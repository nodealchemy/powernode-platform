class CreateBillingAndPayments < ActiveRecord::Migration[8.0]
  def change
    # Create invoices table
    create_table :invoices, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :subscription_id, null: false, limit: 36
      t.string :invoice_number, null: false, limit: 50
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :currency, null: false, default: 'USD', limit: 3
      t.string :status, null: false, default: 'draft', limit: 30
      t.decimal :tax_rate, precision: 5, scale: 4, null: false, default: 0.0
      t.datetime :due_date
      t.datetime :paid_at
      t.text :notes
      t.text :metadata, default: '{}'
      t.string :stripe_invoice_id, limit: 100
      t.string :paypal_invoice_id, limit: 100
      t.timestamps null: false
      
      t.foreign_key :subscriptions, column: :subscription_id
      t.index [:subscription_id]
      t.index [:invoice_number], unique: true
      t.index [:status]
      t.index [:due_date]
      t.index [:paid_at]
      t.index [:stripe_invoice_id], unique: true, where: "stripe_invoice_id IS NOT NULL"
      t.index [:paypal_invoice_id], unique: true, where: "paypal_invoice_id IS NOT NULL"
    end

    # Create invoice_line_items table
    create_table :invoice_line_items, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :invoice_id, null: false, limit: 36
      t.string :description, null: false, limit: 500
      t.integer :quantity, null: false, default: 1
      t.bigint :unit_price_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :line_type, null: false, default: 'subscription', limit: 30
      t.date :period_start
      t.date :period_end
      t.text :metadata, default: '{}'
      t.timestamps null: false
      
      t.foreign_key :invoices, column: :invoice_id
      t.index [:invoice_id]
      t.index [:line_type]
      t.index [:period_start]
      t.index [:period_end]
    end

    # Create payments table
    create_table :payments, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :invoice_id, null: false, limit: 36
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: 'USD', limit: 3
      t.string :payment_method, null: false, limit: 50
      t.string :status, null: false, default: 'pending', limit: 30
      t.bigint :gateway_fee_cents, default: 0
      t.bigint :net_amount_cents
      t.datetime :processed_at
      t.datetime :failed_at
      t.text :failure_reason
      t.text :gateway_response
      t.text :metadata, default: '{}'
      t.timestamps null: false
      
      t.foreign_key :invoices, column: :invoice_id
      t.index [:invoice_id]
      t.index [:status]
      t.index [:payment_method]
      t.index [:processed_at]
      t.index [:failed_at]
    end

    # Create payment_methods table
    create_table :payment_methods, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :account_id, null: false, limit: 36
      t.string :user_id, null: false, limit: 36
      t.string :provider, null: false, limit: 20
      t.string :external_id, null: false, limit: 100
      t.string :payment_type, null: false, limit: 30
      t.string :last_four, limit: 4
      t.string :brand, limit: 50
      t.integer :exp_month
      t.integer :exp_year
      t.string :holder_name, limit: 100
      t.boolean :is_default, null: false, default: false
      t.text :metadata, default: '{}'
      t.timestamps null: false
      
      t.foreign_key :accounts, column: :account_id
      t.foreign_key :users, column: :user_id
      t.index [:account_id]
      t.index [:user_id]
      t.index [:provider]
      t.index [:payment_type]
      t.index [:external_id]
      t.index [:is_default]
    end
  end
end