# frozen_string_literal: true

# Why an improvement offer was dismissed.
#
# dismiss_improvement accepted only a recommendation_id, so the record said THAT
# an offer was closed and never WHY. "the work landed in <sha>", "this is noise"
# and "the finding is wrong" were indistinguishable afterwards — and the
# scoreboard's funnel counts all three identically as `dismissed`, which is the
# one bucket where that distinction decides whether the discovery pass is
# earning its keep.
#
# Mirrors ai_ralph_tasks.revert_reason, which is the same disposition-with-a-
# reason shape and already exists beside reverted_at. A COLUMN rather than a key
# in `evidence`: evidence is what the FINDER recorded about the defect, and an
# operator's disposition is not evidence about the code.
#
# Nullable with no default and no backfill. Every already-dismissed row was
# closed without a reason being captured, and inventing one ("dismissed") would
# assert a decision nobody made — NULL says "not recorded", which is true.
class AddDismissReasonToAiImprovementRecommendations < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_improvement_recommendations, :dismiss_reason, :text
  end
end
