# frozen_string_literal: true

class CreateAiSecurityAuditTrails < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_security_audit_trails, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.uuid :agent_id
      t.uuid :user_id
      t.string :action, null: false
      t.string :outcome, null: false
      t.string :asi_reference
      t.string :csa_pillar
      t.decimal :risk_score, precision: 5, scale: 4
      t.jsonb :context, default: {}
      t.jsonb :details, default: {}
      t.string :source_service
      t.string :severity
      t.inet :ip_address
      t.timestamps
    end

    add_index :ai_security_audit_trails, :agent_id
    add_index :ai_security_audit_trails, :action
    add_index :ai_security_audit_trails, :asi_reference
    add_index :ai_security_audit_trails, :outcome
    add_index :ai_security_audit_trails, :severity
    add_index :ai_security_audit_trails, :created_at
  end
end
