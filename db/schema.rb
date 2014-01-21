require 'active_record'

ActiveRecord::Schema.define(:version => 20130311153635) do
  create_table "coinbase_payment_methods", :force => true do |t|
    t.string   "kb_account_id",          :null => false
    t.string   "kb_payment_method_id"    # NULL before Killbill knows about it
    t.string   "encrypted_coinbase_api_key"
    t.string   "encrypted_coinbase_access_token"
    t.string   "encrypted_coinbase_refresh_token"
    t.boolean  "is_deleted",             :null => false, :default => false
    t.datetime "created_at",             :null => false
    t.datetime "updated_at",             :null => false
  end

  add_index(:coinbase_payment_methods, :kb_account_id)
  add_index(:coinbase_payment_methods, :kb_payment_method_id)

  create_table "coinbase_transactions", :force => true do |t|
    t.integer  "coinbase_response_id",      :null => false
    t.string   "api_call",                  :null => false
    t.string   "kb_payment_id",             :null => false
    t.string   "kb_payment_method_id",      :null => false
    t.string   "coinbase_txn_id",           :null => false
    t.integer  "amount_in_cents",           :null => false
    t.string   "currency",                  :null => false
    t.integer  "processed_amount_in_cents", :null => false
    t.string   "processed_currency",        :null => false
    t.datetime "created_at",                :null => false
    t.datetime "updated_at",                :null => false
  end

  add_index(:coinbase_transactions, :kb_payment_id)

  create_table "coinbase_responses", :force => true do |t|
    t.string   "api_call",        :null => false
    t.string   "kb_payment_id"
    t.string   "coinbase_txn_id"
    t.string   "coinbase_hsh"
    t.string   "coinbase_created_at"
    t.string   "coinbase_request"
    t.integer  "coinbase_amount_in_cents"
    t.string   "coinbase_currency"
    t.string   "coinbase_notes"
    t.string   "coinbase_status"
    t.string   "coinbase_sender_id"
    t.string   "coinbase_sender_name"
    t.string   "coinbase_sender_email"
    t.string   "coinbase_recipient_id"
    t.string   "coinbase_recipient_name"
    t.string   "coinbase_recipient_email"
    t.string   "coinbase_recipient_address"
    t.boolean  "success"
    t.datetime "created_at",        :null => false
    t.datetime "updated_at",        :null => false
  end
end
