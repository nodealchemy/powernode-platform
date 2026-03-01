# frozen_string_literal: true

class MigrateDevopsRepositoriesToGitRepositories < ActiveRecord::Migration[8.0]
  def up
    # Phase R2: Copy devops_repositories records into git_repositories with ID mapping

    # 1. Create temporary mapping table
    create_table :repository_id_migrations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :old_devops_repository_id, null: false
      t.uuid :new_git_repository_id, null: false
      t.string :merge_strategy, null: false # 'mapped_existing' or 'created_new'
      t.timestamps
    end

    add_index :repository_id_migrations, :old_devops_repository_id, unique: true,
              name: "idx_repo_id_migrations_old"
    add_index :repository_id_migrations, :new_git_repository_id,
              name: "idx_repo_id_migrations_new"

    # 2. Map devops_repositories that match existing git_repositories (same account_id + full_name)
    execute <<~SQL
      INSERT INTO repository_id_migrations (old_devops_repository_id, new_git_repository_id, merge_strategy, created_at, updated_at)
      SELECT dr.id, gr.id, 'mapped_existing', NOW(), NOW()
      FROM devops_repositories dr
      INNER JOIN git_repositories gr ON gr.account_id = dr.account_id AND gr.full_name = dr.full_name
    SQL

    # Set devops_provider_id on matched git_repositories
    execute <<~SQL
      UPDATE git_repositories gr
      SET devops_provider_id = dr.devops_provider_id
      FROM repository_id_migrations rim
      INNER JOIN devops_repositories dr ON dr.id = rim.old_devops_repository_id
      WHERE gr.id = rim.new_git_repository_id
        AND rim.merge_strategy = 'mapped_existing'
    SQL

    # 3. Insert new git_repositories for unmatched devops_repositories
    execute <<~SQL
      INSERT INTO git_repositories (
        id, account_id, name, full_name, owner, external_id, default_branch,
        description, clone_url, web_url, is_active, is_private, is_fork, is_archived,
        devops_provider_id, origin, metadata, last_synced_at,
        stars_count, forks_count, open_issues_count, languages, topics,
        webhook_configured, created_at, updated_at
      )
      SELECT
        gen_random_uuid(),
        dr.account_id,
        dr.name,
        dr.full_name,
        SPLIT_PART(dr.full_name, '/', 1),
        COALESCE(dr.external_id, dr.id::text),
        COALESCE(dr.default_branch, 'main'),
        COALESCE(dr.settings->>'description', ''),
        '',
        '',
        dr.is_active,
        COALESCE((dr.settings->>'private')::boolean, false),
        false,
        COALESCE((dr.settings->>'archived')::boolean, false),
        dr.devops_provider_id,
        'devops',
        COALESCE(dr.settings, '{}')::jsonb,
        dr.last_synced_at,
        0, 0, 0, '{}', '[]',
        false,
        dr.created_at,
        dr.updated_at
      FROM devops_repositories dr
      WHERE NOT EXISTS (
        SELECT 1 FROM repository_id_migrations rim WHERE rim.old_devops_repository_id = dr.id
      )
    SQL

    # 4. Record mappings for newly created records
    execute <<~SQL
      INSERT INTO repository_id_migrations (old_devops_repository_id, new_git_repository_id, merge_strategy, created_at, updated_at)
      SELECT dr.id, gr.id, 'created_new', NOW(), NOW()
      FROM devops_repositories dr
      INNER JOIN git_repositories gr ON gr.account_id = dr.account_id
        AND gr.full_name = dr.full_name
        AND gr.origin = 'devops'
      WHERE NOT EXISTS (
        SELECT 1 FROM repository_id_migrations rim WHERE rim.old_devops_repository_id = dr.id
      )
    SQL

    # 5. Validate: mapping count must equal devops_repositories count
    devops_count = execute("SELECT COUNT(*) FROM devops_repositories").first["count"].to_i
    mapping_count = execute("SELECT COUNT(*) FROM repository_id_migrations").first["count"].to_i

    if devops_count != mapping_count
      raise "Migration validation failed: #{devops_count} devops_repositories but #{mapping_count} mappings created"
    end
  end

  def down
    # Remove newly created devops-origin git_repositories
    execute <<~SQL
      DELETE FROM git_repositories
      WHERE id IN (
        SELECT new_git_repository_id FROM repository_id_migrations WHERE merge_strategy = 'created_new'
      )
    SQL

    # Clear devops_provider_id on mapped records
    execute <<~SQL
      UPDATE git_repositories gr
      SET devops_provider_id = NULL
      FROM repository_id_migrations rim
      WHERE gr.id = rim.new_git_repository_id AND rim.merge_strategy = 'mapped_existing'
    SQL

    drop_table :repository_id_migrations
  end
end
