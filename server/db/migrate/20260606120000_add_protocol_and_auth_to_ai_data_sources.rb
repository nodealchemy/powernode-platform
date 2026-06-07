# frozen_string_literal: true

class AddProtocolAndAuthToAiDataSources < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_data_sources, :protocol, :string, null: false, default: "rest"
    add_column :ai_data_sources, :auth_scheme, :string, null: false, default: "none"
    add_column :ai_data_sources, :auth_config, :jsonb, default: {}
  end
end
