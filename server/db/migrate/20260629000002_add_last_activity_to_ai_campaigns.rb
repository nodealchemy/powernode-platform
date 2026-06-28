# frozen_string_literal: true

# A heartbeat for the execution interface: when the campaign last did real work
# (a decision, a parked question, an increment, a lifecycle transition) — distinct
# from updated_at, which also moves on plain status reads / snapshots.
class AddLastActivityToAiCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_campaigns, :last_activity_at, :datetime
    add_index :ai_campaigns, :last_activity_at
  end
end
