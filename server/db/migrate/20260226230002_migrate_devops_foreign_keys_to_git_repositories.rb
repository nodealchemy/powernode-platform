# frozen_string_literal: true

class MigrateDevopsForeignKeysToGitRepositories < ActiveRecord::Migration[8.0]
  def up
    # Phase R3: Re-point devops_pipeline_repositories and supply_chain_sboms to git_repositories

    # ============================
    # devops_pipeline_repositories
    # ============================

    # 1. Add new git_repository_id column
    add_column :devops_pipeline_repositories, :git_repository_id, :uuid, null: true

    # 2. Populate from mapping table
    execute <<~SQL
      UPDATE devops_pipeline_repositories dpr
      SET git_repository_id = rim.new_git_repository_id
      FROM repository_id_migrations rim
      WHERE dpr.devops_repository_id = rim.old_devops_repository_id
    SQL

    # 3. Verify zero NULLs
    null_count = execute(
      "SELECT COUNT(*) FROM devops_pipeline_repositories WHERE git_repository_id IS NULL"
    ).first["count"].to_i

    if null_count > 0
      raise "Migration validation failed: #{null_count} devops_pipeline_repositories have NULL git_repository_id"
    end

    # 4. Make NOT NULL and add FK
    change_column_null :devops_pipeline_repositories, :git_repository_id, false
    add_foreign_key :devops_pipeline_repositories, :git_repositories,
                    column: :git_repository_id, on_delete: :cascade

    # 5. Replace unique index
    remove_index :devops_pipeline_repositories,
                 name: "idx_pipeline_repos_on_pipeline_and_repo"
    add_index :devops_pipeline_repositories, [:devops_pipeline_id, :git_repository_id],
              name: "idx_pipeline_repos_on_pipeline_and_git_repo", unique: true
    add_index :devops_pipeline_repositories, :git_repository_id,
              name: "idx_pipeline_repos_on_git_repository_id"

    # 6. Drop old FK and column
    remove_foreign_key :devops_pipeline_repositories, :devops_repositories
    remove_index :devops_pipeline_repositories,
                 name: "index_devops_pipeline_repositories_on_devops_repository_id"
    remove_column :devops_pipeline_repositories, :devops_repository_id

    # ============================
    # supply_chain_sboms
    # ============================

    # 1. Add new git_repository_id column (nullable — repository is optional on SBOMs)
    add_column :supply_chain_sboms, :git_repository_id, :uuid, null: true

    # 2. Populate from mapping table (only for rows that have a repository_id)
    execute <<~SQL
      UPDATE supply_chain_sboms scs
      SET git_repository_id = rim.new_git_repository_id
      FROM repository_id_migrations rim
      WHERE scs.repository_id = rim.old_devops_repository_id
    SQL

    # 3. Add FK to git_repositories
    add_foreign_key :supply_chain_sboms, :git_repositories,
                    column: :git_repository_id, on_delete: :nullify

    # 4. Update repo-commit index to use new column
    remove_index :supply_chain_sboms, name: "idx_sboms_repo_commit"
    add_index :supply_chain_sboms, [:git_repository_id, :commit_sha],
              name: "idx_sboms_git_repo_commit"
    add_index :supply_chain_sboms, :git_repository_id,
              name: "idx_sboms_git_repository_id"

    # 5. Drop old FK and column
    remove_foreign_key :supply_chain_sboms, column: :repository_id
    remove_index :supply_chain_sboms, name: "index_supply_chain_sboms_on_repository_id"
    remove_column :supply_chain_sboms, :repository_id
  end

  def down
    # Reverse supply_chain_sboms
    add_column :supply_chain_sboms, :repository_id, :uuid, null: true

    execute <<~SQL
      UPDATE supply_chain_sboms scs
      SET repository_id = rim.old_devops_repository_id
      FROM repository_id_migrations rim
      WHERE scs.git_repository_id = rim.new_git_repository_id
    SQL

    add_foreign_key :supply_chain_sboms, :devops_repositories, column: :repository_id
    add_index :supply_chain_sboms, :repository_id, name: "index_supply_chain_sboms_on_repository_id"
    remove_index :supply_chain_sboms, name: "idx_sboms_git_repo_commit"
    remove_index :supply_chain_sboms, name: "idx_sboms_git_repository_id"
    add_index :supply_chain_sboms, [:repository_id, :commit_sha], name: "idx_sboms_repo_commit"
    remove_foreign_key :supply_chain_sboms, :git_repositories
    remove_column :supply_chain_sboms, :git_repository_id

    # Reverse devops_pipeline_repositories
    add_column :devops_pipeline_repositories, :devops_repository_id, :uuid, null: true

    execute <<~SQL
      UPDATE devops_pipeline_repositories dpr
      SET devops_repository_id = rim.old_devops_repository_id
      FROM repository_id_migrations rim
      WHERE dpr.git_repository_id = rim.new_git_repository_id
    SQL

    change_column_null :devops_pipeline_repositories, :devops_repository_id, false
    add_foreign_key :devops_pipeline_repositories, :devops_repositories, on_delete: :cascade
    add_index :devops_pipeline_repositories, :devops_repository_id,
              name: "index_devops_pipeline_repositories_on_devops_repository_id"
    remove_index :devops_pipeline_repositories, name: "idx_pipeline_repos_on_pipeline_and_git_repo"
    remove_index :devops_pipeline_repositories, name: "idx_pipeline_repos_on_git_repository_id"
    add_index :devops_pipeline_repositories, [:devops_pipeline_id, :devops_repository_id],
              name: "idx_pipeline_repos_on_pipeline_and_repo", unique: true
    remove_foreign_key :devops_pipeline_repositories, :git_repositories
    remove_column :devops_pipeline_repositories, :git_repository_id
  end
end
