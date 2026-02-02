# frozen_string_literal: true

class AddPolymorphicToAppSubscriptions < ActiveRecord::Migration[8.0]
  def change
    # Add polymorphic columns for unified marketplace subscriptions
    add_column :app_subscriptions, :subscribable_type, :string
    add_column :app_subscriptions, :subscribable_id, :uuid

    # Make app_id and app_plan_id nullable for non-app subscriptions
    change_column_null :app_subscriptions, :app_id, true
    change_column_null :app_subscriptions, :app_plan_id, true

    # Add subscription tier for non-app items (plugins, templates, integrations)
    add_column :app_subscriptions, :tier, :string, default: "standard"

    # Add metadata for type-specific configuration
    add_column :app_subscriptions, :metadata, :jsonb, default: {}

    # Add indexes for polymorphic lookup
    add_index :app_subscriptions, [ :subscribable_type, :subscribable_id ],
              name: "idx_app_subscriptions_on_subscribable"
    add_index :app_subscriptions, [ :account_id, :subscribable_type, :subscribable_id ],
              unique: true, name: "idx_app_subscriptions_unique_per_account_subscribable"

    # Backfill existing app subscriptions with polymorphic association
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE app_subscriptions
          SET subscribable_type = 'Marketplace::Definition',
              subscribable_id = app_id
          WHERE app_id IS NOT NULL
        SQL
      end
    end
  end
end
