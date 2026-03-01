# frozen_string_literal: true

class DropDevopsRepositoriesTable < ActiveRecord::Migration[8.0]
  def up
    # Phase R6: Clean up old tables after successful migration

    # Drop the temporary mapping table
    drop_table :repository_id_migrations, if_exists: true

    # Drop the old devops_repositories table
    drop_table :devops_repositories, if_exists: true
  end

  def down
    # Recreate devops_repositories table (schema only — data is not recoverable)
    create_table :devops_repositories, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :account_id, null: false
      t.string :name
      t.string :full_name
      t.string :default_branch
      t.string :external_id
      t.uuid :devops_provider_id
      t.boolean :is_active, default: true
      t.jsonb :settings, default: {}
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :devops_repositories, [:account_id, :full_name], unique: true
    add_index :devops_repositories, :account_id
    add_index :devops_repositories, :devops_provider_id
    add_index :devops_repositories, :external_id
    add_foreign_key :devops_repositories, :accounts, on_delete: :cascade
    add_foreign_key :devops_repositories, :devops_providers, on_delete: :cascade

    # Recreate mapping table (empty)
    create_table :repository_id_migrations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :old_devops_repository_id, null: false
      t.uuid :new_git_repository_id, null: false
      t.string :merge_strategy, null: false
      t.timestamps
    end
  end
end
