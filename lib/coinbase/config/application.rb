configure do
  # Usage: rackup -Ilib -E test
  if development? or test?
    Killbill::Coinbase.initialize! unless Killbill::Coinbase.initialized
  end
end

helpers do
  def required_parameter!(parameter_name, parameter_value, message='must be specified!')
    halt 400, "#{parameter_name} #{message}" if parameter_value.blank?
  end
end

after do
  # return DB connections to the Pool if required
  ActiveRecord::Base.connection.close
end

# http://127.0.0.1:9292/plugins/killbill-coinbase?kb_account_id=a6b33ba1
get '/plugins/killbill-coinbase' do
  kb_account_id = request.GET['kb_account_id']
  required_parameter! :kb_account_id, kb_account_id

  locals = {
      :kb_account_id => kb_account_id,
      :success_page => params[:success_page],
      :failure_page => params[:failure_page]
  }
  erb :paypage, :views => File.expand_path(File.dirname(__FILE__) + '/../views'), :locals => locals
end

# Either form data or plain json:
# curl -v -XPOST http://127.0.0.1:9292/plugins/killbill-coinbase/1.0/setup --data-binary '{"kb_account_id":"a6b33ba1", "api_key": "jdk82"}'
post '/plugins/killbill-coinbase/1.0/setup', :provides => 'json' do
  # Assume form data by default
  kb_account_id = params['kb_account_id']
  api_key = params['api_key']
  success_page = params['success_page']

  unless kb_account_id && api_key
    begin
      data = JSON.parse request.body.read
      kb_account_id = data['kb_account_id']
      api_key = data['api_key']
      success_page = data['success_page']
    rescue JSON::ParserError => e
      halt 400, {'Content-Type' => 'text/plain'}, "Invalid payload: #{e}"
    end
  end

  pm = Killbill::Coinbase::CoinbasePaymentMethod.create :kb_account_id => kb_account_id,
                                                        :kb_payment_method_id => nil,
                                                        :coinbase_api_key => api_key

  if success_page
    redirect success_page
  else
    pm.to_json
  end
end

