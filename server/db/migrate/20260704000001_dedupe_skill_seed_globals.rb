# frozen_string_literal: true

# Reconciles duplicate is_system Ai::Skill rows created by a since-fixed seed
# bug (db/seeds/ai_skills_seed.rb): globals were upserted via
# `find_or_initialize_by(source_key:, account_id: nil)`. A pre-globalization
# ACCOUNT-scoped row (source_key nil) never matches that finder, so
# re-seeding INSERTED a brand-new, empty global row instead of converting the
# account row in place. For every affected slug the account-scoped row holds
# the real associations (agent bindings, MCP server links, KG node); the new
# global row has none.
#
# Survivor = the global row (it's the one seeds will keep finding by
# slug/source_key going forward). Its associations are backfilled from each
# account-scoped leftover via Ai::SkillGraph::AutoRepairService#merge_associations
# (the same reassignment path the live conflict auto-repair uses), then the
# leftover is deleted. Real user clones (cloned_from_id present) are never
# touched — only seed dupes (cloned_from_id IS NULL on both sides) qualify;
# a legitimate account customization is always a clone (is_system: false),
# never an is_system: true row, so this filter alone rules them out.
# Idempotent: a slug with no coexisting global+account is_system pair is
# skipped, so re-running is a no-op.
class DedupeSkillSeedGlobals < ActiveRecord::Migration[8.1]
  def up
    dupe_slugs = Ai::Skill.where(is_system: true)
                           .group(:slug)
                           .having("COUNT(*) > 1")
                           .pluck(:slug)

    dupe_slugs.each do |slug|
      rows   = Ai::Skill.where(is_system: true, slug: slug, cloned_from_id: nil).to_a
      winner = rows.find { |r| r.account_id.nil? }
      losers = rows.select { |r| r.account_id.present? }
      next if winner.nil? || losers.empty?

      losers.each do |loser|
        ActiveRecord::Base.transaction do
          Ai::SkillGraph::AutoRepairService.new(nil).merge_associations(winner: winner, loser: loser)
          # merge_associations just moved the KG node off of `loser` by
          # mutating it in place — but `loser`'s has_one association cache
          # still holds that (now stale) reference, and destroy's
          # dependent: :nullify callback would use the cache as-is,
          # clobbering the just-reassigned node's ai_skill_id back to nil.
          # Reload to drop all cached associations before destroying.
          loser.reload.destroy!
        end
        Rails.logger.info "[Migration] Deduped skill seed global '#{slug}' — kept #{winner.id}, removed #{loser.id}"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
