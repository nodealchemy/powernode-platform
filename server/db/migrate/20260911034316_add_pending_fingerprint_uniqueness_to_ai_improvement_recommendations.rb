# frozen_string_literal: true

# D1 review H2 — make code-quality offer dedupe race-proof.
#
# `create_improvement` dedupes by looking for an open (pending) offer with the
# same fingerprint on the same target, then inserting when there is none. Two
# sweeps running at once can both miss and both insert: nothing below the
# application enforced the dedupe, and the discovery clock's retrying POST
# could fan one tick out into many concurrent sweeps.
#
# WHY A COLUMN, NOT AN EXPRESSION INDEX OVER evidence->>'fingerprint'. An index
# over the existing jsonb key would have to hold for every pending row already
# in the table. Any duplicate pairs a past race left behind would make that
# index fail to build at deploy, and resolving them there would mean a
# migration dismissing offers nobody reviewed. The new column is NULL on every
# existing row, so those rows sit outside the partial index and the build
# cannot fail; `create_improvement` writes the column on every offer it files
# or refreshes from now on, and the index enforces one pending offer per
# (account, target, fingerprint) for all of them.
#
# Partial on status = 'pending', matching the application's rule: an approved,
# applied or dismissed offer does not block a new pending one for the same
# finding.
class AddPendingFingerprintUniquenessToAiImprovementRecommendations < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_improvement_recommendations, :fingerprint, :string
    add_index :ai_improvement_recommendations, %i[account_id target_type target_id fingerprint],
              unique: true, where: "status = 'pending' AND fingerprint IS NOT NULL",
              name: "index_ai_improvement_recs_on_pending_fingerprint"
  end
end
