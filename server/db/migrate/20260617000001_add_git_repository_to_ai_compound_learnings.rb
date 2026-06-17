# frozen_string_literal: true

# Portability (Tier-2): wire an optional repository pointer onto compound
# learnings so accumulated learnings can be scoped to a specific
# Devops::GitRepository for uncontaminated per-project recall.
#
# Nullable for backcompat — existing rows remain valid without a repository.
# on_delete: :nullify (NOT cascade): these are accumulation/analytics rows that
# must survive repository deletion, orphaning the pointer rather than the row.
class AddGitRepositoryToAiCompoundLearnings < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_compound_learnings,
                  :git_repository,
                  type: :uuid,
                  null: true,
                  index: true,
                  foreign_key: { to_table: :git_repositories, on_delete: :nullify }
  end
end
