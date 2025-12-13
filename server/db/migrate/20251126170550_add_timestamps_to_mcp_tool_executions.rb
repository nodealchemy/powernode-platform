# frozen_string_literal: true

class AddTimestampsToMcpToolExecutions < ActiveRecord::Migration[8.0]
  def change
    add_column :mcp_tool_executions, :started_at, :datetime
    add_column :mcp_tool_executions, :completed_at, :datetime
    add_column :mcp_tool_executions, :duration_ms, :integer
  end
end
