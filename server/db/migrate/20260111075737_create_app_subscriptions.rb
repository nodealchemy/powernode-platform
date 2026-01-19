# frozen_string_literal: true

class CreateAppSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :app_subscriptions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Account association
      t.uuid :account_id, null: false
      t.uuid :subscribed_by_user_id

      # Polymorphic subscribable (templates, apps, etc.)
      t.string :subscribable_type
      t.uuid :subscribable_id

      # Legacy app association (backward compatibility)
      t.uuid :app_id
      t.uuid :app_plan_id

      # Subscription status and tier
      t.string :status, null: false, default: "active"
      t.string :tier

      # Dates
      t.datetime :subscribed_at, null: false
      t.datetime :next_billing_at
      t.datetime :cancelled_at

      # JSON data
      t.jsonb :configuration, default: {}
      t.jsonb :usage_metrics, default: {}
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :app_subscriptions, :account_id
    add_index :app_subscriptions, :app_id
    add_index :app_subscriptions, :app_plan_id
    add_index :app_subscriptions, [:subscribable_type, :subscribable_id], name: "idx_app_subscriptions_on_subscribable"
    add_index :app_subscriptions, :status
    add_index :app_subscriptions, :subscribed_at

    add_foreign_key :app_subscriptions, :accounts, column: :account_id
  end
end
