# frozen_string_literal: true

class CreateAiProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_providers, id: :uuid do |t|
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 50
      t.string :provider_type, null: false, limit: 50
      t.text :description
      t.string :api_base_url, limit: 500
      t.jsonb :capabilities, null: false, default: []
      t.jsonb :supported_models, null: false, default: []
      t.jsonb :configuration_schema, null: false, default: {}
      t.jsonb :default_parameters, default: {}
      t.jsonb :rate_limits, default: {}
      t.jsonb :pricing_info, default: {}
      t.boolean :is_active, default: true
      t.boolean :requires_auth, default: true
      t.boolean :supports_streaming, default: false
      t.boolean :supports_functions, default: false
      t.boolean :supports_vision, default: false
      t.boolean :supports_code_execution, default: false
      t.string :documentation_url, limit: 500
      t.string :status_url, limit: 500
      t.integer :priority_order, default: 1000
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :name
      t.index :slug, unique: true
      t.index :provider_type
      t.index :is_active
      t.index [:provider_type, :is_active]
      t.index :priority_order
    end

    add_index :ai_providers, :capabilities, using: 'gin'
    add_index :ai_providers, :supported_models, using: 'gin'
  end
end