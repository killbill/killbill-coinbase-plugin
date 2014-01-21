require 'spec_helper'

describe Killbill::Coinbase::PaymentPlugin do
  before(:each) do
    Dir.mktmpdir do |dir|
      keys = File.new(File.join(dir, 'symmetric-encryption.yml'), "w+")
      keys.write(<<-eos)
test:
  key:    1234567890ABCDEF1234567890ABCDEF
  iv:     1234567890ABCDEF
  cipher: aes-128-cbc
      eos
      keys.close

      file = File.new(File.join(dir, 'coinbase.yml'), "w+")
      file.write(<<-eos)
:coinbase:
  :test: true
  :btc_address: '1234'
  :api_key: '5678'
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

      # Start the plugin here - since the config file will be deleted
      @plugin.start_plugin
    end
  end

  it 'should start and stop correctly' do
    @plugin.stop_plugin
  end
end
