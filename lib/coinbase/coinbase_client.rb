require 'coinbase'

module Killbill::Coinbase
  class CoinbaseClient
    class << self
      def find_by_transaction_id(pm, tx_id)
        should_use_oauth(pm) ? find_by_transaction_id_via_oauth(pm, tx_id) : find_by_transaction_id_via_api_key(pm, tx_id)
      end

      def charge(pm, amount, currency, description)
        should_use_oauth(pm) ? charge_via_oauth(pm, amount, currency, description) : charge_via_api_key(pm, amount, currency, description)
      end

      def refund(pm, amount, currency, description)
        should_use_oauth(pm) ? refund_via_oauth(pm, amount, currency, description) : refund_via_api_key(pm, amount, currency, description)
      end

      private

      def should_use_oauth(pm)
        !pm.coinbase_access_token.blank? && !pm.coinbase_refresh_token.blank?
      end

      # OAuth

      def find_by_transaction_id_via_oauth(pm, tx_id)
        call_coinbase_via_oauth do
          oauth_token(pm).get('/api/v1/transactions/' + tx_id).body
        end
      end

      def charge_via_oauth(pm, amount, currency, description)
        money_amount = amount.to_money(currency)
        payload = {
          transaction: {
            to: Killbill::Coinbase.merchant_btc_address,
            amount_string: money_amount.to_f.to_s,
            amount_currency_iso: money_amount.currency,
            notes: description
          }
        }

        call_coinbase_via_oauth do
          token = oauth_token(pm)
          resp = token.post('/api/v1/transactions/send_money', { body: payload })
          oauth_response_to_hash(resp)
        end
      end

      def refund_via_oauth(pm, amount, currency, description)
        # No OAuth for the merchant
        refund_via_api_key(pm, amount, currecy, description)
      end

      def oauth_response_to_hash(resp)
        hash = Hashie::Mash.new(JSON.parse(resp.body))
        if hash.error
          hash.message ||= hash.error
        elsif hash.errors
          hash.message ||= hash.errors.join(", ")
        end
        hash.success ||= (hash.error || hash.errors) ? false : true
        hash
      end

      def call_coinbase_via_oauth
        yield
      rescue ::OAuth2::Error => e
        hash = Hashie::Mash.new(e.response.parsed)
        hash.success = false
        hash.message ||= "#{hash.error}: #{hash.error_description}"
        hash
      end

      def oauth_token(pm)
        token = ::OAuth2::AccessToken.new(oauth_client, pm.coinbase_access_token, { refresh_token: pm.coinbase_refresh_token })
        new_token = token.refresh!

        pm.coinbase_access_token = new_token.token
        pm.coinbase_refresh_token = new_token.refresh_token
        pm.save!

        new_token
      end

      def oauth_client
        ::OAuth2::Client.new(Killbill::Coinbase.client_id,
                             Killbill::Coinbase.client_secret,
                             site: 'https://coinbase.com')
      end

      # API Key

      def find_by_transaction_id_via_api_key(pm, tx_id)
        gateway = gateway_for_api_key(pm.coinbase_api_key)

        call_coinbase_via_api_key do
          # TODO https://coinbase.com/api/doc/1.0/transactions/show.html doesn't seem implemented yet :(
          gateway.transactions.transactions.find { |tx| tx.transaction.id == tx_id }
        end
      end

      def charge_via_api_key(pm, amount, currency, description)
        gateway = gateway_for_api_key(pm.coinbase_api_key)
        send_money_via_api_key gateway, Killbill::Coinbase.merchant_btc_address, amount, currency, description
      end

      def refund_via_api_key(pm, amount, currency, description)
        gateway_customer = gateway_for_api_key(pm.coinbase_api_key)
        btc_address = gateway_customer.receive_address.address

        gateway = gateway_for_api_key(Killbill::Coinbase.merchant_api_key)
        send_money_via_api_key gateway, btc_address, amount, currency, description
      end

      def send_money_via_api_key(sender_gateway, recipient_address, amount, currency, description)
        call_coinbase_via_api_key do
          sender_gateway.send_money recipient_address, amount.to_money(currency), description
        end
      end

      def call_coinbase_via_api_key
        yield
      rescue Coinbase::Client::Error => e
        hash = Hashie::Mash.new
        hash.success = false
        hash.message = e.message
        hash
      end

      def gateway_for_api_key(api_key)
        ::Coinbase::Client.new(api_key, { :base_uri => Killbill::Coinbase.base_uri })
      end
    end
  end
end