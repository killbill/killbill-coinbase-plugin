module Killbill::Coinbase
  class PaymentPlugin < Killbill::Plugin::Payment
    def start_plugin
      Killbill::Coinbase.initialize! @logger, @conf_dir, @kb_apis

      @transactions_refreshes = Killbill::Coinbase::CoinbaseResponse.start_refreshing_transactions Killbill::Coinbase.transactions_refresh_interval, @logger

      super

      @logger.info 'Killbill::Coinbase::PaymentPlugin started'
    end

    def stop_plugin
      @transactions_refreshes.cancel

      super

      @logger.info 'Killbill::Coinbase::PaymentPlugin stopped'
    end

    # return DB connections to the Pool if required
    def after_request
      ActiveRecord::Base.connection.close
    end

    def process_payment(kb_account_id, kb_payment_id, kb_payment_method_id, amount, currency, call_context = nil, options = {})
      # Use Money to compute the amount in cents, as it depends on the currency (1 cent of BTC is 1 Satoshi, not 0.01 BTC)
      amount_in_cents = Money.new_with_amount(amount, currency).cents.to_i
      description = options[:description] || "Kill Bill payment for #{kb_payment_id}"

      # If the payment was already made, just return the status
      coinbase_transaction = CoinbaseTransaction.from_kb_payment_id(kb_payment_id) rescue nil
      return coinbase_transaction.coinbase_response.to_payment_response unless coinbase_transaction.nil?

      # Retrieve the Coinbase payment method
      coinbase_pm = CoinbasePaymentMethod.from_kb_payment_method_id(kb_payment_method_id)

      # Go to Coinbase
      gateway = Killbill::Coinbase.gateway_for_api_key(coinbase_pm.coinbase_api_key)
      coinbase_response = gateway.send_money Killbill::Coinbase.merchant_btc_address, amount.to_money(currency), description

      # Regardless of the input currency, the actual payment is in BTC
      response = save_response_and_transaction coinbase_response, :charge, kb_payment_id, kb_payment_method_id, amount_in_cents, 'BTC'

      response.to_payment_response
    end

    def get_payment_info(kb_account_id, kb_payment_id, tenant_context = nil, options = {})
      coinbase_transaction = CoinbaseTransaction.from_kb_payment_id(kb_payment_id)

      # Go to Coinbase to update the transaction state
      gateway = Killbill::Coinbase.gateway_for_api_key(coinbase_transaction.coinbase_payment_method.coinbase_api_key)
      # TODO https://coinbase.com/api/doc/1.0/transactions/show.html doesn't seem implemented yet :(
      transaction = gateway.transactions.transactions.find { |tx| tx.transaction.id == coinbase_transaction.coinbase_txn_id }
      coinbase_transaction.coinbase_response.update_from_coinbase_transaction(transaction.transaction) unless transaction.nil?

      coinbase_transaction.coinbase_response.to_payment_response
    end

    def process_refund(kb_account_id, kb_payment_id, amount, currency, call_context = nil, options = {})
      # Use Money to compute the amount in cents, as it depends on the currency (1 cent of BTC is 1 Satoshi, not 0.01 BTC)
      amount_in_cents = Money.new_with_amount(amount, currency).cents.to_i
      description = options[:description] || "Kill Bill refund for #{kb_payment_id}"

      # Retrieve the transaction
      coinbase_transaction = CoinbaseTransaction.find_candidate_transaction_for_refund(kb_payment_id, amount)

      # Go to Coinbase
      gateway = Killbill::Coinbase.gateway_for_api_key(Killbill::Coinbase.merchant_api_key)
      btc_address = gateway.receive_address.address
      coinbase_response = gateway.send_money btc_address, amount.to_money(currency), description

      # Regardless of the input currency, the actual refund is in BTC
      response = save_response_and_transaction coinbase_response, :refund, kb_payment_id, coinbase_transaction.kb_payment_method_id, amount_in_cents, 'BTC'

      response.to_refund_response
    end

    def get_refund_info(kb_account_id, kb_payment_id, tenant_context = nil, options = {})
      coinbase_transactions = CoinbaseTransaction.refunds_from_kb_payment_id(kb_payment_id)

      refund_infos = []
      coinbase_transactions.each do |coinbase_transaction|
        # Go to Coinbase to update the transaction state
        gateway = Killbill::Coinbase.gateway_for_api_key(coinbase_transaction.coinbase_payment_method.coinbase_api_key)
        # TODO https://coinbase.com/api/doc/1.0/transactions/show.html doesn't seem implemented yet :(
        transaction = gateway.transactions.transactions.find { |tx| tx.transaction.id == coinbase_transaction.coinbase_txn_id }
        coinbase_transaction.coinbase_response.update_from_coinbase_transaction(transaction.transaction) unless transaction.nil?

        refund_infos << coinbase_transaction.coinbase_response.to_refund_response
      end
      refund_infos
    end

    def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default, call_context = nil, options = {})
      api_key = find_value_from_payment_method_props payment_method_props, Killbill::Coinbase::CoinbasePaymentMethod::COINBASE_API_KEY_KEY
      access_token = find_value_from_payment_method_props payment_method_props, Killbill::Coinbase::CoinbasePaymentMethod::COINBASE_ACCESS_TOKEN_KEY
      refresh_token = find_value_from_payment_method_props payment_method_props, Killbill::Coinbase::CoinbasePaymentMethod::COINBASE_REFRESH_TOKEN_KEY
      raise ArgumentError.new("No api key specified") if (api_key.blank? and access_token.blank?)

      pm = CoinbasePaymentMethod.new :kb_account_id => kb_account_id,
                                     :kb_payment_method_id => kb_payment_method_id
      pm.coinbase_api_key = api_key
      pm.coinbase_access_token = access_token
      pm.coinbase_refresh_token = refresh_token
      pm.save!

      pm
    end

    def delete_payment_method(kb_account_id, kb_payment_method_id, call_context = nil, options = {})
      CoinbasePaymentMethod.mark_as_deleted! kb_payment_method_id
    end

    def get_payment_method_detail(kb_account_id, kb_payment_method_id, tenant_context = nil, options = {})
      CoinbasePaymentMethod.from_kb_payment_method_id(kb_payment_method_id).to_payment_method_response
    end

    def set_default_payment_method(kb_account_id, kb_payment_method_id, call_context = nil, options = {})
      # No-op
    end

    def get_payment_methods(kb_account_id, refresh_from_gateway = false, call_context = nil, options = {})
      CoinbasePaymentMethod.from_kb_account_id(kb_account_id).collect { |pm| pm.to_payment_method_info_response }
    end

    def reset_payment_methods(kb_account_id, payment_methods)
      # No-op. We cannot match them.
    end

    def search_payments(search_key, offset = 0, limit = 100, call_context = nil, options = {})
      CoinbaseResponse.search(search_key, offset, limit, :payment)
    end

    def search_refunds(search_key, offset = 0, limit = 100, call_context = nil, options = {})
      CoinbaseResponse.search(search_key, offset, limit, :refund)
    end

    def search_payment_methods(search_key, offset = 0, limit = 100, call_context = nil, options = {})
      CoinbasePaymentMethod.search(search_key, offset, limit)
    end

    private

    def find_value_from_payment_method_props(payment_method_props, key)
      prop = (payment_method_props.properties.find { |kv| kv.key == key })
      prop.nil? ? nil : prop.value
    end

    def save_response_and_transaction(coinbase_response, api_call, kb_payment_id=nil, kb_payment_method_id=nil, amount_in_cents=0, currency=nil)
      @logger.warn "Unsuccessful #{api_call}: #{coinbase_response.message}" unless coinbase_response.success?

      # Save the response to our logs
      response = CoinbaseResponse.from_response(api_call, kb_payment_id, coinbase_response)
      response.save!

      if response.success and !kb_payment_id.blank? and !response.coinbase_txn_id.blank?
        # Record the transaction
        transaction = response.create_coinbase_transaction!(:amount_in_cents => amount_in_cents,
                                                            :currency => currency,
                                                            # Coinbase return negative values for charges
                                                            :processed_amount_in_cents => response.processed_amount_in_cents.abs,
                                                            :processed_currency => response.processed_currency,
                                                            :api_call => api_call,
                                                            :kb_payment_id => kb_payment_id,
                                                            :kb_payment_method_id => kb_payment_method_id,
                                                            :coinbase_txn_id => response.coinbase_txn_id)
        @logger.debug "Recorded transaction: #{transaction.inspect}"
      end
      response
    end
  end
end
