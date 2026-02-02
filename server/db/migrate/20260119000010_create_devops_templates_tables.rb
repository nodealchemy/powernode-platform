# frozen_string_literal: true

# DevOps Templates Tables - AI Pipeline Templates for DevOps
#
# Revenue Model: Template marketplace + enterprise customization
# - Community templates: free
# - Premium templates: $29-99 one-time
# - Custom template development: $2,000-10,000
# - Enterprise template library: $199/mo
#
class CreateDevopsTemplatesTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # DEVOPS TEMPLATES - Pre-built AI workflow templates for DevOps
    # ==========================================================================
    create_table :ai_devops_templates, id: :uuid do |t|
      t.references :account, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :category, null: false
      t.string :template_type, null: false
      t.string :status, null: false, default: "draft"
      t.string :visibility, null: false, default: "private"
      t.string :version, null: false, default: "1.0.0"
      t.jsonb :workflow_definition, default: {}
      t.jsonb :trigger_config, default: {}
      t.jsonb :input_schema, default: {}
      t.jsonb :output_schema, default: {}
      t.jsonb :variables, default: []
      t.jsonb :secrets_required, default: []
      t.jsonb :integrations_required, default: []
      t.jsonb :tags, default: []
      t.text :usage_guide
      t.boolean :is_system, null: false, default: false
      t.boolean :is_featured, null: false, default: false
      t.decimal :price_usd, precision: 10, scale: 2
      t.integer :installation_count, default: 0
      t.float :average_rating
      t.integer :review_count, default: 0
      t.datetime :published_at

      t.timestamps
    end

    add_index :ai_devops_templates, :slug, unique: true
    add_index :ai_devops_templates, [ :status, :visibility ]
    add_index :ai_devops_templates, :category
    add_index :ai_devops_templates, :template_type
    add_index :ai_devops_templates, :is_system
    add_index :ai_devops_templates, :is_featured

    # ==========================================================================
    # DEVOPS TEMPLATE INSTALLATIONS - Installed templates per account
    # ==========================================================================
    create_table :ai_devops_template_installations, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :devops_template, null: false, foreign_key: { to_table: :ai_devops_templates }, type: :uuid
      t.references :installed_by, foreign_key: { to_table: :users }, type: :uuid
      t.references :created_workflow, foreign_key: { to_table: :ai_workflows }, type: :uuid
      t.string :status, null: false, default: "active"
      t.string :installed_version
      t.jsonb :custom_config, default: {}
      t.jsonb :variable_values, default: {}
      t.integer :execution_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.datetime :last_executed_at

      t.timestamps
    end

    add_index :ai_devops_template_installations, [ :account_id, :devops_template_id ], unique: true, name: "idx_devops_installations_account_template"
    add_index :ai_devops_template_installations, :status

    # ==========================================================================
    # PIPELINE EXECUTIONS - AI-enhanced pipeline run tracking
    # ==========================================================================
    create_table :ai_pipeline_executions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :devops_installation, foreign_key: { to_table: :ai_devops_template_installations }, type: :uuid
      t.references :workflow_run, foreign_key: { to_table: :ai_workflow_runs }, type: :uuid
      t.references :triggered_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :execution_id, null: false
      t.string :pipeline_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :trigger_source
      t.string :trigger_event
      t.uuid :repository_id
      t.string :branch
      t.string :commit_sha
      t.string :pull_request_number
      t.jsonb :input_data, default: {}
      t.jsonb :output_data, default: {}
      t.jsonb :ai_analysis, default: {}
      t.jsonb :metrics, default: {}
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_pipeline_executions, :execution_id, unique: true
    add_index :ai_pipeline_executions, [ :account_id, :status ]
    add_index :ai_pipeline_executions, [ :repository_id, :created_at ]
    add_index :ai_pipeline_executions, :pipeline_type
    add_index :ai_pipeline_executions, :trigger_source

    # ==========================================================================
    # DEPLOYMENT RISK ASSESSMENTS - AI-powered deployment risk analysis
    # ==========================================================================
    create_table :ai_deployment_risks, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :pipeline_execution, foreign_key: { to_table: :ai_pipeline_executions }, type: :uuid
      t.references :assessed_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :assessment_id, null: false
      t.string :deployment_type, null: false
      t.string :target_environment, null: false
      t.string :risk_level, null: false
      t.integer :risk_score
      t.string :status, null: false, default: "pending"
      t.string :decision
      t.jsonb :risk_factors, default: []
      t.jsonb :change_analysis, default: {}
      t.jsonb :impact_analysis, default: {}
      t.jsonb :recommendations, default: []
      t.jsonb :mitigations, default: []
      t.text :summary
      t.text :decision_rationale
      t.boolean :requires_approval, null: false, default: false
      t.uuid :approval_request_id
      t.datetime :assessed_at
      t.datetime :decision_at

      t.timestamps
    end

    add_index :ai_deployment_risks, :assessment_id, unique: true
    add_index :ai_deployment_risks, [ :account_id, :created_at ]
    add_index :ai_deployment_risks, :risk_level
    add_index :ai_deployment_risks, :target_environment
    add_index :ai_deployment_risks, :status

    # ==========================================================================
    # CODE REVIEW ANALYSIS - AI-powered code review results
    # ==========================================================================
    create_table :ai_code_reviews, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :pipeline_execution, foreign_key: { to_table: :ai_pipeline_executions }, type: :uuid
      t.string :review_id, null: false
      t.string :status, null: false, default: "pending"
      t.uuid :repository_id
      t.string :pull_request_number
      t.string :commit_sha
      t.string :base_branch
      t.string :head_branch
      t.integer :files_reviewed, default: 0
      t.integer :lines_added, default: 0
      t.integer :lines_removed, default: 0
      t.integer :issues_found, default: 0
      t.integer :critical_issues, default: 0
      t.integer :suggestions_count, default: 0
      t.jsonb :file_analyses, default: []
      t.jsonb :issues, default: []
      t.jsonb :suggestions, default: []
      t.jsonb :security_findings, default: []
      t.jsonb :quality_metrics, default: {}
      t.text :summary
      t.string :overall_rating
      t.integer :tokens_used, default: 0
      t.decimal :cost_usd, precision: 10, scale: 4, default: 0
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_code_reviews, :review_id, unique: true
    add_index :ai_code_reviews, [ :account_id, :created_at ]
    add_index :ai_code_reviews, [ :repository_id, :pull_request_number ]
    add_index :ai_code_reviews, :status

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_devops_templates
      ADD CONSTRAINT check_devops_category
      CHECK (category IN ('code_quality', 'deployment', 'documentation', 'testing', 'security', 'monitoring', 'release', 'custom'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_devops_templates
      ADD CONSTRAINT check_devops_template_type
      CHECK (template_type IN ('code_review', 'security_scan', 'test_generation', 'deployment_validation', 'release_notes', 'changelog', 'api_docs', 'coverage_analysis', 'performance_check', 'custom'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_devops_templates
      ADD CONSTRAINT check_devops_status
      CHECK (status IN ('draft', 'pending_review', 'published', 'archived', 'deprecated'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_devops_templates
      ADD CONSTRAINT check_devops_visibility
      CHECK (visibility IN ('private', 'team', 'public', 'marketplace'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_devops_template_installations
      ADD CONSTRAINT check_devops_installation_status
      CHECK (status IN ('active', 'paused', 'disabled', 'pending_update'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_pipeline_executions
      ADD CONSTRAINT check_pipeline_type
      CHECK (pipeline_type IN ('pr_review', 'commit_analysis', 'deployment', 'release', 'scheduled', 'manual'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_pipeline_executions
      ADD CONSTRAINT check_pipeline_status
      CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'timeout'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_deployment_risks
      ADD CONSTRAINT check_risk_level
      CHECK (risk_level IN ('low', 'medium', 'high', 'critical'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_deployment_risks
      ADD CONSTRAINT check_risk_status
      CHECK (status IN ('pending', 'assessed', 'approved', 'rejected', 'overridden'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_deployment_risks
      ADD CONSTRAINT check_risk_decision
      CHECK (decision IS NULL OR decision IN ('proceed', 'proceed_with_caution', 'delay', 'abort'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_code_reviews
      ADD CONSTRAINT check_review_status
      CHECK (status IN ('pending', 'analyzing', 'completed', 'failed', 'partial'))
    SQL
  end
end
