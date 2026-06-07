# frozen_string_literal: true

class AddVaultPathToAiDataSourceCredentials < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_data_source_credentials, :vault_path, :string
    add_column :ai_data_source_credentials, :migrated_to_vault_at, :datetime
  end
end
