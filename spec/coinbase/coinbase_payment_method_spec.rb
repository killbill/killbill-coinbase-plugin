require 'spec_helper'

describe Killbill::Coinbase::CoinbasePaymentMethod do
  before :all do
    Killbill::Coinbase::CoinbasePaymentMethod.delete_all
  end

  it 'should generate the right SQL query' do
    # Check count query (search query numeric)
    expected_query = "SELECT COUNT(DISTINCT \"coinbase_payment_methods\".\"id\") FROM \"coinbase_payment_methods\"  WHERE \"coinbase_payment_methods\".\"coinbase_api_key\" = '1234' ORDER BY \"coinbase_payment_methods\".\"id\""
    # Note that Kill Bill will pass a String, even for numeric types
    Killbill::Coinbase::CoinbasePaymentMethod.search_query('1234').to_sql.should == expected_query

    # Check query with results (search query numeric)
    expected_query = "SELECT  DISTINCT \"coinbase_payment_methods\".* FROM \"coinbase_payment_methods\"  WHERE \"coinbase_payment_methods\".\"coinbase_api_key\" = '1234' ORDER BY \"coinbase_payment_methods\".\"id\" LIMIT 10 OFFSET 0"
    # Note that Kill Bill will pass a String, even for numeric types
    Killbill::Coinbase::CoinbasePaymentMethod.search_query('1234', 0, 10).to_sql.should == expected_query

    # Check count query (search query string)
    expected_query = "SELECT COUNT(DISTINCT \"coinbase_payment_methods\".\"id\") FROM \"coinbase_payment_methods\"  WHERE \"coinbase_payment_methods\".\"coinbase_api_key\" = 'XXX' ORDER BY \"coinbase_payment_methods\".\"id\""
    Killbill::Coinbase::CoinbasePaymentMethod.search_query('XXX').to_sql.should == expected_query

    # Check query with results (search query string)
    expected_query = "SELECT  DISTINCT \"coinbase_payment_methods\".* FROM \"coinbase_payment_methods\"  WHERE \"coinbase_payment_methods\".\"coinbase_api_key\" = 'XXX' ORDER BY \"coinbase_payment_methods\".\"id\" LIMIT 10 OFFSET 0"
    Killbill::Coinbase::CoinbasePaymentMethod.search_query('XXX', 0, 10).to_sql.should == expected_query
  end

  it 'should search all fields' do
    do_search('foo').size.should == 0

    pm = Killbill::Coinbase::CoinbasePaymentMethod.create :kb_account_id => '11-22-33-44',
                                                          :kb_payment_method_id => '55-66-77-88',
                                                          :coinbase_api_key => '38102343'

    do_search('foo').size.should == 0
    do_search(pm.coinbase_api_key).size.should == 1
    # Exact match only for api key
    do_search('3810234').size.should == 0
    do_search('38102343').size.should == 1

    pm2 = Killbill::Coinbase::CoinbasePaymentMethod.create :kb_account_id => '22-33-44-55',
                                                           :kb_payment_method_id => '66-77-88-99',
                                                           :coinbase_api_key => '49384029302'

    do_search('foo').size.should == 0
    do_search(pm.coinbase_api_key).size.should == 1
    do_search(pm2.coinbase_api_key).size.should == 1
  end

  private

  def do_search(search_key)
    pagination = Killbill::Coinbase::CoinbasePaymentMethod.search(search_key)
    pagination.current_offset.should == 0
    results = pagination.iterator.to_a
    pagination.total_nb_records.should == results.size
    results
  end
end
