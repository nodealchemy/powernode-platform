# frozen_string_literal: true

class CreateAiGovernanceReportsAndCollusionIndicators < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_governance_reports, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :monitor_agent, type: :uuid, foreign_key: { to_table: :ai_agents }
      t.references :subject_agent, type: :uuid, foreign_key: { to_table: :ai_agents }
      t.references :subject_team, type: :uuid, foreign_key: { to_table: :ai_agent_teams }

      t.string :report_type, null: false
      t.string :severity, null: false, default: "info"
      t.string :status, null: false, default: "open"
      t.jsonb :evidence, default: {}
      t.jsonb :recommended_actions, default: []
      t.decimal :confidence_score, precision: 5, scale: 4, default: 0.5
      t.boolean :auto_remediated, default: false, null: false

      t.timestamps
    end

    add_index :ai_governance_reports, [:account_id, :status], name: "idx_governance_reports_status"
    add_index :ai_governance_reports, [:subject_agent_id, :status], name: "idx_governance_reports_agent"
    add_index :ai_governance_reports, :report_type

    create_table :ai_collusion_indicators, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true

      t.string :indicator_type, null: false
      t.jsonb :agent_cluster, default: []
      t.decimal :correlation_score, precision: 5, scale: 4, default: 0.0
      t.jsonb :evidence_summary, default: {}

      t.timestamps
    end

    add_index :ai_collusion_indicators, [:account_id, :indicator_type], name: "idx_collusion_indicators_type"
  end
end
