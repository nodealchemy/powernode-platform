# frozen_string_literal: true

# Creates the CI/CD Pipeline Management System
# Stores pipeline configurations, prompts, providers, and schedules in the database
# for dynamic management through the frontend interface
class CreateCiCdPipelineSystem < ActiveRecord::Migration[8.0]
  def change
    # ============================================
    # CI/CD Providers (Gitea, GitHub, GitLab, etc.)
    # ============================================
    create_table :ci_cd_providers, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }

      t.string :name, null: false
      t.string :provider_type, null: false  # gitea, github, gitlab, jenkins
      t.string :base_url, null: false
      t.string :api_version, default: 'v1'

      # Encrypted credentials reference (actual secrets in Rails credentials or vault)
      t.string :credential_key  # Key to lookup in credentials store
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :capabilities, null: false, default: []  # What this provider supports

      t.boolean :is_active, null: false, default: true
      t.boolean :is_default, null: false, default: false
      t.datetime :last_health_check_at
      t.string :health_status  # healthy, degraded, unhealthy

      t.timestamps
    end

    add_index :ci_cd_providers, [ :account_id, :name ], unique: true
    add_index :ci_cd_providers, [ :account_id, :is_default ], where: 'is_default = true'

    # ============================================
    # AI Provider Configurations for CI/CD
    # ============================================
    create_table :ci_cd_ai_configs, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }

      t.string :name, null: false
      t.string :provider_type, null: false  # anthropic, bedrock, vertex
      t.string :model_id, null: false
      t.string :credential_key  # Key to lookup API key

      # Model configuration
      t.integer :max_tokens, default: 8192
      t.integer :max_thinking_tokens, default: 4096
      t.integer :timeout_seconds, default: 300
      t.float :temperature, default: 0.7

      t.jsonb :configuration, null: false, default: {}
      t.boolean :is_active, null: false, default: true
      t.boolean :is_default, null: false, default: false
      t.integer :priority, default: 1  # For fallback ordering

      t.timestamps
    end

    add_index :ci_cd_ai_configs, [ :account_id, :name ], unique: true
    add_index :ci_cd_ai_configs, [ :account_id, :is_default ], where: 'is_default = true'
    add_index :ci_cd_ai_configs, [ :account_id, :priority ]

    # ============================================
    # Prompt Templates (reusable across pipelines)
    # ============================================
    create_table :ci_cd_prompt_templates, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }

      t.string :name, null: false
      t.string :slug, null: false  # URL-friendly identifier
      t.string :category, null: false  # review, implement, security, deploy, custom
      t.text :description

      # Template content with variable placeholders
      t.text :content, null: false
      t.jsonb :variables, null: false, default: []  # Expected variables with types/defaults
      t.jsonb :metadata, null: false, default: {}

      # Versioning
      t.integer :version, null: false, default: 1
      t.references :parent_template, type: :uuid, foreign_key: { to_table: :ci_cd_prompt_templates, on_delete: :nullify }

      t.boolean :is_active, null: false, default: true
      t.boolean :is_system, null: false, default: false  # System templates can't be deleted

      t.timestamps
    end

    add_index :ci_cd_prompt_templates, [ :account_id, :slug ], unique: true
    add_index :ci_cd_prompt_templates, [ :account_id, :category ]
    add_index :ci_cd_prompt_templates, :is_system

    # ============================================
    # Pipeline Definitions (the main configuration)
    # ============================================
    create_table :ci_cd_pipelines, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :ci_cd_provider, type: :uuid, foreign_key: { on_delete: :restrict }
      t.references :ci_cd_ai_config, type: :uuid, foreign_key: { on_delete: :restrict }

      t.string :name, null: false
      t.string :slug, null: false
      t.string :pipeline_type, null: false  # review, implement, security, deploy, custom
      t.text :description

      # Trigger configuration
      t.jsonb :triggers, null: false, default: {}
      # Example: { "pull_request": ["opened", "synchronize"], "issue_comment": ["created"], "schedule": "0 2 * * 1" }

      # Steps configuration (ordered array of step definitions)
      t.jsonb :steps, null: false, default: []
      # Example: [{ "name": "checkout", "type": "action", "config": {...} }, ...]

      # Environment and secrets references
      t.jsonb :environment, null: false, default: {}
      t.jsonb :secret_refs, null: false, default: []  # Names of secrets to inject

      # Runtime configuration
      t.string :runner_labels, array: true, default: [ 'ubuntu-latest' ]
      t.integer :timeout_minutes, default: 60
      t.boolean :allow_concurrent, null: false, default: false

      # Feature flags
      t.jsonb :features, null: false, default: {}
      # Example: { "auto_approve": false, "require_tests": true, "block_on_critical": true }

      t.boolean :is_active, null: false, default: true
      t.boolean :is_system, null: false, default: false
      t.integer :version, null: false, default: 1

      t.timestamps
    end

    add_index :ci_cd_pipelines, [ :account_id, :slug ], unique: true
    add_index :ci_cd_pipelines, [ :account_id, :pipeline_type ]
    add_index :ci_cd_pipelines, [ :account_id, :is_active ]

    # ============================================
    # Pipeline Steps (detailed step configurations)
    # ============================================
    create_table :ci_cd_pipeline_steps, id: :uuid do |t|
      t.references :ci_cd_pipeline, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :ci_cd_prompt_template, type: :uuid, foreign_key: { on_delete: :nullify }

      t.string :name, null: false
      t.string :step_type, null: false  # checkout, claude_execute, post_comment, create_pr, upload_artifact, etc.
      t.integer :position, null: false, default: 0

      # Step configuration
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :inputs, null: false, default: {}  # Input mappings from previous steps
      t.jsonb :outputs, null: false, default: []  # Output definitions

      # Conditional execution
      t.text :condition  # Expression like "steps.review.outputs.approved == 'true'"
      t.boolean :continue_on_error, null: false, default: false

      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :ci_cd_pipeline_steps, [ :ci_cd_pipeline_id, :position ]
    add_index :ci_cd_pipeline_steps, [ :ci_cd_pipeline_id, :name ], unique: true

    # ============================================
    # Pipeline Runs (execution history)
    # ============================================
    create_table :ci_cd_pipeline_runs, id: :uuid do |t|
      t.references :ci_cd_pipeline, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :triggered_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }

      t.string :run_number, null: false
      t.string :status, null: false, default: 'pending'  # pending, queued, running, success, failure, cancelled
      t.string :trigger_type, null: false  # manual, pull_request, issue, schedule, webhook

      # Context from the trigger
      t.jsonb :trigger_context, null: false, default: {}
      # Example: { "pr_number": 123, "commit_sha": "abc123", "branch": "feature/x" }

      # Execution tracking
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_seconds

      # Results
      t.jsonb :outputs, null: false, default: {}
      t.jsonb :artifacts, null: false, default: []
      t.text :error_message

      # External reference (if synced to CI provider)
      t.string :external_run_id
      t.string :external_run_url

      t.timestamps
    end

    add_index :ci_cd_pipeline_runs, [ :ci_cd_pipeline_id, :run_number ], unique: true
    add_index :ci_cd_pipeline_runs, [ :ci_cd_pipeline_id, :status ]
    add_index :ci_cd_pipeline_runs, :external_run_id

    # ============================================
    # Step Executions (individual step results)
    # ============================================
    create_table :ci_cd_step_executions, id: :uuid do |t|
      t.references :ci_cd_pipeline_run, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :ci_cd_pipeline_step, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.string :status, null: false, default: 'pending'  # pending, running, success, failure, skipped
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_seconds

      # Results
      t.jsonb :outputs, null: false, default: {}
      t.text :logs
      t.text :error_message

      t.timestamps
    end

    add_index :ci_cd_step_executions, [ :ci_cd_pipeline_run_id, :ci_cd_pipeline_step_id ], unique: true,
              name: 'idx_step_executions_on_run_and_step'

    # ============================================
    # Scheduled Pipelines
    # ============================================
    create_table :ci_cd_schedules, id: :uuid do |t|
      t.references :ci_cd_pipeline, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }

      t.string :name, null: false
      t.string :cron_expression, null: false  # Cron syntax
      t.string :timezone, default: 'UTC'

      t.jsonb :inputs, null: false, default: {}  # Input variables for scheduled runs
      t.datetime :next_run_at
      t.datetime :last_run_at

      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :ci_cd_schedules, [ :ci_cd_pipeline_id, :is_active ]
    add_index :ci_cd_schedules, :next_run_at, where: 'is_active = true'

    # ============================================
    # Repository Configurations
    # ============================================
    create_table :ci_cd_repositories, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :ci_cd_provider, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.string :name, null: false
      t.string :full_name, null: false  # owner/repo
      t.string :default_branch, default: 'main'
      t.string :external_id  # Provider's ID for the repo

      t.jsonb :settings, null: false, default: {}
      # Example: { "protected_branches": ["main"], "review_required_paths": ["**/*.rb"] }

      t.boolean :is_active, null: false, default: true
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :ci_cd_repositories, [ :account_id, :full_name ], unique: true
    add_index :ci_cd_repositories, :external_id

    # ============================================
    # Pipeline-Repository Association
    # ============================================
    create_table :ci_cd_pipeline_repositories, id: :uuid do |t|
      t.references :ci_cd_pipeline, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :ci_cd_repository, type: :uuid, null: false, foreign_key: { on_delete: :cascade }

      t.jsonb :overrides, null: false, default: {}  # Repository-specific overrides

      t.timestamps
    end

    add_index :ci_cd_pipeline_repositories, [ :ci_cd_pipeline_id, :ci_cd_repository_id ], unique: true,
              name: 'idx_pipeline_repos_on_pipeline_and_repo'
  end
end
