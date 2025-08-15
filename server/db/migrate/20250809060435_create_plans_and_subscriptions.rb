class CreatePlansAndSubscriptions < ActiveRecord::Migration[8.0]
  def change
    # Create plans table
    create_table :plans, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :name, null: false, limit: 100
      t.string :description, limit: 500
      t.bigint :price_cents, null: false, default: 0
      t.string :currency, null: false, default: 'USD', limit: 3
      t.string :billing_cycle, null: false, limit: 20
      t.string :status, null: false, default: 'active', limit: 20
      t.integer :trial_days, null: false, default: 0
      t.boolean :is_public, null: false, default: true
      t.text :features, default: '{}'
      t.text :limits, default: '{}'
      t.text :metadata, default: '{}'
      t.string :stripe_price_id, limit: 100
      t.string :paypal_plan_id, limit: 100
      t.timestamps null: false
      
      t.index [:status]
      t.index [:billing_cycle]
      t.index [:currency]
      t.index [:is_public]
      t.index [:stripe_price_id], unique: true, where: "stripe_price_id IS NOT NULL"
      t.index [:paypal_plan_id], unique: true, where: "paypal_plan_id IS NOT NULL"
    end

    # Create subscriptions table
    create_table :subscriptions, id: false do |t|
      t.string :id, primary_key: true, null: false, limit: 36
      t.string :account_id, null: false, limit: 36
      t.string :plan_id, null: false, limit: 36
      t.integer :quantity, null: false, default: 1
      t.string :status, null: false, default: 'trialing', limit: 30
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :trial_start
      t.datetime :trial_end
      t.datetime :canceled_at
      t.datetime :ended_at
      t.text :metadata, default: '{}'
      t.string :stripe_subscription_id, limit: 100
      t.string :paypal_subscription_id, limit: 100
      t.timestamps null: false
      
      t.foreign_key :accounts, column: :account_id
      t.foreign_key :plans, column: :plan_id
      t.index [:account_id], unique: true
      t.index [:plan_id]
      t.index [:status]
      t.index [:current_period_end]
      t.index [:trial_end]
      t.index [:stripe_subscription_id], unique: true, where: "stripe_subscription_id IS NOT NULL"
      t.index [:paypal_subscription_id], unique: true, where: "paypal_subscription_id IS NOT NULL"
    end
  end
end