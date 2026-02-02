# frozen_string_literal: true

class AddPaypalFieldsToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :paypal_payment_id, :string
    add_column :payments, :paypal_transaction_id, :string
    add_column :payments, :paypal_payer_id, :string

    # Add indexes for PayPal fields
    add_index :payments, :paypal_payment_id
    add_index :payments, :paypal_transaction_id
  end
end
