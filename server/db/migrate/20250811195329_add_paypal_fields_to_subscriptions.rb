class AddPaypalFieldsToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :paypal_agreement_id, :string
    add_column :subscriptions, :paypal_plan_id, :string

    # Add indexes for PayPal fields
    add_index :subscriptions, :paypal_agreement_id
    add_index :subscriptions, :paypal_plan_id
  end
end
