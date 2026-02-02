# frozen_string_literal: true

# Sandbox Testing Tables - Enterprise AI Agent Testing Infrastructure
#
# Revenue Model: Sandbox environments + testing infrastructure
# - Basic sandbox: included
# - Advanced testing: $99/mo (recording, playback)
# - Performance profiling: $199/mo
# - Enterprise (dedicated environments): $499/mo
#
class CreateSandboxTestingTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # SANDBOXES - Isolated test environments
    # ==========================================================================
    create_table :ai_sandboxes, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.text :description
      t.string :sandbox_type, null: false, default: "standard"
      t.string :status, null: false, default: "inactive"
      t.jsonb :configuration, default: {}
      t.jsonb :mock_providers, default: {}
      t.jsonb :environment_variables, default: {}
      t.jsonb :resource_limits, default: {}
      t.boolean :is_isolated, null: false, default: true
      t.boolean :recording_enabled, null: false, default: false
      t.integer :test_runs_count, default: 0
      t.integer :total_executions, default: 0
      t.datetime :last_used_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :ai_sandboxes, [ :account_id, :name ], unique: true
    add_index :ai_sandboxes, :status
    add_index :ai_sandboxes, :sandbox_type
    add_index :ai_sandboxes, :expires_at

    # ==========================================================================
    # TEST SCENARIOS - Test case definitions
    # ==========================================================================
    create_table :ai_test_scenarios, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sandbox, null: false, foreign_key: { to_table: :ai_sandboxes }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.references :target_workflow, foreign_key: { to_table: :ai_workflows }, type: :uuid
      t.references :target_agent, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.string :name, null: false
      t.text :description
      t.string :scenario_type, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :input_data, default: {}
      t.jsonb :expected_output, default: {}
      t.jsonb :assertions, default: []
      t.jsonb :setup_steps, default: []
      t.jsonb :teardown_steps, default: []
      t.jsonb :mock_responses, default: []
      t.jsonb :tags, default: []
      t.integer :timeout_seconds, default: 300
      t.integer :retry_count, default: 0
      t.integer :max_retries, default: 3
      t.integer :run_count, default: 0
      t.integer :pass_count, default: 0
      t.integer :fail_count, default: 0
      t.float :pass_rate
      t.datetime :last_run_at

      t.timestamps
    end

    add_index :ai_test_scenarios, [ :sandbox_id, :name ], unique: true
    add_index :ai_test_scenarios, [ :account_id, :status ]
    add_index :ai_test_scenarios, :scenario_type

    # ==========================================================================
    # MOCK RESPONSES - Mocked AI provider responses
    # ==========================================================================
    create_table :ai_mock_responses, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sandbox, null: false, foreign_key: { to_table: :ai_sandboxes }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :provider_type, null: false
      t.string :model_name
      t.string :endpoint
      t.string :match_type, null: false, default: "exact"
      t.jsonb :match_criteria, default: {}
      t.jsonb :response_data, default: {}
      t.integer :latency_ms, default: 100
      t.float :error_rate, default: 0
      t.string :error_type
      t.string :error_message
      t.boolean :is_active, null: false, default: true
      t.integer :priority, default: 0
      t.integer :hit_count, default: 0
      t.datetime :last_hit_at

      t.timestamps
    end

    add_index :ai_mock_responses, [ :sandbox_id, :provider_type ]
    add_index :ai_mock_responses, [ :sandbox_id, :is_active, :priority ]
    add_index :ai_mock_responses, :match_type

    # ==========================================================================
    # TEST RUNS - Test execution records
    # ==========================================================================
    create_table :ai_test_runs, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sandbox, null: false, foreign_key: { to_table: :ai_sandboxes }, type: :uuid
      t.references :triggered_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :run_id, null: false
      t.string :run_type, null: false, default: "manual"
      t.string :status, null: false, default: "pending"
      t.jsonb :scenario_ids, default: []
      t.integer :total_scenarios, default: 0
      t.integer :passed_scenarios, default: 0
      t.integer :failed_scenarios, default: 0
      t.integer :skipped_scenarios, default: 0
      t.integer :total_assertions, default: 0
      t.integer :passed_assertions, default: 0
      t.integer :failed_assertions, default: 0
      t.jsonb :summary, default: {}
      t.jsonb :environment, default: {}
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_test_runs, :run_id, unique: true
    add_index :ai_test_runs, [ :account_id, :status ]
    add_index :ai_test_runs, [ :sandbox_id, :created_at ]
    add_index :ai_test_runs, :run_type

    # ==========================================================================
    # TEST RESULTS - Individual scenario results
    # ==========================================================================
    create_table :ai_test_results, id: :uuid do |t|
      t.references :test_run, null: false, foreign_key: { to_table: :ai_test_runs }, type: :uuid
      t.references :scenario, null: false, foreign_key: { to_table: :ai_test_scenarios }, type: :uuid
      t.string :result_id, null: false
      t.string :status, null: false
      t.jsonb :input_used, default: {}
      t.jsonb :actual_output, default: {}
      t.jsonb :assertion_results, default: []
      t.jsonb :error_details, default: {}
      t.jsonb :logs, default: []
      t.jsonb :metrics, default: {}
      t.integer :duration_ms
      t.integer :tokens_used, default: 0
      t.decimal :cost_usd, precision: 10, scale: 4, default: 0
      t.integer :retry_attempt, default: 0
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_test_results, :result_id, unique: true
    add_index :ai_test_results, [ :test_run_id, :status ]
    add_index :ai_test_results, [ :scenario_id, :created_at ]

    # ==========================================================================
    # RECORDED INTERACTIONS - Captured AI interactions for replay
    # ==========================================================================
    create_table :ai_recorded_interactions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sandbox, null: false, foreign_key: { to_table: :ai_sandboxes }, type: :uuid
      t.references :source_workflow_run, foreign_key: { to_table: :ai_workflow_runs }, type: :uuid
      t.string :recording_id, null: false
      t.string :interaction_type, null: false
      t.string :provider_type
      t.string :model_name
      t.jsonb :request_data, default: {}
      t.jsonb :response_data, default: {}
      t.jsonb :metadata, default: {}
      t.integer :latency_ms
      t.integer :tokens_input, default: 0
      t.integer :tokens_output, default: 0
      t.decimal :cost_usd, precision: 10, scale: 4, default: 0
      t.integer :sequence_number
      t.datetime :recorded_at

      t.timestamps
    end

    add_index :ai_recorded_interactions, :recording_id, unique: true
    add_index :ai_recorded_interactions, [ :sandbox_id, :recorded_at ]
    add_index :ai_recorded_interactions, :interaction_type

    # ==========================================================================
    # PERFORMANCE BENCHMARKS - Performance comparison baselines
    # ==========================================================================
    create_table :ai_performance_benchmarks, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :sandbox, foreign_key: { to_table: :ai_sandboxes }, type: :uuid
      t.references :target_workflow, foreign_key: { to_table: :ai_workflows }, type: :uuid
      t.references :target_agent, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :benchmark_id, null: false
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "active"
      t.jsonb :baseline_metrics, default: {}
      t.jsonb :thresholds, default: {}
      t.jsonb :test_config, default: {}
      t.integer :sample_size, default: 100
      t.integer :run_count, default: 0
      t.jsonb :latest_results, default: {}
      t.float :latest_score
      t.string :trend
      t.datetime :last_run_at

      t.timestamps
    end

    add_index :ai_performance_benchmarks, :benchmark_id, unique: true
    add_index :ai_performance_benchmarks, [ :account_id, :status ]

    # ==========================================================================
    # A/B TEST CONFIGURATIONS - A/B testing infrastructure
    # ==========================================================================
    create_table :ai_ab_tests, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :test_id, null: false
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "draft"
      t.string :target_type, null: false
      t.uuid :target_id, null: false
      t.jsonb :variants, default: []
      t.jsonb :traffic_allocation, default: {}
      t.jsonb :success_metrics, default: []
      t.jsonb :results, default: {}
      t.integer :total_impressions, default: 0
      t.integer :total_conversions, default: 0
      t.string :winning_variant
      t.float :statistical_significance
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :ai_ab_tests, :test_id, unique: true
    add_index :ai_ab_tests, [ :account_id, :status ]
    add_index :ai_ab_tests, [ :target_type, :target_id ]

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_sandboxes
      ADD CONSTRAINT check_sandbox_type
      CHECK (sandbox_type IN ('standard', 'isolated', 'production_mirror', 'performance', 'security'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_sandboxes
      ADD CONSTRAINT check_sandbox_status
      CHECK (status IN ('inactive', 'active', 'paused', 'expired', 'deleted'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_test_scenarios
      ADD CONSTRAINT check_scenario_type
      CHECK (scenario_type IN ('unit', 'integration', 'regression', 'performance', 'security', 'chaos', 'custom'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_test_scenarios
      ADD CONSTRAINT check_scenario_status
      CHECK (status IN ('draft', 'active', 'disabled', 'archived'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_mock_responses
      ADD CONSTRAINT check_mock_match_type
      CHECK (match_type IN ('exact', 'contains', 'regex', 'semantic', 'always'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_test_runs
      ADD CONSTRAINT check_test_run_type
      CHECK (run_type IN ('manual', 'scheduled', 'ci_triggered', 'regression', 'smoke'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_test_runs
      ADD CONSTRAINT check_test_run_status
      CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'timeout'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_test_results
      ADD CONSTRAINT check_test_result_status
      CHECK (status IN ('passed', 'failed', 'skipped', 'error', 'timeout'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_recorded_interactions
      ADD CONSTRAINT check_interaction_type
      CHECK (interaction_type IN ('llm_request', 'tool_call', 'api_call', 'workflow_step', 'agent_action'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_performance_benchmarks
      ADD CONSTRAINT check_benchmark_status
      CHECK (status IN ('active', 'paused', 'archived'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_ab_tests
      ADD CONSTRAINT check_ab_test_status
      CHECK (status IN ('draft', 'running', 'paused', 'completed', 'cancelled'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_ab_tests
      ADD CONSTRAINT check_ab_target_type
      CHECK (target_type IN ('workflow', 'agent', 'prompt', 'model', 'provider'))
    SQL
  end
end
