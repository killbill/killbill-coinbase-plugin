module Killbill::Coinbase
  class CoinbaseTransaction < ActiveRecord::Base
    belongs_to :coinbase_response
    attr_accessible :amount_in_cents,
                    :currency,
                    :processed_amount_in_cents,
                    :processed_currency,
                    :api_call,
                    :kb_payment_id,
                    :kb_payment_method_id,
                    :coinbase_txn_id

    def self.from_kb_payment_id(kb_payment_id)
      transaction_from_kb_payment_id :charge, kb_payment_id, :single
    end

    def self.refunds_from_kb_payment_id(kb_payment_id)
      transaction_from_kb_payment_id :refund, kb_payment_id, :multiple
    end

    def self.find_candidate_transaction_for_refund(kb_payment_id, amount_in_cents)
      # Find one successful charge which amount is at least the amount we are trying to refund
      coinbase_transactions = CoinbaseTransaction.where("coinbase_transactions.amount_in_cents >= ?", amount_in_cents)
                                                 .find_all_by_api_call_and_kb_payment_id(:charge, kb_payment_id)
      raise "Unable to find Coinbase transaction id for payment #{kb_payment_id}" if coinbase_transactions.size == 0

      # We have candidates, but we now need to make sure we didn't refund more than for the specified amount
      amount_refunded_in_cents = Killbill::Coinbase::CoinbaseTransaction.where("api_call = ? and kb_payment_id = ?", :refund, kb_payment_id)
                                                                        .sum("amount_in_cents")

      amount_left_to_refund_in_cents = -amount_refunded_in_cents
      coinbase_transactions.map { |transaction| amount_left_to_refund_in_cents += transaction.amount_in_cents }
      raise "Amount #{amount_in_cents} too large to refund for payment #{kb_payment_id}" if amount_left_to_refund_in_cents < amount_in_cents

      coinbase_transactions.first
    end

    def coinbase_payment_method
      CoinbasePaymentMethod.where(kb_payment_method_id: kb_payment_method_id).first!
    end

    private

    def self.transaction_from_kb_payment_id(api_call, kb_payment_id, how_many)
      coinbase_transactions = find_all_by_api_call_and_kb_payment_id(api_call, kb_payment_id)
      raise "Unable to find Coinbase transaction id for payment #{kb_payment_id}" if coinbase_transactions.empty?
      if how_many == :single
        raise "Killbill payment mapping to multiple Coinbase transactions for payment #{kb_payment_id}" if coinbase_transactions.size > 1
        coinbase_transactions[0]
      else
        coinbase_transactions
      end
    end
  end
end
