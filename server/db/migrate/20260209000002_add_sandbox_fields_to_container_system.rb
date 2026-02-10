# frozen_string_literal: true

class AddSandboxFieldsToContainerSystem < ActiveRecord::Migration[8.0]
  def change
    # Enhance container templates for AI sandbox mode
    add_column :devops_container_templates, :mcp_bridge_config, :jsonb, default: {}
    add_column :devops_container_templates, :storage_mounts, :jsonb, default: []
    add_column :devops_container_templates, :trust_level_required, :string

    # Enhance container instances for sandbox tracking
    add_column :devops_container_instances, :sandbox_mode, :boolean, default: false
    add_column :devops_container_instances, :mcp_bridge_port, :integer
    add_column :devops_container_instances, :trust_level, :string
    add_column :devops_container_instances, :storage_mounts, :jsonb, default: []

    add_index :devops_container_instances, :sandbox_mode
    add_index :devops_container_instances, :trust_level
  end
end
