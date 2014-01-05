module Killbill::Coinbase
  class Properties
    def initialize(file = 'coinbase.yml')
      @config_file = Pathname.new(file).expand_path
    end

    def parse!
      raise "#{@config_file} is not a valid file" unless @config_file.file?
      @config = YAML.load_file(@config_file.to_s)
      validate!
    end

    def [](key)
      @config[key]
    end

    private

    def validate!
      raise "Bad configuration for Coinbase plugin. Config is #{@config.inspect}" if @config.blank? || !@config[:coinbase] || !@config[:coinbase][:btc_address] || !@config[:coinbase][:api_key]
    end
  end
end
