module Killbill::Coinbase
  class CoinbaseResponse < ActiveRecord::Base
    has_one :coinbase_transaction
    attr_accessible :api_call,
                    :kb_payment_id,
                    :coinbase_txn_id,
                    :coinbase_hsh,
                    :coinbase_created_at,
                    :coinbase_request,
                    :coinbase_amount_in_cents,
                    :coinbase_currency,
                    :coinbase_notes,
                    :coinbase_status,
                    :coinbase_sender_id,
                    :coinbase_sender_name,
                    :coinbase_sender_email,
                    :coinbase_recipient_id,
                    :coinbase_recipient_name,
                    :coinbase_recipient_email,
                    :coinbase_recipient_address,
                    :success

    def self.from_response(api_call, kb_payment_id, response)
      coinbase_response = {
                            :api_call => api_call,
                            :kb_payment_id => kb_payment_id,
                            :success => response.success
                          }

      unless response.transaction.blank?
        coinbase_response.merge!({
                                   :coinbase_txn_id => response.transaction.id,
                                   :coinbase_hsh => response.transaction.hsh,
                                   :coinbase_created_at => response.transaction.created_at,
                                   :coinbase_request => response.transaction.request,
                                   # response.transaction.amount is a Money object.
                                   # Note that for BTC, 1 cent is 1 Satoshi (1/100000000)
                                   :coinbase_amount_in_cents => response.transaction.amount.cents,
                                   :coinbase_currency => response.transaction.amount.currency.iso_code,
                                   :coinbase_notes => response.transaction.notes,
                                   :coinbase_status => response.transaction.status,
                                   :coinbase_sender_id => response.transaction.sender.id,
                                   :coinbase_sender_name => response.transaction.sender.name,
                                   :coinbase_sender_email => response.transaction.sender.email,
                                   :coinbase_recipient_id => response.transaction.recipient.id,
                                   :coinbase_recipient_name => response.transaction.recipient.name,
                                   :coinbase_recipient_email => response.transaction.recipient.email,
                                   :coinbase_recipient_address => response.transaction.recipient_address
                                 })
      end

      CoinbaseResponse.new(coinbase_response);
    end

    def update_from_coinbase_transaction(transaction)
      # Are there any other field to update?
      update_attributes(:coinbase_status => transaction.status) unless transaction.nil?
    end

    def to_payment_response
      to_killbill_response :payment
    end

    def to_refund_response
      to_killbill_response :refund
    end

    private

    def to_killbill_response(type)
      if coinbase_transaction.nil?
        amount_in_cents = nil
        currency = nil
        created_date = created_at
        first_payment_reference_id = nil
        second_payment_reference_id = nil
      else
        amount_in_cents = coinbase_transaction.amount_in_cents
        currency = coinbase_transaction.currency
        created_date = coinbase_transaction.created_at
        # We store the hash as the first_payment_reference_id to
        # make sure it is available in the refund info object
        # (required by the killbill-bitcoin-plugin).
        first_payment_reference_id = coinbase_hsh
        second_payment_reference_id = coinbase_txn_id
      end

      if success and coinbase_status == 'pending'
        status = :PENDING
      elsif success and coinbase_status == 'complete'
        status = :PROCESSED
      else
        status = :ERROR
      end
      effective_date = coinbase_created_at
      gateway_error = coinbase_status
      gateway_error_code = nil

      if type == :payment
        p_info_plugin = Killbill::Plugin::Model::PaymentInfoPlugin.new
        p_info_plugin.amount = BigDecimal.new(amount_in_cents.to_s) / 100.0 if amount_in_cents
        p_info_plugin.currency = currency
        p_info_plugin.created_date = created_date
        p_info_plugin.effective_date = effective_date
        p_info_plugin.status = status
        p_info_plugin.gateway_error = gateway_error
        p_info_plugin.gateway_error_code = gateway_error_code
        p_info_plugin.first_payment_reference_id = first_payment_reference_id
        p_info_plugin.second_payment_reference_id = second_payment_reference_id
        p_info_plugin
      else
        r_info_plugin = Killbill::Plugin::Model::RefundInfoPlugin.new
        r_info_plugin.amount = BigDecimal.new(amount_in_cents.to_s) / 100.0 if amount_in_cents
        r_info_plugin.currency = currency
        r_info_plugin.created_date = created_date
        r_info_plugin.effective_date = effective_date
        r_info_plugin.status = status
        r_info_plugin.gateway_error = gateway_error
        r_info_plugin.gateway_error_code = gateway_error_code
        r_info_plugin.reference_id = first_payment_reference_id
        r_info_plugin
      end
    end
  end
end