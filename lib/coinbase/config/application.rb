configure do
  # Usage: rackup -Ilib -E test
  if development? or test?
    @@plugin ||= begin
      plugin = Killbill::Coinbase::PaymentPlugin.new
      plugin.logger = Logger.new(STDOUT)
      plugin.logger.level = Logger::INFO
      plugin.conf_dir = Killbill::Coinbase.conf_dir || File.expand_path('../../../..', __FILE__)
      plugin.kb_apis = Killbill::Plugin::KillbillApi.new('coinbase', {})
      plugin.start_plugin
      plugin
    end
  end
end

helpers do
  def client
    OAuth2::Client.new(Killbill::Coinbase.client_id,
                       Killbill::Coinbase.client_secret,
                       site: 'https://coinbase.com')
  end
end

after do
  # return DB connections to the Pool if required
  ActiveRecord::Base.connection.close
end

enable :sessions

# curl -v http://127.0.0.1:9292/plugins/killbill-coinbase/1.0/authorize?kb_account_id=d4598da0-302a-11e3-baa7-0800211c9a66
get '/plugins/killbill-coinbase/1.0/authorize' do
  halt 400, "kb_account_id must be specified" if params[:kb_account_id].blank?

  session[:kb_account_id] = params[:kb_account_id]
  # Redirect the user to the authorize_uri endpoint
  url = client.auth_code.authorize_url(redirect_uri: Killbill::Coinbase.redirect_uri,
                                       scope: 'send')
  redirect url
end

# curl -v http://127.0.0.1:9292/plugins/killbill-coinbase/1.0/pms?code=ABCD
get '/plugins/killbill-coinbase/1.0/pms', :provides => 'json' do
  halt 400, "session has expired" if session[:kb_account_id].blank?

  begin
    # Make a request to the access_token_uri endpoint to get an access_token
    resp = client.auth_code.get_token(params[:code], redirect_uri: Killbill::Coinbase.redirect_uri)
  rescue OAuth2::Error => e
    if !e.description.blank? and !e.code.blank?
      msg = "OAuth error (#{e.code}): #{e.description}"
    elsif !e.description.blank?
      msg = "OAuth error: #{e.description}"
    elsif !e.response.blank? and !e.response.body.blank?
      msg = e.response.body
    else
      msg = "OAuth error"
    end
    halt 400, msg
  end

  pm = Killbill::Coinbase::CoinbasePaymentMethod.new
  pm.kb_account_id = session[:kb_account_id]
  pm.coinbase_access_token = resp.token
  pm.coinbase_refresh_token = resp.refresh_token

  if development? or test?
    pm.kb_payment_method_id = SecureRandom.uuid
    pm.save!
    pm_id = pm.kb_payment_method_id
  else
    payment_method_plugin = pm.to_payment_method_response

    # Create the payment method in Kill Bill
    context = Killbill::Coinbase.kb_apis.create_context
    account = Killbill::Coinbase.kb_apis.account_user_api.get_account_by_id(session[:kb_account_id], context)
    pm_id = Killbill::Coinbase.kb_apis.payment_api.add_payment_method('killbill-coinbase', account, params[:default] || true, payment_method_plugin, context)
  end

  if !Killbill::Coinbase.app_redirect_uri.blank?
    redirect Killbill::Coinbase.app_redirect_uri
  else
    pm = Killbill::Coinbase::CoinbasePaymentMethod.find_by_kb_payment_method_id(pm_id)
    pm.to_json
  end
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

#
# Test endpoints
#

# curl -v -XPOST http://127.0.0.1:9292/plugins/killbill-coinbase/test/paymentMethods --data-binary '{"apiKey":"a6b33ba1"}'
post '/plugins/killbill-coinbase/test/paymentMethods', :provides => 'json' do
  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError => e
    halt 400, {'Content-Type' => 'text/plain'}, "Invalid payload: #{e}"
  end

  properties = []
  prop = Killbill::Plugin::Model::PaymentMethodKVInfo.new
  prop.key = Killbill::Coinbase::CoinbasePaymentMethod::COINBASE_API_KEY_KEY
  prop.value = data['apiKey']
  properties << prop

  info = Killbill::Plugin::Model::PaymentMethodPlugin.new
  info.properties = properties

  response = @@plugin.add_payment_method SecureRandom.uuid,
                                         SecureRandom.uuid,
                                         info,
                                         true
  response.to_json
end

# curl -v -XPOST http://127.0.0.1:9292/plugins/killbill-coinbase/test/charge --data-binary '{"kb_payment_method_id":"a6b33ba1"}'
post '/plugins/killbill-coinbase/test/charge', :provides => 'json' do
  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError => e
    halt 400, {'Content-Type' => 'text/plain'}, "Invalid payload: #{e}"
  end

  response = @@plugin.process_payment SecureRandom.uuid,
                                      SecureRandom.uuid,
                                      data['kb_payment_method_id'],
                                      data['amount_in_cents'] || 0.0020,
                                      data['currency'] || 'BTC'
  response.to_json
end

# curl -v http://127.0.0.1:9292/plugins/killbill-coinbase/test/payments/a6b33ba1
get '/plugins/killbill-coinbase/test/payments/:id', :provides => 'json' do
  response = @@plugin.get_payment_info SecureRandom.uuid,
                                       params[:id]
  response.to_json
end

# curl -v -XPOST http://127.0.0.1:9292/plugins/killbill-coinbase/test/refund --data-binary '{"kb_payment_id":"a6b33ba1"}'
post '/plugins/killbill-coinbase/test/refund', :provides => 'json' do
  begin
    data = JSON.parse request.body.read
  rescue JSON::ParserError => e
    halt 400, {'Content-Type' => 'text/plain'}, "Invalid payload: #{e}"
  end

  response = @@plugin.process_refund SecureRandom.uuid,
                                     data['kb_payment_id'],
                                     data['amount_in_cents'] || 0.0020,
                                     data['currency'] || 'BTC'
  response.to_json
end

# curl -v http://127.0.0.1:9292/plugins/killbill-coinbase/test/refunds/a6b33ba1
get '/plugins/killbill-coinbase/test/refunds/:id', :provides => 'json' do
  response = @@plugin.get_refund_info SecureRandom.uuid,
                                      params[:id]
  response.to_json
end

