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
  :btc_address: 'your-merchant-BTC-address'
  :api_key: 'your-coinbase-API-key'
  :log_file: '/var/tmp/coinbase.log'
  # Switch to false for production
  :test: true

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

By default, the plugin will look at the plugin directory root (where `killbill.properties` is located) to find this file.
Alternatively, set the Kill Bill system property `-Dcom.ning.billing.osgi.bundles.jruby.conf.dir=/my/directory` to specify another location.
