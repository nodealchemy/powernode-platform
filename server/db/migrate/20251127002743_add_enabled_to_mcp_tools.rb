# frozen_string_literal: true

class AddEnabledToMcpTools < ActiveRecord::Migration[8.0]
  def change
    add_column :mcp_tools, :enabled, :boolean, default: true, null: false
  end
end
