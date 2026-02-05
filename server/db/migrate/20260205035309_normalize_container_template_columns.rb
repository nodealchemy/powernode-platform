# frozen_string_literal: true

class NormalizeContainerTemplateColumns < ActiveRecord::Migration[8.1]
  def up
    # Rename existing column to match API interface
    rename_column :mcp_container_templates, :allow_network, :network_access

    # Promote nested jsonb fields to proper columns
    add_column :mcp_container_templates, :memory_mb, :integer, default: 512
    add_column :mcp_container_templates, :cpu_millicores, :integer, default: 500

    # Add missing columns the controller permits
    add_column :mcp_container_templates, :category, :string
    add_column :mcp_container_templates, :sandbox_mode, :boolean, default: true
    add_column :mcp_container_templates, :input_schema, :jsonb, default: {}
    add_column :mcp_container_templates, :output_schema, :jsonb, default: {}
    add_column :mcp_container_templates, :allowed_egress_domains, :jsonb, default: []

    add_index :mcp_container_templates, :category

    # Migrate data from resource_limits jsonb to new columns
    execute <<~SQL
      UPDATE mcp_container_templates
      SET memory_mb = COALESCE((resource_limits->>'memory_mb')::integer, 512),
          cpu_millicores = COALESCE((resource_limits->>'cpu_millicores')::integer, 500)
      WHERE resource_limits IS NOT NULL AND resource_limits != '{}'::jsonb
    SQL
  end

  def down
    remove_index :mcp_container_templates, :category

    remove_column :mcp_container_templates, :allowed_egress_domains
    remove_column :mcp_container_templates, :output_schema
    remove_column :mcp_container_templates, :input_schema
    remove_column :mcp_container_templates, :sandbox_mode
    remove_column :mcp_container_templates, :category
    remove_column :mcp_container_templates, :cpu_millicores
    remove_column :mcp_container_templates, :memory_mb

    rename_column :mcp_container_templates, :network_access, :allow_network
  end
end
