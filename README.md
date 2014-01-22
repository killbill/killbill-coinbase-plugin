[![Build Status](https://travis-ci.org/killbill/killbill-coinbase-plugin.png)](https://travis-ci.org/killbill/killbill-coinbase-plugin)
[![Code Climate](https://codeclimate.com/github/killbill/killbill-coinbase-plugin.png)](https://codeclimate.com/github/killbill/killbill-coinbase-plugin)

killbill-coinbase-plugin
========================

Plugin to use Coinbase as a gateway.

Requirements
------------

The plugin needs a database. The latest version of the schema can be found here: https://raw.github.com/killbill/killbill-coinbase-plugin/master/db/ddl.sql.

Usage
-----

In this version, users need to provide their Coinbase API key. This is unfortunate but required in order to Kill Bill to transfer Bitcoins on the user's behalf. Maybe one day Coinbase will provide some sort of revokable token, potentially with a monthly max transfer amount, for such scenarii?

To enable API access, go to https://coinbase.com/account/integrations, click "Show My API Key", enter your password and click enable.

Then, save the key in Kill Bill as a new payment method:

```
curl -v \
     -X POST \
     -H "Content-Type: application/json" \
     -H "X-Killbill-CreatedBy: Web server" \
     -H "X-Killbill-Reason: New account" \
     --data-binary '{
       "pluginName": "killbill-coinbase",
       "pluginInfo": {
         "properties": [
           {
             "key": "apiKey",
             "value": "t3GER3BP3JHLASZe"
           }
         ]
       }
     }' \
     "http://$HOST:8080/1.0/kb/accounts/13d26090-b8d7-11e2-9e96-0800200c9a66/paymentMethods?isDefault=true"
```

Configuration
-------------

The plugin expects a `coinbase.yml` configuration file containing the following:

```
:coinbase:
  :log_file: '/var/tmp/coinbase.log'
  :refresh_interval: 120
  # Trust Coinbase for the payment/refund status or delegate to the Bitcoin plugin?
  :refresh_update_killbill: false
  # Switch to false for production
  :test: true
  # REQUIRED: your payout address
  :btc_address: 'your-merchant-BTC-address'
  # REQUIRED: your Coinbase apiKey (needed for refunds)
  :api_key: 'your-coinbase-API-key'
  # OPTIONAL: you application OAuth details (to use the OAuth-based login mechanism)
  :client_id: 'your-application-client-id'
  :client_secret: 'your-application-client-secret'
  # Change it to your Kill Bill address (make sure to update Coinbase as well)
  :redirect_uri: 'http://127.0.0.1:8080/plugins/killbill-coinbase/1.0/pms'

:database:
  :adapter: 'sqlite3'
  :database: 'test.db'
# For MySQL
#  :adapter: 'jdbc'
#  :username: 'your-username'
#  :password: 'your-password'
#  :driver: 'com.mysql.jdbc.Driver'
#  :url: 'jdbc:mysql://127.0.0.1:3306/your-database'
```

The plugin encrypts API keys and OAuth tokens in the database. To do so, we use https://github.com/reidmorrison/symmetric-encryption, which requires a configuration file `symmetric-encryption.yml`.

To generate this file:

```
cd /var/tmp/
curl -O https://raw2.github.com/reidmorrison/symmetric-encryption/master/examples/symmetric-encryption.yml
# Replace /etc/rails with the directory where you want the keys to be stored
vi /var/tmp/symmetric-encryption.yml
irb
> require 'symmetric-encryption'
> SymmetricEncryption.generate_symmetric_key_files('/var/tmp/symmetric-encryption.yml', 'production')
```


Note that the symmetric-encryption project can also help you encrypting your API and/or OAuth keys in the `coinbase.yml` file. First, encrypt them using the keys you generated:

```
require 'symmetric-encryption'
SymmetricEncryption.load!('/var/tmp/symmetric-encryption.yml', 'production')
SymmetricEncryption.encrypt('your-coinbase-API-key')
```

You can now update your `coinbase.yml` file with the encrypted API key:

```
:coinbase:
  :api_key: <%= SymmetricEncryption.try_decrypt "JqLJOi6dNjWI9kX9lSL1XQ==\n" %>
```

If you are using JRuby and encounter the following error:
```
OpenSSL::Cipher::CipherError: Illegal key size: possibly you need to install Java Cryptography Extension (JCE) Unlimited Strength Jurisdiction Policy Files for your JRE
```

Copy and Paste these lines in your IRB session before trying to encrypt:

```
# See https://github.com/jruby/jruby/wiki/UnlimitedStrengthCrypto
security_class = java.lang.Class.for_name('javax.crypto.JceSecurity')
restricted_field = security_class.get_declared_field('isRestricted')
restricted_field.accessible = true
restricted_field.set nil, false
```

See also http://www.slideshare.net/reidmorrison/ruby-on-rails-symmetricencryption for more details.


By default, the plugin will look at the plugin directory root (where `killbill.properties` is located) to find these files.
Alternatively, set the Kill Bill system property `-Dcom.ning.billing.osgi.bundles.jruby.conf.dir=/my/directory` to specify another location.
