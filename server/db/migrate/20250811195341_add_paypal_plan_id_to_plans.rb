# frozen_string_literal: true

class AddPaypalPlanIdToPlans < ActiveRecord::Migration[8.0]
  def change
    # Check if column already exists before adding
    unless column_exists?(:plans, :paypal_plan_id)
      add_column :plans, :paypal_plan_id, :string
    end

    # Add index for PayPal plan ID if not exists
    unless index_exists?(:plans, :paypal_plan_id)
      add_index :plans, :paypal_plan_id
    end
  end
end
