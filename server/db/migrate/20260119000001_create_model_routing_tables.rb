# frozen_string_literal: true

class CreateModelRoutingTables < ActiveRecord::Migration[8.0]
  def change
    # Model Routing Rules - defines how to route AI requests to providers
    create_table :ai_model_routing_rules, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.text :description
      t.string :rule_type, null: false, default: "capability_based"
      t.integer :priority, null: false, default: 100
      t.boolean :is_active, null: false, default: true

      # Matching conditions (JSON)
      t.jsonb :conditions, null: false, default: {}
      # Example: { "capabilities": ["chat"], "min_quality_score": 0.8, "max_cost_per_token": 0.0001 }

      # Routing target (JSON)
      t.jsonb :target, null: false, default: {}
      # Example: { "provider_ids": ["uuid1", "uuid2"], "model_names": ["gpt-4"], "strategy": "cost_optimized" }

      # Performance thresholds
      t.decimal :max_latency_ms, precision: 10, scale: 2
      t.decimal :min_quality_score, precision: 5, scale: 4
      t.decimal :max_cost_per_1k_tokens, precision: 10, scale: 6

      # Statistics
      t.integer :times_matched, null: false, default: 0
      t.integer :times_succeeded, null: false, default: 0
      t.integer :times_failed, null: false, default: 0
      t.datetime :last_matched_at

      t.timestamps
    end

    add_index :ai_model_routing_rules, [:account_id, :is_active, :priority],
              name: "idx_routing_rules_account_active_priority"
    add_index :ai_model_routing_rules, [:account_id, :rule_type]
    add_index :ai_model_routing_rules, :conditions, using: :gin

    # Add check constraint for rule_type
    execute <<-SQL
      ALTER TABLE ai_model_routing_rules
      ADD CONSTRAINT check_routing_rule_type
      CHECK (rule_type IN ('capability_based', 'cost_based', 'latency_based', 'quality_based', 'custom', 'ml_optimized'))
    SQL

    # Routing Decisions - logs each routing decision for analysis
    create_table :ai_routing_decisions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :routing_rule, foreign_key: { to_table: :ai_model_routing_rules }, type: :uuid
      t.references :selected_provider, foreign_key: { to_table: :ai_providers }, type: :uuid
      t.references :workflow_run, foreign_key: { to_table: :ai_workflow_runs }, type: :uuid
      t.references :agent_execution, foreign_key: { to_table: :ai_agent_executions }, type: :uuid

      # Request context
      t.string :request_type, null: false
      t.jsonb :request_metadata, null: false, default: {}
      t.integer :estimated_tokens

      # Decision details
      t.string :strategy_used, null: false
      t.jsonb :candidates_evaluated, null: false, default: []
      t.jsonb :scoring_breakdown, null: false, default: {}
      t.string :decision_reason

      # Outcome
      t.string :outcome # succeeded, failed, timeout, fallback
      t.decimal :actual_cost_usd, precision: 12, scale: 8
      t.integer :actual_latency_ms
      t.decimal :quality_score, precision: 5, scale: 4
      t.integer :actual_tokens_used

      # Cost comparison
      t.decimal :estimated_cost_usd, precision: 12, scale: 8
      t.decimal :alternative_cost_usd, precision: 12, scale: 8
      t.decimal :savings_usd, precision: 12, scale: 8

      t.timestamps
    end

    add_index :ai_routing_decisions, [:account_id, :created_at]
    add_index :ai_routing_decisions, [:selected_provider_id, :created_at]
    add_index :ai_routing_decisions, [:strategy_used, :outcome]
    add_index :ai_routing_decisions, :outcome
    add_index :ai_routing_decisions, :created_at

    # Cost Optimization Logs - tracks cost optimization opportunities and actions
    create_table :ai_cost_optimization_logs, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :optimization_type, null: false
      t.string :status, null: false, default: "identified"
      t.text :description

      # Financial impact
      t.decimal :current_cost_usd, precision: 12, scale: 4
      t.decimal :optimized_cost_usd, precision: 12, scale: 4
      t.decimal :potential_savings_usd, precision: 12, scale: 4
      t.decimal :actual_savings_usd, precision: 12, scale: 4
      t.decimal :savings_percentage, precision: 5, scale: 2

      # Context
      t.string :resource_type # provider, workflow, agent
      t.uuid :resource_id
      t.jsonb :recommendation, null: false, default: {}
      t.jsonb :before_state, null: false, default: {}
      t.jsonb :after_state, null: false, default: {}

      # Time tracking
      t.datetime :identified_at
      t.datetime :applied_at
      t.datetime :validated_at
      t.date :analysis_period_start
      t.date :analysis_period_end

      t.timestamps
    end

    add_index :ai_cost_optimization_logs, [:account_id, :status]
    add_index :ai_cost_optimization_logs, [:account_id, :optimization_type]
    add_index :ai_cost_optimization_logs, [:resource_type, :resource_id]
    add_index :ai_cost_optimization_logs, :created_at

    # Add check constraints
    execute <<-SQL
      ALTER TABLE ai_cost_optimization_logs
      ADD CONSTRAINT check_optimization_type
      CHECK (optimization_type IN ('provider_switch', 'model_downgrade', 'caching', 'batching', 'rate_optimization', 'usage_reduction'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_cost_optimization_logs
      ADD CONSTRAINT check_optimization_status
      CHECK (status IN ('identified', 'analyzing', 'recommended', 'applied', 'validated', 'rejected', 'expired'))
    SQL
  end
end
