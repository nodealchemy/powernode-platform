# frozen_string_literal: true

class AddSuspendedToSubscriptionStatuses < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL
      ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS valid_subscription_status;
      ALTER TABLE subscriptions ADD CONSTRAINT valid_subscription_status
        CHECK (status IN ('active', 'trialing', 'past_due', 'canceled', 'unpaid', 'incomplete', 'incomplete_expired', 'paused', 'suspended'));
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS valid_subscription_status;
      ALTER TABLE subscriptions ADD CONSTRAINT valid_subscription_status
        CHECK (status IN ('active', 'trialing', 'past_due', 'canceled', 'unpaid', 'incomplete', 'incomplete_expired', 'paused'));
    SQL
  end
end
