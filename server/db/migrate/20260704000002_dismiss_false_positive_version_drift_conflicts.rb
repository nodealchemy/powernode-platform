# frozen_string_literal: true

# Ai::SkillGraph::ConflictDetectionService#detect_version_drift used to group
# skills by the first word of their name, so unrelated skills that merely
# share a prefix ("SDWAN Create Network" vs "SDWAN Delete Network",
# "Architecture …", "Package …") were flagged as version_drift conflicts.
# The detector is now fixed to key on real lineage (Ai::Skill#cloned_from_id
# + a 3-way-merge divergence check) — see ConflictDetectionService#
# detect_version_drift. This migration retires the conflicts the old,
# crude detector created that the corrected one would never have created:
# any active version_drift row whose two skills have no real lineage
# relationship between them at all. A pair that IS genuinely linked
# (direct cloned_from_id relation either direction, or a shared non-blank
# source_key) is left active — it may still represent a real divergence,
# and the next scan will supersede it with a fully-detailed conflict via
# the corrected detector's own dedupe (create_conflict_if_new).
#
# Reuses Ai::SkillConflict#dismiss! (the same resolution path the live
# conflict UI/AutoRepairService use) rather than hand-rolling a status
# update, so dismissed_at/resolved_by bookkeeping stays consistent.
#
# Also normalizes existing active "overlapping" conflicts from severity
# "medium" down to "low" — the detector now creates new overlapping rows
# as advisory ("low"), and HealthScoreService#calculate_conflict_penalty
# is now severity-weighted (F6); leaving old rows at "medium" would let
# stale rows keep outweighing genuine conflicts.
#
# Idempotent: dismissed rows fall out of the `.active` scope, so re-running
# only touches whatever is still active (none, on a clean re-run).
class DismissFalsePositiveVersionDriftConflicts < ActiveRecord::Migration[8.1]
  def up
    dismissed = 0

    Ai::SkillConflict.where(conflict_type: "version_drift").active.find_each do |conflict|
      skill_a = Ai::Skill.find_by(id: conflict.skill_a_id)
      skill_b = Ai::Skill.find_by(id: conflict.skill_b_id)

      next if skill_a && skill_b && real_lineage?(skill_a, skill_b)

      conflict.dismiss!
      dismissed += 1
    end

    Rails.logger.info "[Migration] Dismissed #{dismissed} false-positive version_drift conflicts (name-prefix detector artifacts)"

    normalized = Ai::SkillConflict.where(conflict_type: "overlapping", severity: "medium").active
      .update_all(severity: "low")
    Rails.logger.info "[Migration] Normalized #{normalized} active overlapping conflicts from severity medium -> low"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def real_lineage?(skill_a, skill_b)
    return true if skill_a.cloned_from_id == skill_b.id || skill_b.cloned_from_id == skill_a.id
    return true if skill_a.source_key.present? && skill_a.source_key == skill_b.source_key

    false
  end
end
