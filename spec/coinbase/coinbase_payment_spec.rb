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
    "recipient_address": "#{MERCHANT_API_BTC_ADDRESS}"
  }
}
eos
    fake :post, "/transactions/send_money", response

    response = <<eos
{
  "success": true,
  "address": "muVu2JZo8PbewBHRp6bpqFvVD87qvqEHWA",
  "callback_url": null
}
eos
    fake :get, "/account/receive_address", response

    pm = create_payment_method
    amount = BigDecimal.new("0.01")
    currency = 'BTC'
    kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.process_payment pm.kb_account_id, kb_payment_id, pm.kb_payment_method_id, amount, currency
    payment_response.amount.should == amount
    payment_response.currency.should == currency
    payment_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    payment_response.status.should == :PENDING
    payment_response.gateway_error.should == "pending"
    payment_response.gateway_error_code.should be_nil
    payment_response.first_payment_reference_id.should == "501a1791f8182b2071000087"
    payment_response.second_payment_reference_id.should be_nil

    # Verify our table directly
    response = Killbill::Coinbase::CoinbaseResponse.find_by_api_call_and_kb_payment_id :charge, kb_payment_id
    response.success.should be_true
    response.api_call.should == 'charge'
    response.kb_payment_id.should == kb_payment_id
    response.coinbase_txn_id.should == '501a1791f8182b2071000087'
    response.coinbase_created_at.should == '2012-08-01T23:00:49-07:00'
    response.coinbase_request.should == 'f'
    response.coinbase_status.should == 'pending'
    response.coinbase_sender_id.should == '5011f33df8182b142400000e'
    response.coinbase_sender_name.should == 'User Two'
    response.coinbase_sender_email.should == 'user2@example.com'
    response.coinbase_recipient_id.should == '5011f33df8182b142400000a'
    response.coinbase_recipient_name.should == 'User One'
    response.coinbase_recipient_email.should == 'user1@example.com'

    payment_response = @plugin.get_payment_info pm.kb_account_id, kb_payment_id
    payment_response.amount.should == amount
    payment_response.currency.should == currency
    payment_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    payment_response.status.should == :PENDING
    payment_response.gateway_error.should == "pending"
    payment_response.gateway_error_code.should be_nil
    payment_response.first_payment_reference_id.should == "501a1791f8182b2071000087"
    payment_response.second_payment_reference_id.should be_nil

    # Check we cannot refund an amount greater than the original charge
    lambda { @plugin.process_refund pm.kb_account_id, kb_payment_id, amount + 1, currency }.should raise_error RuntimeError

    refund_response = @plugin.process_refund pm.kb_account_id, kb_payment_id, amount, currency
    refund_response.amount.should == amount
    refund_response.currency.should == currency
    refund_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    refund_response.status.should == :PENDING
    refund_response.gateway_error.should == "pending"
    refund_response.gateway_error_code.should be_nil
    refund_response.reference_id.should == "501a1791f8182b2071000087"

    # Verify our table directly
    response = Killbill::Coinbase::CoinbaseResponse.find_by_api_call_and_kb_payment_id :refund, kb_payment_id
    response.success.should be_true
    response.api_call.should == 'refund'
    response.kb_payment_id.should == kb_payment_id
    response.coinbase_txn_id.should == '501a1791f8182b2071000087'
    response.coinbase_created_at.should == '2012-08-01T23:00:49-07:00'
    response.coinbase_request.should == 'f'
    response.coinbase_status.should == 'pending'
    response.coinbase_sender_id.should == '5011f33df8182b142400000e'
    response.coinbase_sender_name.should == 'User Two'
    response.coinbase_sender_email.should == 'user2@example.com'
    response.coinbase_recipient_id.should == '5011f33df8182b142400000a'
    response.coinbase_recipient_name.should == 'User One'
    response.coinbase_recipient_email.should == 'user1@example.com'

    # Check we can retrieve the refund
    refund_response = @plugin.get_refund_info pm.kb_account_id, kb_payment_id
    refund_response.amount.should == amount
    refund_response.currency.should == currency
    refund_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    refund_response.status.should == :PENDING
    refund_response.gateway_error.should == "pending"
    refund_response.gateway_error_code.should be_nil
    refund_response.reference_id.should == "501a1791f8182b2071000087"

    # Make sure we can charge again the same payment method
    second_kb_payment_id = SecureRandom.uuid

    payment_response = @plugin.process_payment pm.kb_account_id, second_kb_payment_id, pm.kb_payment_method_id, amount, currency
    payment_response.amount.should == amount
    payment_response.currency.should == currency
    payment_response.effective_date.should == "2012-08-01T23:00:49-07:00"
    payment_response.status.should == :PENDING
    payment_response.gateway_error.should == "pending"
    payment_response.gateway_error_code.should be_nil
    payment_response.first_payment_reference_id.should == "501a1791f8182b2071000087"
    payment_response.second_payment_reference_id.should be_nil
  end

  private

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