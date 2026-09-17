# frozen_string_literal: true

# IMP-077c2471b85a / operator ruling 2026-09-13 (b). One-shot operator step:
# drain every non-empty `ai_ralph_loops.learnings` row into CompoundLearning via
# Ai::Learning::RalphLearningExtractor, then empty the column. This ships in
# this release; the drop-column migration that refuses while any row is still
# non-empty is a DEFERRED follow-up (D4, 2026-09-17) — a refusing migration
# cannot ship in the same release as its own remedy, because rails-start.sh
# runs db:migrate under `set -e` before exec puma, and a boot-time refusal
# would leave the backend unable to start. Every reader of the column is
# already retired in THIS release (state_machine.rb, storage_metrics.rb,
# ralph_loop_tool.rb), so the column sits dormant and unread until the
# follow-up drops it; this task is how an operator drains it in the meantime,
# or ahead of that follow-up landing.
#
# WHY A RAKE TASK AND NOT INLINE IN THE MIGRATION. The extractor needs account
# context (CompoundLearningService is scoped per account) and calls out to the
# worker's embedding service at run time — both wrong things to depend on inside
# a migration, which can run unattended at boot on a live node.
#
# THIS COLUMN IS THE ONLY COPY, so every write here follows one rule: a row is
# rewritten to hold EXACTLY the entries not yet confirmed durable, never a
# blanket []. Three ways that would otherwise fail silently (all caught in
# review, none by the original draft):
#
#   1. PER-ENTRY, NOT PER-BATCH. Ai::Learning::RalphLearningExtractor#extract
#      sums a block under ONE method-level rescue — a raise on entry 3 of 5
#      aborts entries 4-5 unattempted, returns 0 (byte-identical to "everything
#      deduped"), and a caller that trusts that 0 to clear the column destroys
#      3, 4 and 5. #extract_entry! is the non-rescuing per-entry sibling: this
#      task calls it once per entry, in its OWN begin/rescue, so one entry's
#      failure can never take an unattempted sibling down with it, and a caught
#      raise is DISTINGUISHABLE from a legitimate dedup (which returns `false`,
#      not a raise — either way the content is durably represented, so both
#      truthy and `false` drop the entry; only a raise keeps it).
#   2. A HEALTHY PROBE AT t0 IS NOT A LICENSE FOR t1..tn. The per-account
#      embedding-service probe below only rules out "already down before this
#      account's batch starts" — it says nothing about entry 40 of 200. The
#      per-entry confirmation in (1) is what actually guards every entry; the
#      probe is a fast-fail so an account-wide outage is reported once instead
#      of as N identical per-entry failures.
#   3. UNRECOGNIZED SHAPE MUST STOP, NOT DISCARD. A non-empty row that is not a
#      list of `{"text" => ...}` hashes (a bare jsonb object, a JSON string, an
#      array keyed "learning"/"content" from an older writer) fails the entry
#      filter silently — nothing about "no usable entries" implies "safe to
#      clear". That loop is left untouched and counted as skipped, printing the
#      raw value so an operator can look at it.
namespace :ai do
  desc "One-shot: drain leftover ai_ralph_loops.learnings rows into CompoundLearning, then empty the column (idempotent; run before the drop-column migration)"
  task drain_dormant_ralph_learnings: :environment do
    totals = { accounts: 0, loops: 0, stored: 0, entries_kept: 0, loops_skipped: 0 }
    stopped_on = nil

    # A re-run after the drop-column migration has already applied must be a
    # clean no-op, not a "column does not exist" crash — the migration is the
    # eventual, expected end state this task is a precondition for.
    unless ActiveRecord::Base.connection.column_exists?(:ai_ralph_loops, :learnings)
      line = "[ai:drain_dormant_ralph_learnings] nothing to drain — ai_ralph_loops.learnings is already dropped"
      Rails.logger.info(line)
      puts line
      next
    end

    account_ids = Ai::RalphLoop.where("learnings IS NOT NULL AND learnings <> '[]'::jsonb").distinct.pluck(:account_id)

    if account_ids.empty?
      line = "[ai:drain_dormant_ralph_learnings] nothing to drain — every loop's learnings column is already empty"
      Rails.logger.info(line)
      puts line
      next
    end

    account_ids.each do |account_id|
      break if stopped_on

      account = Account.find_by(id: account_id)
      if account.nil?
        stopped_on = "account=#{account_id}: no such account (orphaned row)"
        break
      end

      # Fast-fail on an outage already present before this account's batch
      # starts. This is NOT the safety guard — see (2) above — it only avoids
      # spending N identical per-entry failures finding out what one call
      # would have shown.
      begin
        Ai::Memory::EmbeddingService.new(account: account)
          .generate("ai:drain_dormant_ralph_learnings health probe", use_cache: false)
      rescue StandardError => e
        stopped_on = "account=#{account.id}: embedding service unreachable (#{e.class}: #{e.message})"
        break
      end

      loops = Ai::RalphLoop.where(account: account)
                            .where("learnings IS NOT NULL AND learnings <> '[]'::jsonb")

      loops.find_each do |loop_record|
        entries = Array(loop_record.learnings)
        usable, unrecognized = entries.partition { |e| e.is_a?(Hash) && e["text"].present? }

        if unrecognized.any?
          line = "[ai:drain_dormant_ralph_learnings] SKIPPED loop=#{loop_record.id}: " \
                 "#{unrecognized.size} entr#{unrecognized.size == 1 ? 'y' : 'ies'} in an unrecognized shape, " \
                 "column left intact: #{unrecognized.inspect}"
          Rails.logger.warn(line)
          puts line
          totals[:loops_skipped] += 1
          next
        end

        extractor = Ai::Learning::RalphLearningExtractor.new(account: account)
        kept = []
        stored = 0

        usable.each do |entry|
          begin
            result = extractor.extract_entry!(loop_record, entry)
            stored += 1 if result
            # result == false: a near-duplicate already exists durably in
            # CompoundLearning (boosted) — the content is represented, so this
            # entry is also safe to drop even though it created nothing new.
          rescue StandardError => e
            kept << entry
            Rails.logger.warn(
              "[ai:drain_dormant_ralph_learnings] loop=#{loop_record.id} entry KEPT (store raised): #{e.class}: #{e.message}"
            )
          end
        end

        loop_record.update_column(:learnings, kept)

        totals[:loops] += 1
        totals[:stored] += stored
        totals[:entries_kept] += kept.size
      end

      totals[:accounts] += 1
    end

    summary = "[ai:drain_dormant_ralph_learnings] accounts=#{totals[:accounts]} loops_drained=#{totals[:loops]} " \
              "learnings_stored=#{totals[:stored]} entries_kept=#{totals[:entries_kept]} loops_skipped=#{totals[:loops_skipped]}"
    Rails.logger.info(summary)
    puts summary

    if stopped_on
      message = "[ai:drain_dormant_ralph_learnings] STOPPED — #{stopped_on}. That account's loops were left " \
                "untouched. Re-run once resolved; the drop-column migration refuses while any row is non-empty."
      Rails.logger.error(message)
      abort(message)
    elsif totals[:entries_kept].positive? || totals[:loops_skipped].positive?
      message = "[ai:drain_dormant_ralph_learnings] INCOMPLETE — #{totals[:entries_kept]} entr" \
                "#{totals[:entries_kept] == 1 ? 'y' : 'ies'} kept after a failed store, " \
                "#{totals[:loops_skipped]} loop(s) skipped for an unrecognized entry shape. Investigate and re-run; " \
                "the drop-column migration refuses while any row is non-empty."
      Rails.logger.error(message)
      abort(message)
    end
  end
end
