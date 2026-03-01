# frozen_string_literal: true

class DropPluginSystemTables < ActiveRecord::Migration[8.0]
  def up
    # Drop all remaining plugin system tables
    tables_to_drop = %w[
      workflow_node_plugins
      ai_provider_plugins
      plugins
      plugin_marketplaces
      plugin_installations
      plugin_reviews
      plugin_dependencies
    ]

    tables_to_drop.each do |table|
      if table_exists?(table)
        execute("DROP TABLE IF EXISTS #{table} CASCADE")
        say "Dropped table: #{table}"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Plugin system has been completely removed and cannot be restored."
  end
end
