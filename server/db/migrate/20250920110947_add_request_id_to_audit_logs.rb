# frozen_string_literal: true

class AddRequestIdToAuditLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :audit_logs, :request_id, :string, limit: 50
    add_index :audit_logs, :request_id
  end
end
