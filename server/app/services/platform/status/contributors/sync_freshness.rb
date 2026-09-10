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
        REASON_NO_INTERVAL  = "NoSyncInterval"

        STALE_AFTER_INTERVALS = 2

        # @param record [#last_synced_at, #sync_interval_seconds, #auto_sync]
        # @return [Hash, nil] the condition, or nil when no claim is warranted
        def sync_freshness_condition(record, now: Time.current)
          return nil unless auto_sync?(record)

          interval = record.sync_interval_seconds.to_i
          stale_after = interval * STALE_AFTER_INTERVALS
          last_synced_at = record.last_synced_at

          evidence = {
            "last_synced_at" => last_synced_at&.iso8601,
            "sync_interval_seconds" => interval,
            "stale_after_seconds" => stale_after,
            "auto_sync" => true
          }.compact

          return no_interval_condition(evidence, now) if stale_after <= 0
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

        # `auto_sync` IS NULL IS NOT `auto_sync` IS FALSE.
        #
        # `devops_docker_hosts.auto_sync` is `default: true` and NULLABLE with
        # no model validation, so a row written by a backfill or a raw insert
        # can hold NULL. `record.auto_sync?` answers false for it, which would
        # make the contributor skip the freshness check on a host nobody is
        # syncing — a failure that is BLIND rather than loud: the host simply
        # looks fine.
        #
        # The deliberate operator choice this module declines to second-guess
        # is `auto_sync == false`. NULL is not that choice; it is an absent
        # value, and the value an absent one takes is the COLUMN DEFAULT. Read
        # from the column rather than hardcoded, so a schema change to the
        # default cannot leave this reading a stale constant.
        # (`devops_kubernetes_clusters.auto_sync` is `null: false` and never
        # reaches this branch.)
        def auto_sync?(record)
          value = record.auto_sync
          return value unless value.nil?

          record.class.column_defaults["auto_sync"] != false
        end

        # Auto-sync is ON and the cadence is missing or non-positive, so there
        # is no window to measure freshness against.
        #
        # `unknown`, NOT stale. `nil.to_i` is 0 and `age <= 0` is false for any
        # positive age, so treating a missing interval as a window would make
        # the record permanently `SyncStale` — permanently degraded for a
        # reason no operator can act on, which is precisely the "permanent
        # false alarm" this module refuses to manufacture for the auto-sync-off
        # case.
        #
        # And NOT a guessed cadence either. `Devops::DockerHost` validates the
        # interval between 30 and 3600 without `allow_nil`, so a missing one is
        # only reachable through `update_column` or raw SQL: it is a data
        # defect, and substituting 60 seconds for it could call a host stale
        # that was legitimately on a half-hour cadence somebody wiped. The
        # honest answer to a defect is "we cannot measure this", which is what
        # `unknown` means.
        def no_interval_condition(evidence, now)
          Condition.build(
            type: FRESH_TYPE,
            status: Condition::UNKNOWN,
            reason: REASON_NO_INTERVAL,
            message: "auto-sync is on but no sync interval is configured",
            evidence: evidence,
            now: now
          )
        end

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
