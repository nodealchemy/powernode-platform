# frozen_string_literal: true

class CreateAiBehavioralFingerprints < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_behavioral_fingerprints, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :agent, null: false, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.string :metric_name, null: false
      t.float :baseline_mean, null: false, default: 0.0
      t.float :baseline_stddev, null: false, default: 1.0
      t.integer :rolling_window_days, null: false, default: 7
      t.float :deviation_threshold, null: false, default: 2.0
      t.integer :observation_count, null: false, default: 0
      t.datetime :last_observation_at
      t.integer :anomaly_count, null: false, default: 0
      t.jsonb :recent_observations, null: false, default: []

      t.timestamps
    end

    add_index :ai_behavioral_fingerprints, [:agent_id, :metric_name], unique: true,
              name: "idx_ai_behavioral_fingerprints_agent_metric"
    add_index :ai_behavioral_fingerprints, [:account_id, :agent_id],
              name: "idx_ai_behavioral_fingerprints_account_agent"
  end
end
