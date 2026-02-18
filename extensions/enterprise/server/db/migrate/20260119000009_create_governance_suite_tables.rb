# frozen_string_literal: true

# Governance Suite Tables - AI Workflow Governance & Compliance
#
# Revenue Model: Enterprise licensing + compliance certifications
# - Compliance add-on: $299-999/mo based on tier
# - SOC 2 certification support: $5,000 one-time
# - Dedicated compliance officer support: $2,000/mo
# - Custom policy development: $10,000+
#
class CreateGovernanceSuiteTables < ActiveRecord::Migration[8.0]
  def change
    # ==========================================================================
    # COMPLIANCE POLICIES - Rules for AI operations
    # ==========================================================================
    create_table :ai_compliance_policies, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :policy_type, null: false
      t.string :category
      t.text :description
      t.string :status, null: false, default: "draft"
      t.string :enforcement_level, null: false, default: "warn"
      t.jsonb :conditions, default: {}
      t.jsonb :actions, default: {}
      t.jsonb :exceptions, default: []
      t.jsonb :applies_to, default: {}
      t.boolean :is_system, null: false, default: false
      t.boolean :is_required, null: false, default: false
      t.integer :priority, default: 0
      t.integer :violation_count, default: 0
      t.datetime :last_triggered_at
      t.datetime :activated_at

      t.timestamps
    end

    add_index :ai_compliance_policies, [ :account_id, :name ], unique: true
    add_index :ai_compliance_policies, [ :account_id, :status ]
    add_index :ai_compliance_policies, :policy_type
    add_index :ai_compliance_policies, :enforcement_level
    add_index :ai_compliance_policies, :is_system

    # ==========================================================================
    # POLICY VIOLATIONS - Detected compliance violations
    # ==========================================================================
    create_table :ai_policy_violations, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :policy, null: false, foreign_key: { to_table: :ai_compliance_policies }, type: :uuid
      t.references :detected_by, foreign_key: { to_table: :users }, type: :uuid
      t.references :resolved_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :violation_id, null: false
      t.string :severity, null: false
      t.string :status, null: false, default: "open"
      t.string :source_type
      t.uuid :source_id
      t.text :description, null: false
      t.text :context
      t.jsonb :violation_data, default: {}
      t.jsonb :remediation_steps, default: []
      t.text :resolution_notes
      t.string :resolution_action
      t.datetime :detected_at, null: false
      t.datetime :acknowledged_at
      t.datetime :resolved_at
      t.datetime :escalated_at

      t.timestamps
    end

    add_index :ai_policy_violations, :violation_id, unique: true
    add_index :ai_policy_violations, [ :account_id, :status ]
    add_index :ai_policy_violations, [ :policy_id, :created_at ]
    add_index :ai_policy_violations, :severity
    add_index :ai_policy_violations, :source_type

    # ==========================================================================
    # APPROVAL CHAINS - Multi-step approval workflows
    # ==========================================================================
    create_table :ai_approval_chains, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :created_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.text :description
      t.string :trigger_type, null: false
      t.jsonb :trigger_conditions, default: {}
      t.jsonb :steps, default: []
      t.string :status, null: false, default: "active"
      t.boolean :is_sequential, null: false, default: true
      t.integer :timeout_hours
      t.string :timeout_action, default: "reject"
      t.integer :usage_count, default: 0

      t.timestamps
    end

    add_index :ai_approval_chains, [ :account_id, :name ], unique: true
    add_index :ai_approval_chains, [ :account_id, :status ]
    add_index :ai_approval_chains, :trigger_type

    # ==========================================================================
    # APPROVAL REQUESTS - Individual approval instances
    # ==========================================================================
    create_table :ai_approval_requests, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :approval_chain, null: false, foreign_key: { to_table: :ai_approval_chains }, type: :uuid
      t.references :requested_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :request_id, null: false
      t.string :status, null: false, default: "pending"
      t.string :source_type
      t.uuid :source_id
      t.text :description
      t.jsonb :request_data, default: {}
      t.jsonb :step_statuses, default: []
      t.integer :current_step, default: 0
      t.datetime :expires_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_approval_requests, :request_id, unique: true
    add_index :ai_approval_requests, [ :account_id, :status ]
    add_index :ai_approval_requests, [ :approval_chain_id, :created_at ]
    add_index :ai_approval_requests, :expires_at

    # ==========================================================================
    # APPROVAL DECISIONS - Individual approver decisions
    # ==========================================================================
    create_table :ai_approval_decisions, id: :uuid do |t|
      t.references :approval_request, null: false, foreign_key: { to_table: :ai_approval_requests }, type: :uuid
      t.references :approver, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.integer :step_number, null: false
      t.string :decision, null: false
      t.text :comments
      t.jsonb :conditions, default: {}

      t.timestamps
    end

    add_index :ai_approval_decisions, [ :approval_request_id, :step_number ]
    add_index :ai_approval_decisions, [ :approver_id, :created_at ]

    # ==========================================================================
    # DATA CLASSIFICATIONS - PII/sensitive data tracking
    # ==========================================================================
    create_table :ai_data_classifications, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :classified_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :name, null: false
      t.string :classification_level, null: false
      t.text :description
      t.jsonb :detection_patterns, default: []
      t.jsonb :handling_requirements, default: {}
      t.jsonb :retention_policy, default: {}
      t.boolean :requires_encryption, null: false, default: false
      t.boolean :requires_masking, null: false, default: false
      t.boolean :requires_audit, null: false, default: true
      t.boolean :is_system, null: false, default: false
      t.integer :detection_count, default: 0

      t.timestamps
    end

    add_index :ai_data_classifications, [ :account_id, :name ], unique: true
    add_index :ai_data_classifications, :classification_level
    add_index :ai_data_classifications, :is_system

    # ==========================================================================
    # DATA DETECTIONS - Detected sensitive data instances
    # ==========================================================================
    create_table :ai_data_detections, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :classification, null: false, foreign_key: { to_table: :ai_data_classifications }, type: :uuid
      t.string :detection_id, null: false
      t.string :source_type, null: false
      t.uuid :source_id, null: false
      t.string :field_path
      t.string :action_taken, null: false, default: "logged"
      t.text :original_snippet
      t.text :masked_snippet
      t.float :confidence_score
      t.jsonb :detection_metadata, default: {}

      t.timestamps
    end

    add_index :ai_data_detections, :detection_id, unique: true
    add_index :ai_data_detections, [ :account_id, :created_at ]
    add_index :ai_data_detections, [ :classification_id, :created_at ]
    add_index :ai_data_detections, :source_type
    add_index :ai_data_detections, :action_taken

    # ==========================================================================
    # COMPLIANCE REPORTS - Generated compliance documentation
    # ==========================================================================
    create_table :ai_compliance_reports, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :generated_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :report_id, null: false
      t.string :report_type, null: false
      t.string :status, null: false, default: "generating"
      t.string :format, null: false, default: "pdf"
      t.datetime :period_start
      t.datetime :period_end
      t.jsonb :report_config, default: {}
      t.jsonb :summary_data, default: {}
      t.string :file_path
      t.bigint :file_size_bytes
      t.datetime :generated_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :ai_compliance_reports, :report_id, unique: true
    add_index :ai_compliance_reports, [ :account_id, :report_type ]
    add_index :ai_compliance_reports, :status
    add_index :ai_compliance_reports, :generated_at

    # ==========================================================================
    # AUDIT TRAIL ENTRIES - Detailed compliance audit log
    # ==========================================================================
    create_table :ai_compliance_audit_entries, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :user, foreign_key: true, type: :uuid
      t.string :entry_id, null: false
      t.string :action_type, null: false
      t.string :resource_type, null: false
      t.uuid :resource_id
      t.string :outcome, null: false
      t.text :description
      t.jsonb :before_state, default: {}
      t.jsonb :after_state, default: {}
      t.jsonb :context, default: {}
      t.string :ip_address
      t.string :user_agent
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :ai_compliance_audit_entries, :entry_id, unique: true
    add_index :ai_compliance_audit_entries, [ :account_id, :occurred_at ]
    add_index :ai_compliance_audit_entries, [ :resource_type, :resource_id ]
    add_index :ai_compliance_audit_entries, :action_type
    add_index :ai_compliance_audit_entries, :outcome

    # ==========================================================================
    # CONSTRAINTS
    # ==========================================================================
    execute <<-SQL
      ALTER TABLE ai_compliance_policies
      ADD CONSTRAINT check_policy_type
      CHECK (policy_type IN ('data_access', 'model_usage', 'output_filter', 'rate_limit', 'cost_limit', 'approval_required', 'retention', 'audit', 'custom'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_compliance_policies
      ADD CONSTRAINT check_policy_status
      CHECK (status IN ('draft', 'active', 'disabled', 'archived'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_compliance_policies
      ADD CONSTRAINT check_enforcement_level
      CHECK (enforcement_level IN ('log', 'warn', 'block', 'require_approval'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_policy_violations
      ADD CONSTRAINT check_violation_severity
      CHECK (severity IN ('low', 'medium', 'high', 'critical'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_policy_violations
      ADD CONSTRAINT check_violation_status
      CHECK (status IN ('open', 'acknowledged', 'investigating', 'resolved', 'dismissed', 'escalated'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_approval_chains
      ADD CONSTRAINT check_chain_trigger_type
      CHECK (trigger_type IN ('workflow_deploy', 'agent_deploy', 'high_cost', 'sensitive_data', 'model_change', 'policy_override', 'manual'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_approval_requests
      ADD CONSTRAINT check_request_status
      CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'cancelled'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_approval_decisions
      ADD CONSTRAINT check_decision_type
      CHECK (decision IN ('approved', 'rejected', 'delegated', 'abstained'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_data_classifications
      ADD CONSTRAINT check_classification_level
      CHECK (classification_level IN ('public', 'internal', 'confidential', 'restricted', 'pii', 'phi', 'pci'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_data_detections
      ADD CONSTRAINT check_detection_action
      CHECK (action_taken IN ('logged', 'masked', 'blocked', 'encrypted', 'flagged'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_compliance_reports
      ADD CONSTRAINT check_report_type
      CHECK (report_type IN ('soc2', 'hipaa', 'gdpr', 'pci_dss', 'iso27001', 'custom', 'audit_summary', 'violation_summary', 'data_inventory'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_compliance_reports
      ADD CONSTRAINT check_report_status
      CHECK (status IN ('generating', 'completed', 'failed', 'expired'))
    SQL

    execute <<-SQL
      ALTER TABLE ai_compliance_audit_entries
      ADD CONSTRAINT check_audit_outcome
      CHECK (outcome IN ('success', 'failure', 'blocked', 'warning'))
    SQL
  end
end
