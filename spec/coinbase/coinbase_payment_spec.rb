# Inspired from https://github.com/coinbase/coinbase-ruby/blob/master/spec/client_spec.rb
require 'fakeweb'

require 'spec_helper'

class FakeJavaUserAccountApi
  attr_accessor :accounts

  def initialize
    @accounts = []
  end

  def get_account_by_id(id, context)
    @accounts.find { |account| account.id == id.to_s }
  end

  def get_account_by_key(external_key, context)
    @accounts.find { |account| account.external_key == external_key.to_s }
  end
end

describe Killbill::Coinbase::CoinbaseResponse do
  BASE_URI = 'http://fake.com/api/v1' # switching to http (instead of https) seems to help FakeWeb
  MERCHANT_API_BTC_ADDRESS = '37muSN5ZrukVTvyVh3mT5Zc5ew9L9CBare'

  before(:all) do
    Dir.mktmpdir do |dir|
      file = File.new(File.join(dir, 'coinbase.yml'), "w+")
      file.write(<<-eos)
:coinbase:
  :btc_address: '#{MERCHANT_API_BTC_ADDRESS}'
  :api_key: '5678'
  :base_uri: '#{BASE_URI}'
# As defined by spec_helper.rb
:database:
  :adapter: 'sqlite3'
  :database: 'test.db'
      eos
      file.close

      @plugin = Killbill::Coinbase::PaymentPlugin.new
      @plugin.logger = Logger.new(STDOUT)
      @plugin.logger.level = Logger::INFO
      @plugin.conf_dir = File.dirname(file)

      @account_api = FakeJavaUserAccountApi.new
      svcs = {:account_user_api => @account_api}
      @plugin.kb_apis = Killbill::Plugin::KillbillApi.new('coinbase', svcs)

      # Start the plugin here - since the config file will be deleted
      @plugin.start_plugin
    end
  end

  it 'should be able to create and retrieve payment methods' do
    pm = create_payment_method

    pms = @plugin.get_payment_methods(pm.kb_account_id)
    pms.size.should == 1
    pms[0].external_payment_method_id.should == pm.coinbase_api_key

    pm_details = @plugin.get_payment_method_detail(pm.kb_account_id, pm.kb_payment_method_id)
    pm_details.external_payment_method_id.should == pm.coinbase_api_key

    pms_found = @plugin.search_payment_methods pm.coinbase_api_key
    pms_found = pms_found.iterator.to_a
    pms_found.size.should == 1
    pms_found.first.external_payment_method_id.should == pm_details.external_payment_method_id

    @plugin.delete_payment_method(pm.kb_account_id, pm.kb_payment_method_id)

    @plugin.get_payment_methods(pm.kb_account_id).size.should == 0
    lambda { @plugin.get_payment_method_detail(pm.kb_account_id, pm.kb_payment_method_id) }.should raise_error RuntimeError
  end

  it 'should be able to charge and refund' do
    pm = create_payment_method
    amount = BigDecimal.new("0.01")
    currency = 'BTC'
    kb_payment_id = SecureRandom.uuid

    fake_transactions

    fake_send_money MERCHANT_API_BTC_ADDRESS

    payment_response = @plugin.process_payment pm.kb_account_id, kb_payment_id, pm.kb_payment_method_id, amount, currency
    payment_response.amount.should == amount
    payment_response.currency.should == currency
    payment_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    payment_response.status.should == :PENDING
    payment_response.gateway_error.should == "pending"
    payment_response.gateway_error_code.should be_nil
    payment_response.first_payment_reference_id.should == "9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3"
    payment_response.second_payment_reference_id.should == "501a1791f8182b2071000087"

    # Verify our table directly
    response = Killbill::Coinbase::CoinbaseResponse.find_by_api_call_and_kb_payment_id :charge, kb_payment_id
    response.success.should be_true
    response.api_call.should == 'charge'
    response.kb_payment_id.should == kb_payment_id
    response.coinbase_txn_id.should == '501a1791f8182b2071000087'
    response.coinbase_hsh.should == '9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3'
    response.coinbase_created_at.should == '2012-08-01T23:00:49-07:00'
    response.coinbase_request.should == 'f'
    response.coinbase_amount_in_cents.should == -123400000
    response.coinbase_currency.should == 'BTC'
    response.coinbase_notes.should == 'Sample transaction for you!'
    response.coinbase_status.should == 'pending'
    response.coinbase_sender_id.should == '5011f33df8182b142400000e'
    response.coinbase_sender_name.should == 'User Two'
    response.coinbase_sender_email.should == 'user2@example.com'
    response.coinbase_recipient_id.should == '5011f33df8182b142400000a'
    response.coinbase_recipient_name.should == 'User One'
    response.coinbase_recipient_email.should == 'user1@example.com'
    response.coinbase_recipient_address.should == MERCHANT_API_BTC_ADDRESS

    # Verify through the API, this will update the record
    payment_response = @plugin.get_payment_info pm.kb_account_id, kb_payment_id
    payment_response.amount.should == amount
    payment_response.currency.should == currency
    payment_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    payment_response.status.should == :PROCESSED
    payment_response.gateway_error.should == "complete"
    payment_response.gateway_error_code.should be_nil
    payment_response.first_payment_reference_id.should == "9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3"
    payment_response.second_payment_reference_id.should == "501a1791f8182b2071000087"

    # Check we cannot refund an amount greater than the original charge
    lambda { @plugin.process_refund pm.kb_account_id, kb_payment_id, amount + 1, currency }.should raise_error RuntimeError

    fake_send_money 'muVu2JZo8PbewBHRp6bpqFvVD87qvqEHWA'
    fake_receive_address 'muVu2JZo8PbewBHRp6bpqFvVD87qvqEHWA'

    refund_response = @plugin.process_refund pm.kb_account_id, kb_payment_id, amount, currency
    refund_response.amount.should == amount
    refund_response.currency.should == currency
    refund_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    refund_response.status.should == :PENDING
    refund_response.gateway_error.should == "pending"
    refund_response.gateway_error_code.should be_nil
    refund_response.reference_id.should == "9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3"

    # Verify our table directly
    response = Killbill::Coinbase::CoinbaseResponse.find_by_api_call_and_kb_payment_id :refund, kb_payment_id
    response.success.should be_true
    response.api_call.should == 'refund'
    response.kb_payment_id.should == kb_payment_id
    response.coinbase_txn_id.should == '501a1791f8182b2071000087'
    response.coinbase_hsh.should == '9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3'
    response.coinbase_created_at.should == '2012-08-01T23:00:49-07:00'
    response.coinbase_request.should == 'f'
    response.coinbase_amount_in_cents.should == -123400000
    response.coinbase_currency.should == 'BTC'
    response.coinbase_notes.should == 'Sample transaction for you!'
    response.coinbase_status.should == 'pending'
    response.coinbase_sender_id.should == '5011f33df8182b142400000e'
    response.coinbase_sender_name.should == 'User Two'
    response.coinbase_sender_email.should == 'user2@example.com'
    response.coinbase_recipient_id.should == '5011f33df8182b142400000a'
    response.coinbase_recipient_name.should == 'User One'
    response.coinbase_recipient_email.should == 'user1@example.com'
    # Whereas the rest of the response is the same (same mock), the recipient will have changed
    response.coinbase_recipient_address.should == 'muVu2JZo8PbewBHRp6bpqFvVD87qvqEHWA'

    # Verify through the API, this will update the record
    refund_response = @plugin.get_refund_info pm.kb_account_id, kb_payment_id
    refund_response.amount.should == amount
    refund_response.currency.should == currency
    refund_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    refund_response.status.should == :PROCESSED
    refund_response.gateway_error.should == "complete"
    refund_response.gateway_error_code.should be_nil
    refund_response.reference_id.should == "9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3"

    # Make sure we can charge again the same payment method
    second_kb_payment_id = SecureRandom.uuid

    fake_send_money MERCHANT_API_BTC_ADDRESS

    payment_response = @plugin.process_payment pm.kb_account_id, second_kb_payment_id, pm.kb_payment_method_id, amount, currency
    payment_response.amount.should == amount
    payment_response.currency.should == currency
    payment_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    payment_response.status.should == :PENDING
    payment_response.gateway_error.should == "pending"
    payment_response.gateway_error_code.should be_nil
    payment_response.first_payment_reference_id.should == "9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3"
    payment_response.second_payment_reference_id.should == "501a1791f8182b2071000087"
  end

  private

  def fake_send_money(recipient_address)
    response = <<eos
{
  "success": true,
  "transaction": {
    "id": "501a1791f8182b2071000087",
    "created_at": "2012-08-01T23:00:49-07:00",
    "hsh": "9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3",
    "notes": "Sample transaction for you!",
    "amount": {
      "amount": "-1.23400000",
      "currency": "BTC"
    },
    "request": false,
    "status": "pending",
    "sender": {
      "id": "5011f33df8182b142400000e",
      "name": "User Two",
      "email": "user2@example.com"
    },
    "recipient": {
      "id": "5011f33df8182b142400000a",
      "name": "User One",
      "email": "user1@example.com"
    },
    "recipient_address": "#{recipient_address}"
  }
}
eos
    fake :post, "/transactions/send_money", response
  end

  def fake_receive_address(receive_address)
    response = <<eos
{
  "success": true,
  "address": "#{receive_address}",
  "callback_url": null
}
eos
    fake :get, "/account/receive_address", response
  end

  def fake_transactions
    # The second transaction shares the id with 501a1791f8182b2071000087 above
    # to check the status field is updated correctly when fetching the payment or refund info
    response = <<eos
{
  "current_user": {
    "id": "5011f33df8182b142400000e",
    "email": "user2@example.com",
    "name": "User Two"
  },
  "balance": {
    "amount": "50.00000000",
    "currency": "BTC"
  },
  "total_count": 2,
  "num_pages": 1,
  "current_page": 1,
  "transactions": [
    {
      "transaction": {
        "id": "5018f833f8182b129c00002f",
        "created_at": "2012-08-01T02:34:43-07:00",
        "amount": {
          "amount": "-1.10000000",
          "currency": "BTC"
        },
        "request": true,
        "status": "pending",
        "sender": {
          "id": "5011f33df8182b142400000e",
          "name": "User Two",
          "email": "user2@example.com"
        },
        "recipient": {
          "id": "5011f33df8182b142400000a",
          "name": "User One",
          "email": "user1@example.com"
        }
      }
    },
    {
      "transaction": {
        "id": "501a1791f8182b2071000087",
        "created_at": "2012-08-01T23:00:49-07:00",
        "hsh": "9d6a7d1112c3db9de5315b421a5153d71413f5f752aff75bf504b77df4e646a3",
        "amount": {
          "amount": "-1.23400000",
          "currency": "BTC"
        },
        "request": false,
        "status": "complete",
        "sender": {
          "id": "5011f33df8182b142400000e",
          "name": "User Two",
          "email": "user2@example.com"
        },
        "recipient_address": "37muSN5ZrukVTvyVh3mT5Zc5ew9L9CBare"
      }
    }
 ]
}
eos
    fake :get, "/transactions", response
  end

  def create_kb_account(kb_account_id)
    external_key = Time.now.to_i.to_s + '-test'
    email = external_key + '@tester.com'

    account = Killbill::Plugin::Model::Account.new
    account.id = kb_account_id
    account.external_key = external_key
    account.email = email
    account.name = 'Integration spec'
    account.currency = :USD

    @account_api.accounts << account

    return external_key, kb_account_id
  end

  def create_payment_method
    kb_account_id = SecureRandom.uuid
    kb_payment_method_id = SecureRandom.uuid

    # Create a new account
    create_kb_account kb_account_id

    # Generate a token in Coinbase
    coinbase_api_key = '123456789012345678901324567890abcdefghi'

    properties = []
    properties << create_pm_kv_info('apiKey', coinbase_api_key)

    info = Killbill::Plugin::Model::PaymentMethodPlugin.new
    info.properties = properties
    payment_method = @plugin.add_payment_method(kb_account_id, kb_payment_method_id, info, true)

    pm = Killbill::Coinbase::CoinbasePaymentMethod.from_kb_payment_method_id kb_payment_method_id
    pm.should == payment_method
    pm.kb_account_id.should == kb_account_id
    pm.kb_payment_method_id.should == kb_payment_method_id
    pm.coinbase_api_key.should == coinbase_api_key

    pm
  end

  def create_pm_kv_info(key, value)
    prop = Killbill::Plugin::Model::PaymentMethodKVInfo.new
    prop.key = key
    prop.value = value
    prop
  end

  def fake method, path, body
    FakeWeb.register_uri(method, "#{BASE_URI}#{path}", body: body)
  end
end