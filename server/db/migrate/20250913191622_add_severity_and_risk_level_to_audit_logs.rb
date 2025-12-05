# frozen_string_literal: true

class AddSeverityAndRiskLevelToAuditLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :audit_logs, :severity, :string, default: 'medium', null: false
    add_column :audit_logs, :risk_level, :string, default: 'low', null: false
    
    add_index :audit_logs, :severity
    add_index :audit_logs, :risk_level
  end
end
