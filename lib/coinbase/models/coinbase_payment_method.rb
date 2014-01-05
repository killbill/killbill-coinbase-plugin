module Killbill::Coinbase
  class CoinbasePaymentMethod < ActiveRecord::Base
    attr_accessible :kb_account_id,
                    :kb_payment_method_id,
                    :coinbase_api_key

    alias_attribute :external_payment_method_id, :coinbase_api_key

    def self.from_kb_account_id(kb_account_id)
      find_all_by_kb_account_id_and_is_deleted(kb_account_id, false)
    end

    def self.from_kb_payment_method_id(kb_payment_method_id)
      payment_methods = find_all_by_kb_payment_method_id_and_is_deleted(kb_payment_method_id, false)
      raise "No payment method found for payment method #{kb_payment_method_id}" if payment_methods.empty?
      raise "Killbill payment method mapping to multiple active Coinbase tokens for payment method #{kb_payment_method_id}" if payment_methods.size > 1
      payment_methods[0]
    end

    def self.mark_as_deleted!(kb_payment_method_id)
      payment_method = from_kb_payment_method_id(kb_payment_method_id)
      payment_method.is_deleted = true
      payment_method.save!
    end

    # VisibleForTesting
    def self.search_query(search_key, offset = nil, limit = nil)
      t = self.arel_table

      # Exact match for coinbase_api_key
      where_clause = t[:coinbase_api_key].eq(search_key)

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

    def self.search(search_key, offset = 0, limit = 100)
      pagination = Killbill::Plugin::Model::Pagination.new
      pagination.current_offset = offset
      pagination.total_nb_records = self.count_by_sql(self.search_query(search_key))
      pagination.max_nb_records = self.count
      pagination.next_offset = (!pagination.total_nb_records.nil? && offset + limit >= pagination.total_nb_records) ? nil : offset + limit
      # Reduce the limit if the specified value is larger than the number of records
      actual_limit = [pagination.max_nb_records, limit].min
      pagination.iterator = StreamyResultSet.new(actual_limit) do |offset,limit|
        self.find_by_sql(self.search_query(search_key, offset, limit))
            .map(&:to_payment_method_response)
      end
      pagination
    end

    def to_payment_method_response
      properties = []
      properties << create_pm_kv_info('apiKey', external_payment_method_id)

      pm_plugin = Killbill::Plugin::Model::PaymentMethodPlugin.new
      pm_plugin.kb_payment_method_id = kb_payment_method_id
      pm_plugin.external_payment_method_id = external_payment_method_id
      pm_plugin.is_default_payment_method = is_default
      pm_plugin.properties = properties
      pm_plugin.type = 'AltCoin'
      pm_plugin.cc_name = nil
      pm_plugin.cc_type = nil
      pm_plugin.cc_expiration_month = nil
      pm_plugin.cc_expiration_year = nil
      pm_plugin.cc_last4 = nil
      pm_plugin.address1 = nil
      pm_plugin.address2 = nil
      pm_plugin.city = nil
      pm_plugin.state = nil
      pm_plugin.zip = nil
      pm_plugin.country = nil

      pm_plugin
    end

    def to_payment_method_info_response
      pm_info_plugin = Killbill::Plugin::Model::PaymentMethodInfoPlugin.new
      pm_info_plugin.account_id = kb_account_id
      pm_info_plugin.payment_method_id = kb_payment_method_id
      pm_info_plugin.is_default = is_default
      pm_info_plugin.external_payment_method_id = external_payment_method_id
      pm_info_plugin
    end

    def is_default
      # No concept of default payment method in Coinbase
      false
    end

    private

    def create_pm_kv_info(key, value)
      prop = Killbill::Plugin::Model::PaymentMethodKVInfo.new
      prop.key = key
      prop.value = value
      prop
    end
  end
end
