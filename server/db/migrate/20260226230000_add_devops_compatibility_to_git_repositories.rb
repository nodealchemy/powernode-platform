# frozen_string_literal: true

class AddDevopsCompatibilityToGitRepositories < ActiveRecord::Migration[8.0]
  def change
    # Phase R1: Extend git_repositories to accept data from devops_repositories

    # Add is_active column (devops_repositories has this, git_repositories does not)
    add_column :git_repositories, :is_active, :boolean, default: true, null: false

    # Add devops_provider_id FK for records migrated from devops system
    add_column :git_repositories, :devops_provider_id, :uuid, null: true

    # Add origin column for provenance tracking
    add_column :git_repositories, :origin, :string, default: "git", null: false

    # Make git_provider_credential_id nullable (devops-origin records won't have a git credential)
    change_column_null :git_repositories, :git_provider_credential_id, true

    # Add FK to devops_providers
    add_foreign_key :git_repositories, :devops_providers, column: :devops_provider_id, on_delete: :nullify

    # Add indexes
    add_index :git_repositories, [:account_id, :devops_provider_id],
              name: "idx_git_repos_account_devops_provider",
              where: "devops_provider_id IS NOT NULL"
    add_index :git_repositories, :is_active, name: "idx_git_repos_is_active"
    add_index :git_repositories, :origin, name: "idx_git_repos_origin"
  end
end
