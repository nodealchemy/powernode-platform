# frozen_string_literal: true

# Universal Plugin System Migration
# Supports AI providers, workflow nodes, and extensible plugin types
class CreateUniversalPluginSystem < ActiveRecord::Migration[7.1]
  def change
    # Plugin Marketplaces - can host plugins from any platform
    create_table :plugin_marketplaces, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :creator, type: :uuid, null: false, foreign_key: { to_table: :users }

      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.string :owner, null: false, limit: 255
      t.text :description
      t.string :marketplace_type, null: false, default: 'private'
      t.string :source_type, null: false  # 'git', 'npm', 'local', 'url'
      t.string :source_url, limit: 500
      t.string :visibility, default: 'private', null: false  # 'public', 'private', 'team'
      t.integer :plugin_count, default: 0
      t.decimal :average_rating, precision: 3, scale: 2

      t.jsonb :configuration, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps

      t.index [:account_id, :slug], unique: true
      t.index :marketplace_type
      t.index :visibility
    end

    # Universal Plugins - can be AI providers, workflow nodes, or future types
    create_table :plugins, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :creator, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.references :source_marketplace, type: :uuid, foreign_key: { to_table: :plugin_marketplaces }

      # Plugin identity
      t.string :plugin_id, null: false, limit: 255  # Unique identifier (com.example.plugin)
      t.string :name, null: false, limit: 255
      t.string :slug, null: false, limit: 255
      t.text :description
      t.string :version, null: false, limit: 20
      t.string :author, limit: 255
      t.string :homepage, limit: 500
      t.string :license, limit: 50

      # Plugin types (can have multiple)
      t.string :plugin_types, array: true, default: [], null: false  # ['ai_provider', 'workflow_node', 'integration']

      # Source management
      t.string :source_type, null: false  # 'git', 'npm', 'local', 'url', 'marketplace'
      t.string :source_url, limit: 500
      t.string :source_ref, limit: 255  # branch, tag, or commit

      # Status and availability
      t.string :status, default: 'available', null: false  # 'available', 'installed', 'error', 'deprecated'
      t.boolean :is_verified, default: false
      t.boolean :is_official, default: false

      # Manifest and configuration
      t.jsonb :manifest, default: {}, null: false
      t.jsonb :capabilities, default: [], null: false
      t.jsonb :configuration, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false

      # Statistics
      t.integer :install_count, default: 0
      t.integer :download_count, default: 0
      t.decimal :average_rating, precision: 3, scale: 2
      t.integer :rating_count, default: 0

      t.timestamps

      t.index [:account_id, :plugin_id], unique: true
      t.index [:account_id, :slug], unique: true
      t.index :plugin_types, using: :gin
      t.index :status
      t.index :source_type
      t.index :is_verified
      t.index :is_official
      t.index :capabilities, using: :gin
    end

    # Plugin Installations - tracks installed plugins per account
    create_table :plugin_installations, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :plugin, type: :uuid, null: false, foreign_key: true
      t.references :installed_by, type: :uuid, null: false, foreign_key: { to_table: :users }

      t.string :status, default: 'active', null: false  # 'active', 'inactive', 'error', 'updating'
      t.datetime :installed_at, null: false
      t.datetime :last_activated_at
      t.datetime :last_used_at

      # Installation configuration (user-specific overrides)
      t.jsonb :configuration, default: {}, null: false
      t.jsonb :credentials, default: {}, null: false  # Encrypted in application
      t.jsonb :installation_metadata, default: {}, null: false

      # Usage tracking
      t.integer :execution_count, default: 0
      t.decimal :total_cost, precision: 10, scale: 4, default: 0.0

      t.timestamps

      t.index [:account_id, :plugin_id], unique: true
      t.index :status
      t.index :installed_at
    end

    # AI Provider Plugins - specific table for AI provider type
    create_table :ai_provider_plugins, id: :uuid do |t|
      t.references :plugin, type: :uuid, null: false, foreign_key: true

      t.string :provider_type, null: false  # 'openai_compatible', 'anthropic_compatible', 'custom'
      t.jsonb :supported_capabilities, default: [], null: false
      t.jsonb :models, default: [], null: false
      t.jsonb :authentication_schema, default: {}, null: false
      t.jsonb :default_configuration, default: {}, null: false

      t.timestamps

      t.index :provider_type
      t.index :supported_capabilities, using: :gin
    end

    # Workflow Node Plugins - specific table for workflow node type
    create_table :workflow_node_plugins, id: :uuid do |t|
      t.references :plugin, type: :uuid, null: false, foreign_key: true

      t.string :node_type, null: false
      t.string :node_category, null: false  # 'data', 'logic', 'integration', 'ai', 'custom'
      t.jsonb :input_schema, default: {}, null: false
      t.jsonb :output_schema, default: {}, null: false
      t.jsonb :configuration_schema, default: {}, null: false
      t.jsonb :ui_configuration, default: {}, null: false  # Icon, color, layout hints

      t.timestamps

      t.index :node_type
      t.index :node_category
    end

    # Plugin Reviews and Ratings
    create_table :plugin_reviews, id: :uuid do |t|
      t.references :plugin, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true

      t.integer :rating, null: false  # 1-5
      t.text :review_text
      t.boolean :is_verified_purchase, default: false
      t.string :plugin_version, limit: 20

      t.timestamps

      t.index [:plugin_id, :account_id], unique: true
      t.index :rating
    end

    # Plugin Dependencies
    create_table :plugin_dependencies, id: :uuid do |t|
      t.references :plugin, type: :uuid, null: false, foreign_key: true
      t.string :dependency_plugin_id, null: false
      t.string :version_constraint  # '>= 1.0.0', '~> 2.1'
      t.boolean :is_required, default: true

      t.timestamps

      t.index [:plugin_id, :dependency_plugin_id], unique: true
    end

    # Add plugin support to workflow nodes
    add_column :ai_workflow_nodes, :plugin_id, :uuid, null: true
    add_foreign_key :ai_workflow_nodes, :plugins
    add_index :ai_workflow_nodes, :plugin_id

    # Add provider_identifier to ai_providers for plugin integration
    add_column :ai_providers, :provider_identifier, :string, limit: 255
    add_index :ai_providers, [:account_id, :provider_identifier], unique: true
  end
end
