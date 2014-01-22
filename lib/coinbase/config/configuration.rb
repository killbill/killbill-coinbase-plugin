module Killbill::Coinbase
  mattr_reader :logger
  mattr_reader :config
  mattr_reader :kb_apis
  mattr_reader :initialized
  mattr_reader :test
  mattr_reader :merchant_api_key
  mattr_reader :client_id
  mattr_reader :client_secret
  mattr_reader :redirect_uri
  mattr_reader :merchant_btc_address
  mattr_reader :transactions_refresh_interval
  mattr_reader :base_uri

  def self.initialize!(logger=Logger.new(STDOUT), conf_dir=File.expand_path('../../../', File.dirname(__FILE__)), kb_apis = nil)
    @@logger = logger
    @@kb_apis = kb_apis

    config_file = "#{conf_dir}/coinbase.yml"
    @@config = Properties.new(config_file)
    @@config.parse!
    @@test = @@config[:coinbase][:test]
    # To access our merchant account (refunds)
    @@merchant_api_key = @@config[:coinbase][:api_key]
    # For OAuth
    @@client_id = @@config[:coinbase][:client_id]
    @@client_secret = @@config[:coinbase][:client_secret]
    # This must match the url you set during registration
    @@redirect_uri = @@config[:coinbase][:redirect_uri]

    @@merchant_btc_address = @@config[:coinbase][:btc_address]
    @@transactions_refresh_interval = @@config[:coinbase][:refresh_interval] || 120
    @@base_uri = @@config[:coinbase][:base_uri] || 'https://coinbase.com/api/v1'

    @@logger.log_level = Logger::DEBUG if (@@config[:logger] || {})[:debug]

    if defined?(JRUBY_VERSION)
      # See https://github.com/jruby/activerecord-jdbc-adapter/issues/302
      require 'jdbc/mysql'
      Jdbc::MySQL.load_driver(:require) if Jdbc::MySQL.respond_to?(:load_driver)
    end

    ActiveRecord::Base.establish_connection(@@config[:database])
    ActiveRecord::Base.logger = @@logger

    # Make sure OpenSSL is correctly loaded
    javax.crypto.spec.IvParameterSpec.new(java.lang.String.new("dummy test").getBytes())

    # See https://github.com/reidmorrison/symmetric-encryption
    SymmetricEncryption.load!("#{conf_dir}/symmetric-encryption.yml", @@test ? 'test' : 'production')

    @@initialized = true
  end
end
