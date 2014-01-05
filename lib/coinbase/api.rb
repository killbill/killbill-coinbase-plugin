module Killbill::Coinbase
  class PaymentPlugin < Killbill::Plugin::Payment
    def start_plugin
      Killbill::Coinbase.initialize! @logger, @conf_dir, @kb_apis

      super

      @logger.info 'Killbill::Coinbase::PaymentPlugin started'
    end

    # return DB connections to the Pool if required
    def after_request
      ActiveRecord::Base.connection.close
    end

    def process_payment(kb_account_id, kb_payment_id, kb_payment_method_id, amount, currency, call_context = nil, options = {})
      amount_in_cents = (amount * 100).to_i
      description = options[:description] || "Kill Bill payment for #{kb_payment_id}"

      # If the payment was already made, just return the status
      coinbase_transaction = CoinbaseTransaction.from_kb_payment_id(kb_payment_id) rescue nil
      return coinbase_transaction.coinbase_response.to_payment_response unless coinbase_transaction.nil?

      # Retrieve the Coinbase payment method
      coinbase_pm = CoinbasePaymentMethod.from_kb_payment_method_id(kb_payment_method_id)

      merchant_address = Killbill::Coinbase.config[:coinbase][:btc_address]

      # Go to Coinbase
      gateway = Killbill::Coinbase.gateway_for_api_key(coinbase_pm.api_key)
      coinbase_response = coinbase.send_money merchant_address, amount.to_money(currency), description

      # Regardless of the input currency, the actual payment is in BTC
      response = save_response_and_transaction coinbase_response, :charge, kb_payment_id, amount_in_cents, 'BTC'

      response.to_payment_response
    end


    def get_payment_info(kb_account_id, kb_payment_id, tenant_context = nil, options = {})
      # We assume the payment is immutable in Coinbase and only look at our tables
      # (https://coinbase.com/api/doc/1.0/transactions/show.html doesn't seem implemented yet)
      coinbase_transaction = CoinbaseTransaction.from_kb_payment_id(kb_payment_id)

      coinbase_transaction.coinbase_response.to_payment_response
    end

    def process_refund(kb_account_id, kb_payment_id, amount, currency, call_context = nil, options = {})
      amount_in_cents = (amount * 100).to_i
      description = options[:description] || "Kill Bill refund for #{kb_payment_id}"

      # Retrieve the transaction
      coinbase_transaction = CoinbaseTransaction.find_candidate_transaction_for_refund(kb_payment_id, actual_amount)

      # Go to Coinbase
      gateway = Killbill::Coinbase.gateway_for_api_key(Killbill::Coinbase.config[:coinbase][:api_key])
      coinbase_response = coinbase.send_money merchant_address, amount.to_money(currency), description

      # Regardless of the input currency, the actual refund is in BTC
      response = save_response_and_transaction coinbase_response, :refund, kb_payment_id, amount_in_cents, 'BTC'

      response.to_refund_response
    end

    def get_refund_info(kb_account_id, kb_payment_id, tenant_context = nil, options = {})
      # We assume the payment is immutable in Coinbase and only look at our tables
      coinbase_transaction = CoinbaseTransaction.refund_from_kb_payment_id(kb_payment_id)

      coinbase_transaction.coinbase_response.to_refund_response
    end

    def add_payment_method(kb_account_id, kb_payment_method_id, payment_method_props, set_default, call_context = nil, options = {})
      api_key = find_value_from_payment_method_props payment_method_props, 'apiKey'
      raise ArgumentError.new("No api key specified") if (api_key.blank?)

      currency = account_currency(kb_account_id)
      CoinbasePaymentMethod.create :kb_account_id => kb_account_id,
                                   :kb_payment_method_id => kb_payment_method_id,
                                   :coinbase_api_key => api_key
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
      return if payment_methods.nil?

      coinbase_pms = CoinbasePaymentMethod.from_kb_account_id(kb_account_id)

      payment_methods.delete_if do |payment_method_info_plugin|
        should_be_deleted = false
        coinbase_pms.each do |coinbase_pm|
          # Do coinbase_pm and payment_method_info_plugin represent the same Coinbase payment method?
          if coinbase_pm.external_payment_method_id == payment_method_info_plugin.external_payment_method_id
            # Do we already have a kb_payment_method_id?
            if coinbase_pm.kb_payment_method_id == payment_method_info_plugin.payment_method_id
              should_be_deleted = true
              break
            elsif coinbase_pm.kb_payment_method_id.nil?
              # We didn't have the kb_payment_method_id - update it
              coinbase_pm.kb_payment_method_id = payment_method_info_plugin.payment_method_id
              should_be_deleted = coinbase_pm.save
              break
              # Otherwise the same token points to 2 different kb_payment_method_id. This should never happen,
              # but we cowardly will insert a second row below
            end
          end
        end

        should_be_deleted
      end

      # The remaining elements in payment_methods are not in our table (this should never happen?!)
      payment_methods.each do |payment_method_info_plugin|
        CoinbasePaymentMethod.create :kb_account_id => payment_method_info_plugin.account_id,
                                     :kb_payment_method_id => payment_method_info_plugin.payment_method_id,
                                     :coinbase_api_key => payment_method_info_plugin.external_payment_method_id
      end
    end

    def search_payment_methods(search_key, offset = 0, limit = 100, call_context = nil, options = {})
      CoinbasePaymentMethod.search(search_key, offset, limit)
    end

    private

    def find_value_from_payment_method_props(payment_method_props, key)
      prop = (payment_method_props.properties.find { |kv| kv.key == key })
      prop.nil? ? nil : prop.value
    end

    def account_currency(kb_account_id)
      account = @kb_apis.account_user_api.get_account_by_id(kb_account_id, @kb_apis.create_context)
      account.currency
    end

    def save_response_and_transaction(coinbase_response, api_call, kb_payment_id=nil, amount_in_cents=0, currency=nil)
      @logger.warn "Unsuccessful #{api_call}: #{coinbase_response.message}" unless coinbase_response.success?

      # Save the response to our logs
      response = CoinbaseResponse.from_response(api_call, kb_payment_id, coinbase_response)
      response.save!

      if response.success and !kb_payment_id.blank? and !response.coinbase_txn_id.blank?
        # Record the transaction
        transaction = response.create_coinbase_transaction!(:amount_in_cents => amount_in_cents,
                                                            :currency => currency,
                                                            :api_call => api_call,
                                                            :kb_payment_id => kb_payment_id,
                                                            :coinbase_txn_id => response.coinbase_txn_id)
        @logger.debug "Recorded transaction: #{transaction.inspect}"
      end
      response
    end
  end
end
