require 'logger'
# Coinbase gem
require 'coinbase'

module Killbill::Coinbase
  mattr_reader :logger
  mattr_reader :config
  mattr_reader :currency_conversions
  mattr_reader :kb_apis
  mattr_reader :initialized
  mattr_reader :test

  def self.initialize!(logger=Logger.new(STDOUT), conf_dir=File.expand_path('../../../', File.dirname(__FILE__)), kb_apis = nil)
    @@logger = logger
    @@kb_apis = kb_apis

    config_file = "#{conf_dir}/coinbase.yml"
    @@config = Properties.new(config_file)
    @@config.parse!
    @@test = @@config[:coinbase][:test]
    @@base_uri = @@config[:coinbase][:base_uri] || 'https://coinbase.com/api/v1'

    @@logger.log_level = Logger::DEBUG if (@@config[:logger] || {})[:debug]

    if defined?(JRUBY_VERSION)
      # See https://github.com/jruby/activerecord-jdbc-adapter/issues/302
      require 'jdbc/mysql'
      Jdbc::MySQL.load_driver(:require) if Jdbc::MySQL.respond_to?(:load_driver)
    end

    ActiveRecord::Base.establish_connection(@@config[:database])
    ActiveRecord::Base.logger = @@logger

    @@initialized = true
  end

  def self.transactions_refresh_interval
    Killbill::Coinbase.config[:coinbase][:refresh_interval] || 120
  end

  def self.merchant_api_key
    Killbill::Coinbase.config[:coinbase][:api_key]
  end

  def self.merchant_btc_address
    Killbill::Coinbase.config[:coinbase][:btc_address]
  end

  def self.gateway_for_api_key(api_key)
    ::Coinbase::Client.new(api_key, { :base_uri => @@base_uri })
  end
end
