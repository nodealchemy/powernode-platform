# frozen_string_literal: true

# Portability (Tier-2): wire an optional repository pointer onto shared
# knowledge entries so knowledge can be scoped to a specific
# Devops::GitRepository for uncontaminated per-project recall.
#
# Nullable for backcompat — existing rows remain valid without a repository.
# on_delete: :nullify (NOT cascade): knowledge accumulation must survive
# repository deletion, orphaning the pointer rather than the row.
class AddGitRepositoryToAiSharedKnowledges < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_shared_knowledges,
                  :git_repository,
                  type: :uuid,
                  null: true,
                  index: true,
                  foreign_key: { to_table: :git_repositories, on_delete: :nullify }
  end
end
