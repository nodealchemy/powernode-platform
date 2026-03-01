# frozen_string_literal: true

class AddVaultPathToCredentials < ActiveRecord::Migration[8.0]
  def change
    # Add Vault migration fields to AI provider credentials
    add_column :ai_provider_credentials, :vault_path, :string
    add_column :ai_provider_credentials, :migrated_to_vault_at, :datetime
    add_index :ai_provider_credentials, :vault_path, unique: true, where: "vault_path IS NOT NULL"

    # Make encrypted_credentials nullable (cleared after Vault migration)
    change_column_null :ai_provider_credentials, :encrypted_credentials, true

    # Add Vault migration fields to DevOps integration credentials
    add_column :devops_integration_credentials, :vault_path, :string
    add_column :devops_integration_credentials, :migrated_to_vault_at, :datetime
    add_index :devops_integration_credentials, :vault_path, unique: true, where: "vault_path IS NOT NULL"

    # Make encrypted_credentials nullable (cleared after Vault migration)
    change_column_null :devops_integration_credentials, :encrypted_credentials, true

    # Add Vault fields to MCP servers for OAuth tokens
    add_column :mcp_servers, :vault_path, :string
    add_column :mcp_servers, :migrated_to_vault_at, :datetime
    add_index :mcp_servers, :vault_path, unique: true, where: "vault_path IS NOT NULL"

    # Add federation and community fields to A2A tasks
    add_column :ai_a2a_tasks, :federation_task_id, :string
    add_column :ai_a2a_tasks, :federation_partner_id, :uuid
    add_column :ai_a2a_tasks, :community_agent_id, :uuid

    add_index :ai_a2a_tasks, :federation_task_id, where: "federation_task_id IS NOT NULL"
    add_foreign_key :ai_a2a_tasks, :federation_partners, column: :federation_partner_id, on_delete: :nullify
    add_foreign_key :ai_a2a_tasks, :community_agents, column: :community_agent_id, on_delete: :nullify
  end
end
