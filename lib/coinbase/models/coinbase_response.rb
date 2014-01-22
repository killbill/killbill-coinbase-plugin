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
                    :message,
                    :success

    alias_attribute :processed_amount_in_cents, :coinbase_amount_in_cents
    alias_attribute :processed_currency, :coinbase_currency

    def self.from_response(api_call, kb_payment_id, response)
      coinbase_response = {
                            :api_call => api_call,
                            :kb_payment_id => kb_payment_id,
                            :message => response.message,
                            :success => response.success
                          }

      unless response.transaction.blank?
        coinbase_response.merge!({
                                   :coinbase_txn_id => response.transaction.id,
                                   # We may not get the hash right away, but it will be eventually
                                   # populated (see update_from_coinbase_transaction below)
                                   # Also, we don't get one if we are sending funds between Coinbase accounts
                                   :coinbase_hsh => response.transaction.hsh,
                                   :coinbase_created_at => response.transaction.created_at,
                                   :coinbase_request => response.transaction.request,
                                   :coinbase_notes => response.transaction.notes,
                                   :coinbase_status => response.transaction.status
                                })

        unless response.transaction.amount.blank?
          coinbase_response.merge!({
                                     # response.transaction.amount can be a Money object.
                                     # Note that for BTC, 1 cent is 1 Satoshi (1/100000000)
                                     :coinbase_amount_in_cents => response.transaction.amount.cents,
                                     :coinbase_currency => response.transaction.amount.currency.is_a?(Money::Currency) ? response.transaction.amount.currency.iso_code : response.transaction.amount.currency
                                  })
        end

        unless response.transaction.sender.blank?
          coinbase_response.merge!({
                                     :coinbase_sender_id => response.transaction.sender.id,
                                     :coinbase_sender_name => response.transaction.sender.name,
                                     :coinbase_sender_email => response.transaction.sender.email
                                  })
        end

        unless response.transaction.recipient.blank?
          coinbase_response.merge!({
                                     :coinbase_recipient_id => response.transaction.recipient.id,
                                     :coinbase_recipient_name => response.transaction.recipient.name,
                                     :coinbase_recipient_email => response.transaction.recipient.email,
                                     :coinbase_recipient_address => response.transaction.recipient_address
                                  })
        end
      end

      CoinbaseResponse.new(coinbase_response);
    end

    def self.start_refreshing_transactions(delay = 120, logger = nil)
      Thread.every(delay) {
        to_refresh = 0
        refreshed = 0

        Killbill::Coinbase::CoinbaseResponse.where(:coinbase_status => 'pending').each do |response|
          to_refresh += 1

          coinbase_transaction = response.coinbase_transaction
          pm = coinbase_transaction.coinbase_payment_method

          # Go to Coinbase to update the transaction state
          transaction = CoinbaseClient.find_by_transaction_id(pm, coinbase_transaction.coinbase_txn_id)

          unless transaction.nil?
            new_response = response.update_from_coinbase_transaction(transaction.transaction)
            if transaction.transaction.status != 'pending'
              refreshed += 1

              # Update the state in Kill Bill if required
              if Killbill::Coinbase.transactions_refresh_update_killbill
                success = (transaction.transaction.status == 'complete')

                context = Killbill::Coinbase.kb_apis.create_context
                kb_account_id = Killbill::Coinbase.kb_apis.payment_api.get_payment(response.kb_payment_id, false, context).get_account_id
                account = Killbill::Coinbase.kb_apis.account_user_api.get_account_by_id(kb_account_id, context)
                if response.api_call == 'charge'
                  Killbill::Coinbase.kb_apis.payment_api.notify_pending_payment_of_state_changed(account, response.kb_payment_id, success, context)
                elsif response.api_call == 'refund'
                  Killbill::Coinbase.kb_apis.payment_api.notify_pending_refund_of_state_changed(account, response.kb_payment_id, success, context)
                end
              end
            end
          end
        end

        logger.info "Refreshed #{refreshed}/#{to_refresh} transaction(s) with Coinbase" if !logger.nil? and to_refresh > 0
      }
    end

    def update_from_coinbase_transaction(transaction)
      # Are there any other field to update?
      update_attributes(:coinbase_status => transaction.status, :coinbase_hsh => transaction.hsh) unless transaction.nil?
    end

    def to_payment_response
      to_killbill_response :payment
    end

    def to_refund_response
      to_killbill_response :refund
    end

    # VisibleForTesting
    def self.search_query(api_call, search_key, offset = nil, limit = nil)
      t = self.arel_table

      # Exact matches only
      where_clause =     t[:coinbase_txn_id].eq(search_key)
                     .or(t[:coinbase_hsh].eq(search_key))
                     .or(t[:coinbase_sender_id].eq(search_key))
                     .or(t[:coinbase_sender_email].eq(search_key))
                     .or(t[:coinbase_recipient_id].eq(search_key))
                     .or(t[:coinbase_recipient_email].eq(search_key))

      # Only search successful payments and refunds
      where_clause = where_clause.and(t[:api_call].eq(api_call))
                                 .and(t[:success].eq(true))

      query = t.where(where_clause)
               .order(t[:id])

      if offset.blank? and limit.blank?
        # true is for count distinct
        query.project(t[:id].count(true))
      else
        query.skip(offset) unless offset.blank?
        query.take(limit) unless limit.blank?
        query.project(t[Arel.star])
        # Not chainable
        query.distinct
      end
      query
    end

    def self.search(search_key, offset = 0, limit = 100, type = :payment)
      api_call = type == :payment ? 'charge' : 'refund'
      pagination = Killbill::Plugin::Model::Pagination.new
      pagination.current_offset = offset
      pagination.total_nb_records = self.count_by_sql(self.search_query(api_call, search_key))
      pagination.max_nb_records = self.where(:api_call => api_call, :success => true).count
      pagination.next_offset = (!pagination.total_nb_records.nil? && offset + limit >= pagination.total_nb_records) ? nil : offset + limit
      # Reduce the limit if the specified value is larger than the number of records
      actual_limit = [pagination.max_nb_records, limit].min
        pagination.iterator = StreamyResultSet.new(actual_limit) do |offset,limit|
        self.find_by_sql(self.search_query(api_call, search_key, offset, limit))
            .map { |x| type == :payment ? x.to_payment_response : x.to_refund_response }
      end
      pagination
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
        amount_in_cents = coinbase_transaction.processed_amount_in_cents
        currency = coinbase_transaction.processed_currency
        created_date = coinbase_transaction.created_at
        first_reference_id = coinbase_hsh
        second_reference_id = coinbase_txn_id
      end

      if success and (!coinbase_hsh.blank? or coinbase_status == 'pending')
        # If we have a hash, always mark it as pending so the bitcoin-plugin
        # can monitor confirmations for that hash
        status = :PENDING
      elsif success and coinbase_status == 'complete'
        # For Coinbase to Coinbase exchanges, we won't have a hash unfortunately
        # and the coinbase_status will be complete right away. We have to trust
        # them in that case since we can't monitor confirmations
        status = :PROCESSED
      else
        status = :ERROR
      end
      effective_date = coinbase_created_at
      gateway_error = message
      gateway_error_code = nil

      if type == :payment
        p_info_plugin = Killbill::Plugin::Model::PaymentInfoPlugin.new
        p_info_plugin.kb_payment_id = kb_payment_id
        p_info_plugin.amount = Money.new(amount_in_cents, currency).to_d if currency
        p_info_plugin.currency = currency
        p_info_plugin.created_date = created_date
        p_info_plugin.effective_date = effective_date
        p_info_plugin.status = status
        p_info_plugin.gateway_error = gateway_error
        p_info_plugin.gateway_error_code = gateway_error_code
        p_info_plugin.first_payment_reference_id = first_reference_id
        p_info_plugin.second_payment_reference_id = second_reference_id
        p_info_plugin
      else
        r_info_plugin = Killbill::Plugin::Model::RefundInfoPlugin.new
        r_info_plugin.kb_payment_id = kb_payment_id
        r_info_plugin.amount = Money.new(amount_in_cents, currency).to_d if currency
        r_info_plugin.currency = currency
        r_info_plugin.created_date = created_date
        r_info_plugin.effective_date = effective_date
        r_info_plugin.status = status
        r_info_plugin.gateway_error = gateway_error
        r_info_plugin.gateway_error_code = gateway_error_code
        r_info_plugin.first_refund_reference_id = first_reference_id
        r_info_plugin.second_refund_reference_id = second_reference_id
        r_info_plugin
      end
    end
  end
end
