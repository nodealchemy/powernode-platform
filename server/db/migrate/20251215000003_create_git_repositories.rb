# frozen_string_literal: true

class CreateGitRepositories < ActiveRecord::Migration[8.0]
  def change
    create_table :git_repositories, id: :uuid do |t|
      t.references :git_provider_credential, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :external_id, null: false, limit: 255
      t.string :name, null: false, limit: 255
      t.string :full_name, null: false, limit: 500
      t.string :owner, null: false, limit: 255
      t.text :description
      t.string :default_branch, limit: 255, default: "main"
      t.string :clone_url, limit: 500
      t.string :ssh_url, limit: 500
      t.string :web_url, limit: 500
      t.boolean :is_private, default: false
      t.boolean :is_fork, default: false
      t.boolean :is_archived, default: false
      t.boolean :has_issues, default: true
      t.boolean :has_pull_requests, default: true
      t.boolean :has_wiki, default: false
      t.boolean :webhook_configured, default: false
      t.string :webhook_id, limit: 255
      t.string :webhook_secret, limit: 255
      t.jsonb :languages, default: {}
      t.jsonb :topics, default: []
      t.jsonb :sync_settings, default: {}
      t.integer :stars_count, default: 0
      t.integer :forks_count, default: 0
      t.integer :open_issues_count, default: 0
      t.integer :open_prs_count, default: 0
      t.timestamp :last_synced_at
      t.timestamp :last_commit_at
      t.timestamp :provider_created_at
      t.timestamp :provider_updated_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :git_repositories, %i[account_id full_name], unique: true
    add_index :git_repositories, :external_id
    add_index :git_repositories, :owner
    add_index :git_repositories, :is_private
    add_index :git_repositories, :webhook_configured
    add_index :git_repositories, :last_synced_at
    add_index :git_repositories, :topics, using: :gin
  end
end
