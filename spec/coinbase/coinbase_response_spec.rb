require 'spec_helper'

describe Killbill::Coinbase::CoinbaseResponse do
  before :all do
    Killbill::Coinbase::CoinbaseResponse.delete_all
  end

  it 'should generate the right SQL query' do
    # Check count query (search query numeric)
    expected_query = "SELECT COUNT(DISTINCT \"coinbase_responses\".\"id\") FROM \"coinbase_responses\"  WHERE (((((\"coinbase_responses\".\"coinbase_txn_id\" = '1234' OR \"coinbase_responses\".\"coinbase_hsh\" = '1234') OR \"coinbase_responses\".\"coinbase_sender_id\" = '1234') OR \"coinbase_responses\".\"coinbase_sender_email\" = '1234') OR \"coinbase_responses\".\"coinbase_recipient_id\" = '1234') OR \"coinbase_responses\".\"coinbase_recipient_email\" = '1234') AND \"coinbase_responses\".\"api_call\" = 'charge' AND \"coinbase_responses\".\"success\" = 't' ORDER BY \"coinbase_responses\".\"id\""
    # Note that Kill Bill will pass a String, even for numeric types
    Killbill::Coinbase::CoinbaseResponse.search_query('charge', '1234').to_sql.should == expected_query

    # Check query with results (search query numeric)
    expected_query = "SELECT  DISTINCT \"coinbase_responses\".* FROM \"coinbase_responses\"  WHERE (((((\"coinbase_responses\".\"coinbase_txn_id\" = '1234' OR \"coinbase_responses\".\"coinbase_hsh\" = '1234') OR \"coinbase_responses\".\"coinbase_sender_id\" = '1234') OR \"coinbase_responses\".\"coinbase_sender_email\" = '1234') OR \"coinbase_responses\".\"coinbase_recipient_id\" = '1234') OR \"coinbase_responses\".\"coinbase_recipient_email\" = '1234') AND \"coinbase_responses\".\"api_call\" = 'charge' AND \"coinbase_responses\".\"success\" = 't' ORDER BY \"coinbase_responses\".\"id\" LIMIT 10 OFFSET 0"
    # Note that Kill Bill will pass a String, even for numeric types
    Killbill::Coinbase::CoinbaseResponse.search_query('charge', '1234', 0, 10).to_sql.should == expected_query

    # Check count query (search query string)
    expected_query = "SELECT COUNT(DISTINCT \"coinbase_responses\".\"id\") FROM \"coinbase_responses\"  WHERE (((((\"coinbase_responses\".\"coinbase_txn_id\" = 'XXX' OR \"coinbase_responses\".\"coinbase_hsh\" = 'XXX') OR \"coinbase_responses\".\"coinbase_sender_id\" = 'XXX') OR \"coinbase_responses\".\"coinbase_sender_email\" = 'XXX') OR \"coinbase_responses\".\"coinbase_recipient_id\" = 'XXX') OR \"coinbase_responses\".\"coinbase_recipient_email\" = 'XXX') AND \"coinbase_responses\".\"api_call\" = 'charge' AND \"coinbase_responses\".\"success\" = 't' ORDER BY \"coinbase_responses\".\"id\""
    Killbill::Coinbase::CoinbaseResponse.search_query('charge', 'XXX').to_sql.should == expected_query

    # Check query with results (search query string)
    expected_query = "SELECT  DISTINCT \"coinbase_responses\".* FROM \"coinbase_responses\"  WHERE (((((\"coinbase_responses\".\"coinbase_txn_id\" = 'XXX' OR \"coinbase_responses\".\"coinbase_hsh\" = 'XXX') OR \"coinbase_responses\".\"coinbase_sender_id\" = 'XXX') OR \"coinbase_responses\".\"coinbase_sender_email\" = 'XXX') OR \"coinbase_responses\".\"coinbase_recipient_id\" = 'XXX') OR \"coinbase_responses\".\"coinbase_recipient_email\" = 'XXX') AND \"coinbase_responses\".\"api_call\" = 'charge' AND \"coinbase_responses\".\"success\" = 't' ORDER BY \"coinbase_responses\".\"id\" LIMIT 10 OFFSET 0"
    Killbill::Coinbase::CoinbaseResponse.search_query('charge', 'XXX', 0, 10).to_sql.should == expected_query
  end

  it 'should search all fields' do
    do_search('foo').size.should == 0

    pm = Killbill::Coinbase::CoinbaseResponse.create :api_call => 'charge',
                                                     :kb_payment_id => '11-22-33-44',
                                                     :coinbase_txn_id => 'aa-bb-cc-dd',
                                                     :coinbase_hsh => '55-66-77-88',
                                                     :coinbase_sender_id => 38102343,
                                                     :coinbase_sender_email => 'sender@coinbase.com',
                                                     :coinbase_recipient_id => 9843291,
                                                     :coinbase_recipient_emal => 'receiver@coinbase.com',
                                                     :success => true

    # Wrong api_call
    ignored1 = Killbill::Coinbase::CoinbaseResponse.create :api_call => 'add_payment_method',
                                                           :kb_payment_id => pm.kb_payment_id,
                                                           :coinbase_txn_id => pm.coinbase_txn_id,
                                                           :coinbase_hsh => pm.coinbase_hsh,
                                                           :coinbase_sender_id => pm.coinbase_sender_id,
                                                           :coinbase_sender_email => pm.coinbase_sender_email,
                                                           :coinbase_recipient_id => pm.coinbase_recipient_id,
                                                           :coinbase_recipient_email => pm.coinbase_recipient_email,
                                                           :success => true

    # Not successful
    ignored2 = Killbill::Coinbase::CoinbaseResponse.create :api_call => 'charge',
                                                           :kb_payment_id => pm.kb_payment_id,
                                                           :coinbase_txn_id => pm.coinbase_txn_id,
                                                           :coinbase_hsh => pm.coinbase_hsh,
                                                           :coinbase_sender_id => pm.coinbase_sender_id,
                                                           :coinbase_sender_email => pm.coinbase_sender_email,
                                                           :coinbase_recipient_id => pm.coinbase_recipient_id,
                                                           :coinbase_recipient_email => pm.coinbase_recipient_email,
                                                           :success => false

    do_search('foo').size.should == 0
    do_search(pm.coinbase_txn_id).size.should == 1
    do_search(pm.coinbase_hsh).size.should == 1
    do_search(pm.coinbase_sender_id).size.should == 1

    pm2 = Killbill::Coinbase::CoinbaseResponse.create :api_call => 'charge',
                                                      :kb_payment_id => '11-22-33-44',
                                                      :coinbase_txn_id => 'AA-BB-CC-DD',
                                                      :coinbase_hsh => '11-22-33-44',
                                                      :coinbase_sender_id => pm.coinbase_sender_id,
                                                      :coinbase_sender_email => 'sender2@coinbase.com',
                                                      :coinbase_recipient_id => 984329234341,
                                                      :coinbase_recipient_email => 'receiver2@coinbase.com',
                                                      :success => true

    do_search('foo').size.should == 0
    do_search(pm.coinbase_txn_id).size.should == 1
    do_search(pm.coinbase_hsh).size.should == 1
    do_search(pm.coinbase_sender_id).size.should == 2
    do_search(pm.coinbase_sender_email).size.should == 1
    do_search(pm.coinbase_recipient_id).size.should == 1
    do_search(pm.coinbase_recipient_email).size.should == 1
    do_search(pm2.coinbase_txn_id).size.should == 1
    do_search(pm2.coinbase_hsh).size.should == 1
    do_search(pm2.coinbase_sender_id).size.should == 2
    do_search(pm2.coinbase_sender_email).size.should == 1
    do_search(pm2.coinbase_recipient_id).size.should == 1
    do_search(pm2.coinbase_recipient_email).size.should == 1
  end

  private

  def do_search(search_key)
    pagination = Killbill::Coinbase::CoinbaseResponse.search(search_key)
    pagination.current_offset.should == 0
    results = pagination.iterator.to_a
    pagination.total_nb_records.should == results.size
    results
  end
end
