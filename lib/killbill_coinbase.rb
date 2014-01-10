require 'active_support/core_ext'
require 'active_record'
require 'bigdecimal'
require 'money'
require 'pathname'
require 'sinatra'
require 'singleton'
require 'thread/every'
require 'yaml'

require 'killbill'

require 'coinbase/config/configuration'
require 'coinbase/config/properties'

require 'coinbase/api'

require 'coinbase/models/coinbase_payment_method'
require 'coinbase/models/coinbase_response'
require 'coinbase/models/coinbase_transaction'

require 'coinbase/coinbase_utils'

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end
