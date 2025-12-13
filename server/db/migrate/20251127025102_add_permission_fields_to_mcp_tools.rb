# frozen_string_literal: true

class AddPermissionFieldsToMcpTools < ActiveRecord::Migration[8.0]
  def change
    # Add permission fields to mcp_tools table
    add_column :mcp_tools, :required_permissions, :jsonb, default: [], null: false,
               comment: 'Array of permission strings required to execute this tool'

    add_column :mcp_tools, :permission_level, :string, default: 'public', null: false,
               comment: 'Permission level: public, account, admin'

    add_column :mcp_tools, :allowed_scopes, :jsonb, default: {}, null: false,
               comment: 'Allowed operation scopes (file_access, network, data, system, ai)'

    # Add check constraint for permission_level values
    add_check_constraint :mcp_tools, "permission_level IN ('public', 'account', 'admin')",
                        name: 'mcp_tools_permission_level_check'

    # Add index for permission-based queries
    add_index :mcp_tools, :permission_level
  end
end
