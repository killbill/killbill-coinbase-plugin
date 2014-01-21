CREATE TABLE `coinbase_payment_methods` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `kb_account_id` varchar(255) NOT NULL,
  `kb_payment_method_id` varchar(255) DEFAULT NULL,
  `encrypted_coinbase_api_key` varchar(255) DEFAULT NULL,
  `encrypted_coinbase_access_token` varchar(255) DEFAULT NULL,
  `encrypted_coinbase_refresh_token` varchar(255) DEFAULT NULL,
  `is_deleted` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_coinbase_payment_methods_on_kb_account_id` (`kb_account_id`),
  KEY `index_coinbase_payment_methods_on_kb_payment_method_id` (`kb_payment_method_id`)
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_bin;

CREATE TABLE `coinbase_transactions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `coinbase_response_id` int(11) NOT NULL,
  `api_call` varchar(255) NOT NULL,
  `kb_payment_id` varchar(255) NOT NULL,
  `kb_payment_method_id` varchar(255) NOT NULL,
  `coinbase_txn_id` varchar(255) NOT NULL,
  `amount_in_cents` int(11) NOT NULL,
  `currency` varchar(255) NOT NULL,
  `processed_amount_in_cents` int(11) NOT NULL,
  `processed_currency` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_coinbase_transactions_on_kb_payment_id` (`kb_payment_id`)
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_bin;

CREATE TABLE `coinbase_responses` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `api_call` varchar(255) NOT NULL,
  `kb_payment_id` varchar(255) DEFAULT NULL,
  `coinbase_txn_id` varchar(255) DEFAULT NULL,
  `coinbase_hsh` varchar(255) DEFAULT NULL,
  `coinbase_created_at` varchar(255) DEFAULT NULL,
  `coinbase_request` varchar(255) DEFAULT NULL,
  `coinbase_amount_in_cents` int(11) DEFAULT NULL,
  `coinbase_currency` varchar(255) DEFAULT NULL,
  `coinbase_notes` varchar(255) DEFAULT NULL,
  `coinbase_status` varchar(255) DEFAULT NULL,
  `coinbase_sender_id` varchar(255) DEFAULT NULL,
  `coinbase_sender_name` varchar(255) DEFAULT NULL,
  `coinbase_sender_email` varchar(255) DEFAULT NULL,
  `coinbase_recipient_id` varchar(255) DEFAULT NULL,
  `coinbase_recipient_name` varchar(255) DEFAULT NULL,
  `coinbase_recipient_email` varchar(255) DEFAULT NULL,
  `coinbase_recipient_address` varchar(255) DEFAULT NULL,
  `success` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB CHARACTER SET utf8 COLLATE utf8_bin;
