# frozen_string_literal: true

# Instance principals (dev-cell / node-instance mTLS clients, resolved via
# Mcp::Principal.for_instance_cn) have no User, but McpSession and
# McpToolExecution required user_id NOT NULL — so an instance could never open
# an MCP session or record a tool execution, and the dev-cell autonomous
# executor's whole MCP loop (dev_next_task / dev_complete_task) failed at
# session open with "Validation failed: User must exist". (BUG-Q)
#
# Make user_id optional and record the principal generically (kind + subject id)
# so instance sessions are attributable without a core→extension FK to
# system_node_instances (core must not depend on the system extension). The
# USER path is unchanged: it keeps setting user_id, and principal_kind stays
# nil for existing/user rows.
class SupportInstancePrincipalMcpSessions < ActiveRecord::Migration[8.1]
  def change
    change_column_null :mcp_sessions, :user_id, true
    add_column :mcp_sessions, :principal_kind, :string
    add_column :mcp_sessions, :principal_subject_id, :uuid
    add_index :mcp_sessions, [ :principal_kind, :principal_subject_id ],
              name: "index_mcp_sessions_on_principal"

    change_column_null :mcp_tool_executions, :user_id, true
  end
end
