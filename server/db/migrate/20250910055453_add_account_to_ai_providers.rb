# frozen_string_literal: true

class AddAccountToAiProviders < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_providers, :account, null: true, foreign_key: true, type: :uuid
    add_column :ai_providers, :api_endpoint, :string, limit: 500
  end
end
