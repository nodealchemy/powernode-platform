# frozen_string_literal: true

class CreateIntegrationTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_templates, id: :uuid do |t|
      # Basic Information
      t.string :name, null: false
      t.string :slug, null: false
      t.string :integration_type, null: false  # github_action, webhook, mcp_server, rest_api, custom
      t.string :category  # ci_cd, notifications, monitoring, deployment, etc.
      t.string :version, default: "1.0.0"
      t.text :description
      t.string :icon_url
      t.string :documentation_url

      # Configuration Schemas (JSON Schema format)
      t.jsonb :configuration_schema, default: {}  # Schema for instance configuration
      t.jsonb :credential_requirements, default: {}  # What credentials are needed
      t.jsonb :capabilities, default: []  # List of capabilities this integration provides
      t.jsonb :input_schema, default: {}  # Expected input format
      t.jsonb :output_schema, default: {}  # Expected output format
      t.jsonb :default_configuration, default: {}  # Default values for configuration

      # Template Metadata
      t.jsonb :metadata, default: {}  # Additional metadata (author, tags, etc.)
      t.jsonb :supported_providers, default: []  # For git-related integrations

      # Visibility & Discovery
      t.boolean :is_public, default: false
      t.boolean :is_featured, default: false
      t.boolean :is_active, default: true

      # Usage Statistics
      t.integer :usage_count, default: 0
      t.integer :install_count, default: 0

      t.timestamps
    end

    add_index :integration_templates, :slug, unique: true
    add_index :integration_templates, :integration_type
    add_index :integration_templates, :category
    add_index :integration_templates, :is_public
    add_index :integration_templates, :is_featured
    add_index :integration_templates, :is_active
    add_index :integration_templates, [:is_public, :is_active], name: "idx_templates_public_active"
  end
end
