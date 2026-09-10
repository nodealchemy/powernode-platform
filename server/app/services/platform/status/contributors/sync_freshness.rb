# frozen_string_literal: true

module Platform
  module Status
    module Contributors
      # THE `Fresh` CONDITION for sources that sync themselves on an interval.
      #
      # A `connected` docker host that has not been heard from in an hour is not
      # connected — it is a row nobody has corrected. The status column alone
      # cannot say so, because nothing writes "disconnected" until a sync
      # actually fails, and a sync that never runs never fails. Freshness is the
      # condition that catches the gap between "last known good" and "known".
      #
      # Two contributors need exactly this (`docker_host`, `kubernetes_cluster`)
      # and both carry the same two columns, so the rule lives here once. A
      # second copy is a second thing to keep in step with the multiplier.
      #
      # ── THE MULTIPLIER ──────────────────────────────────────────────────────
      # Stale after TWICE the record's own `sync_interval_seconds`, matching the
      # staleness convention the rest of this plane uses. Two, not one: a single
      # missed pass is normal (a lock held, a deploy, a slow upstream) and must
      # not turn a healthy fleet amber every minute.
      #
      # The window is derived from the RECORD's interval, never a constant, so a
      # host configured to sync every 10 minutes is not called stale at 2
      # minutes.
      #
      # ── WHY AUTO-SYNC OFF PRODUCES NO CLAIM AT ALL ──────────────────────────
      # With `auto_sync` false nobody is syncing, by an operator's choice. A
      # `Fresh` condition would then be either a permanent false alarm (`stale`,
      # forever, for a thing working as configured) or permanent blindness
      # (`unknown`, which ranks ABOVE `held` on the ladder and would count every
      # deliberately manual host as a gap in the rollup). So the contributor
      # makes NO freshness claim, which is the honest position: we are not
      # measuring it, because nothing was supposed to.
      #
      # This module is NOT a contributor and carries no `KIND`;
      # Contributors.register_all! skips it for exactly that reason.
      module SyncFreshness
        FRESH_TYPE = "Fresh"

        REASON_FRESH        = "SyncFresh"
        REASON_STALE        = "SyncStale"
        REASON_NEVER_SYNCED = "NeverSynced"

        STALE_AFTER_INTERVALS = 2

        # @param record [#last_synced_at, #sync_interval_seconds, #auto_sync]
        # @return [Hash, nil] the condition, or nil when no claim is warranted
        def sync_freshness_condition(record, now: Time.current)
          return nil unless record.auto_sync?

          interval = record.sync_interval_seconds.to_i
          stale_after = interval * STALE_AFTER_INTERVALS
          last_synced_at = record.last_synced_at

          evidence = {
            "last_synced_at" => last_synced_at&.iso8601,
            "sync_interval_seconds" => interval,
            "stale_after_seconds" => stale_after,
            "auto_sync" => true
          }.compact

          return never_synced_condition(evidence, now) if last_synced_at.blank?

          age = (now - last_synced_at).to_i
          fresh = age <= stale_after

          Condition.build(
            type: FRESH_TYPE,
            status: fresh,
            reason: fresh ? REASON_FRESH : REASON_STALE,
            message: "last synced #{age}s ago; stale after #{stale_after}s",
            evidence: evidence.merge("age_seconds" => age),
            observed_at: last_synced_at,
            now: now
          )
        end

        private

        # Auto-sync is ON and nothing has ever synced. That is a gap, not a
        # pass and not a failure: `unknown` renders as `not_measured`, which is
        # exactly what "we have never heard from it" means.
        def never_synced_condition(evidence, now)
          Condition.build(
            type: FRESH_TYPE,
            status: Condition::UNKNOWN,
            reason: REASON_NEVER_SYNCED,
            message: "auto-sync is on but no sync has ever completed",
            evidence: evidence,
            now: now
          )
        end
      end
    end
  end
end
