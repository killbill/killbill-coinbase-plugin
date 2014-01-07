configure do
  # Usage: rackup -Ilib -E test
  if development? or test?
    Killbill::Coinbase.initialize! unless Killbill::Coinbase.initialized
  end
end

after do
  # return DB connections to the Pool if required
  ActiveRecord::Base.connection.close
end

# curl -v http://127.0.0.1:9292/plugins/killbill-coinbase/1.0/pms/1
get '/plugins/killbill-coinbase/1.0/pms/:id', :provides => 'json' do
  if pm = Killbill::Coinbase::CoinbasePaymentMethod.find_by_id(params[:id].to_i)
    pm.to_json
  else
    status 404
  end
end

# curl -v http://127.0.0.1:9292/plugins/killbill-coinbase/1.0/transactions/1
get '/plugins/killbill-coinbase/1.0/transactions/:id', :provides => 'json' do
  if transaction = Killbill::Coinbase::CoinbaseTransaction.find_by_id(params[:id].to_i)
    transaction.to_json
  else
    status 404
  end
end

