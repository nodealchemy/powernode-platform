# frozen_string_literal: true

class CreateGitProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :git_providers, id: :uuid do |t|
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 50
      t.string :provider_type, null: false, limit: 30
      t.text :description
      t.string :api_base_url, limit: 500
      t.string :web_base_url, limit: 500
      t.jsonb :capabilities, null: false, default: []
      t.jsonb :oauth_config, default: {}
      t.jsonb :webhook_config, default: {}
      t.jsonb :ci_cd_config, default: {}
      t.boolean :is_active, default: true
      t.boolean :supports_oauth, default: true
      t.boolean :supports_pat, default: true
      t.boolean :supports_webhooks, default: true
      t.boolean :supports_ci_cd, default: false
      t.integer :priority_order, default: 1000
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :git_providers, :slug, unique: true
    add_index :git_providers, :provider_type
    add_index :git_providers, :is_active
    add_index :git_providers, :priority_order
    add_index :git_providers, :capabilities, using: :gin
  end
end
