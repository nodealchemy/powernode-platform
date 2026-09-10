# frozen_string_literal: true

module Platform
  module Status
    # THE SWEEP (design §4.5). Walks every registered contributor, turns each
    # component into conditions, derives a verdict, and upserts one row.
    #
    # IT READS, IT DOES NOT PROBE. Every fact it writes was already maintained
    # by a sensor, a snapshot or a model column. A sweep that opened sockets
    # would be a fleet-wide load generator on a 60-second cron, and its
    # failure modes would be indistinguishable from the failures it is
    # supposed to report.
    #
    # `run_once!(account)` is deliberately callable with no cron, no worker
    # and no Redis, so this increment's oracle is executable before the job
    # exists (A2). A2 wraps it with the kill-switch and standby-fence guards
    # and the worker route; NOTHING here emits events or broadcasts — the
    # transitions are RETURNED, and A2 is the single producer that turns them
    # into `Platform::StatusEvent` rows and `PlatformStatusChannel` messages.
    # One producer, always.
    #
    # ── A RAISING CONTRIBUTOR NEVER TAKES DOWN THE SWEEP ────────────────────
    # It marks its own components `not_measured` with `reason: ContributorError`
    # and the exception class in evidence, and every other kind still runs. The
    # alternative — one bad contributor blanking the whole screen — is exactly
    # the failure this plane exists to make visible.
    #
    # ── THE REAP ARM ────────────────────────────────────────────────────────
    # A component whose record is gone must not keep a verdict forever. A row
    # not seen for THREE sweeps is deleted. Three, not one, because a single
    # missed pass (a lock held, a deploy, a transient contributor error) is
    # normal and must not delete history.
    #
    # The same age rule reaps rows of a kind that is no longer REGISTERED, for
    # free: nothing refreshes them, so they age out. Deleting unregistered
    # kinds immediately would be a boot-order hazard instead — an extension
    # that registers late would find its rows deleted by whichever sweep ran
    # first.
    class SweepService
      # No hardcoded cadence: the interval is configuration, and the reap
      # threshold is derived from it so the two can never disagree.
      SWEEP_INTERVAL_SETTING = "platform.status.sweep_interval_seconds"
      DEFAULT_SWEEP_INTERVAL_SECONDS = 60
      REAP_AFTER_SWEEPS = 3

      CONTRIBUTOR_ERROR_REASON = "ContributorError"

      class << self
        def run_once!(account, now: Time.current)
          new(account: account, now: now).run_once!
        end

        # Seconds between sweeps, from SiteSetting, defaulting to
        # DEFAULT_SWEEP_INTERVAL_SECONDS. A blank or non-positive setting is
        # the default, not a division by zero.
        def sweep_interval_seconds
          configured = ::SiteSetting.get(SWEEP_INTERVAL_SETTING)
          configured.present? && configured.to_i.positive? ? configured.to_i : DEFAULT_SWEEP_INTERVAL_SECONDS
        end

        def reap_after_seconds
          sweep_interval_seconds * REAP_AFTER_SWEEPS
        end
      end

      def initialize(account:, now: Time.current)
        @account = account
        @now = now
        @summary = {}
        @transitions = []
      end

      def run_once!
        Registry.contributors.each { |kind, contributor| sweep_kind(kind, contributor) }

        {
          account_id: @account&.id,
          swept_at: @now,
          kinds: @summary,
          transitions: @transitions,
          reaped: reap!
        }
      end

      private

      # One kind. Enumeration and per-record work are rescued separately
      # because they fail differently: a broken enumeration yields no refs at
      # all (so there is nothing to key a row on but the wildcard), while a
      # broken single record must not hide its healthy siblings.
      def sweep_kind(kind, contributor)
        tally = { count: 0, transitions: 0, errors: 0 }
        @summary[kind] = tally

        account_id = contributor_account_id(contributor)
        existing = existing_rows(kind, account_id)

        begin
          contributor.each_component(@account) do |record|
            ref = safe_ref(contributor, record)
            next tally[:errors] += 1 if ref.blank?

            upsert_component(kind, contributor, record, ref, account_id, existing[ref], tally)
          end
        rescue StandardError => e
          # The ENUMERATION itself failed: there are no refs, so the failure
          # lands on one wildcard row rather than vanishing.
          tally[:errors] += 1
          Rails.logger.error("[Platform::Status] kind=#{kind} enumeration failed: #{e.class}: #{e.message}")
          write_contributor_error(kind, contributor, ComponentStatus::WILDCARD_REF, account_id,
                                  existing[ComponentStatus::WILDCARD_REF], e, tally)
          return tally
        end

        # A clean enumeration means the wildcard row (if any) is stale the
        # moment it stops being written; the reap arm removes it on schedule
        # like any other row.
        tally
      end

      def upsert_component(kind, contributor, record, ref, account_id, row, tally)
        conditions = build_conditions(contributor, record, row)
        write_row(kind, contributor, record, ref, account_id, row, conditions, tally)
      rescue StandardError => e
        tally[:errors] += 1
        Rails.logger.error("[Platform::Status] kind=#{kind} ref=#{ref} failed: #{e.class}: #{e.message}")
        write_contributor_error(kind, contributor, ref, account_id, row, e, tally)
      end

      def build_conditions(contributor, record, row)
        previous = Condition.index_by_type(row&.conditions)
        Array(contributor.conditions_for(record)).map do |condition|
          rebuild_with_transition(condition, previous)
        end
      end

      # A contributor builds its conditions without knowing what was stored
      # last pass, so the transition timestamp is resolved HERE, against the
      # previously stored condition of the same type. Rebuilding through
      # Condition.build also re-validates the tokens, so a contributor cannot
      # sneak a lowercase reason in by hand-rolling the hash.
      def rebuild_with_transition(condition, previous_by_type)
        attrs = condition.transform_keys(&:to_s)
        type = attrs["type"]

        Condition.build(
          type: type,
          status: attrs["status"],
          reason: attrs["reason"],
          message: attrs["message"],
          severity: attrs["severity"],
          evidence: attrs["evidence"],
          observed_generation: attrs["observed_generation"],
          observed_at: attrs["observed_at"],
          previous: previous_by_type[type.to_s],
          now: @now
        )
      end

      def write_row(kind, contributor, record, ref, account_id, row, conditions, tally)
        row ||= ComponentStatus.new(account_id: account_id, component_kind: kind, component_ref: ref)
        previous_verdict = row.persisted? ? row.verdict : nil
        verdict = Condition.verdict_for_set(conditions)

        row.assign_attributes(
          environment_id: contributor.try(:environment_id_for, record),
          display_name: contributor.display_name_for(record).to_s.presence,
          verdict: verdict,
          observed_generation: contributor.try(:observed_generation_for, record)&.to_s,
          presentation: contributor.presentation || {},
          links: Array(contributor.links_for(record)),
          actions: Array(contributor.try(:actions_for, record)),
          conditions: conditions,
          dependencies: Array(contributor.dependencies_for(record)),
          observed_at: contributor.try(:observed_at_for, record) || @now,
          last_seen_sweep_at: @now
        )
        row.save!

        tally[:count] += 1
        record_transition(row, previous_verdict, verdict, tally)
        row
      end

      # A row whose contributor blew up: `not_measured`, the reason token the
      # composite probe already uses, and the exception class as evidence. The
      # PREVIOUS verdict is not preserved — reporting a stale `ok` because we
      # failed to look would be the exact lie this plane exists to prevent.
      def write_contributor_error(kind, contributor, ref, account_id, row, error, tally)
        condition = Condition.build(
          type: "Observed",
          status: Condition::UNKNOWN,
          reason: CONTRIBUTOR_ERROR_REASON,
          message: "#{error.class}: #{error.message}",
          evidence: { "exception_class" => error.class.name },
          previous: Condition.index_by_type(row&.conditions)["Observed"],
          now: @now
        )

        row ||= ComponentStatus.new(account_id: account_id, component_kind: kind, component_ref: ref)
        previous_verdict = row.persisted? ? row.verdict : nil

        row.assign_attributes(
          display_name: row.display_name.presence || safe_display_name(contributor, ref),
          verdict: ComponentStatus::NOT_MEASURED,
          conditions: [ condition ],
          observed_at: @now,
          last_seen_sweep_at: @now
        )
        row.presentation = contributor.presentation if row.presentation.blank? && contributor.respond_to?(:presentation)
        row.save!

        record_transition(row, previous_verdict, ComponentStatus::NOT_MEASURED, tally)
        row
      rescue StandardError => e
        # Even the error path must not abort the other kinds.
        Rails.logger.error("[Platform::Status] kind=#{kind} could not record contributor error: #{e.class}: #{e.message}")
        nil
      end

      def record_transition(row, previous_verdict, verdict, tally)
        return if previous_verdict == verdict

        tally[:transitions] += 1
        @transitions << {
          component_status_id: row.id,
          account_id: row.account_id,
          component_kind: row.component_kind,
          component_ref: row.component_ref,
          from: previous_verdict,
          to: verdict,
          at: @now
        }
      end

      # Scoped to the rows this run is responsible for: this account's rows and
      # the shared (null-account) rows every run re-sweeps. A global reap would
      # delete another account's rows just because nobody swept that account.
      def reap!
        cutoff = @now - self.class.reap_after_seconds.seconds
        scope = ComponentStatus.where(account_id: [ @account&.id, nil ].uniq).not_seen_since(cutoff)
        scope.delete_all
      end

      def existing_rows(kind, account_id)
        ComponentStatus.where(account_id: account_id, component_kind: kind).index_by(&:component_ref)
      end

      # A shared kind's rows carry a NULL account, which is why the column is
      # nullable and the unique index is NULLS NOT DISTINCT.
      def contributor_account_id(contributor)
        return nil unless contributor.respond_to?(:account_scoped?) ? contributor.account_scoped? : true

        @account&.id
      end

      def safe_ref(contributor, record)
        contributor.ref_for(record).to_s.presence
      rescue StandardError => e
        Rails.logger.error("[Platform::Status] ref_for failed: #{e.class}: #{e.message}")
        nil
      end

      def safe_display_name(contributor, ref)
        contributor.respond_to?(:kind) ? "#{contributor.kind} #{ref}" : ref
      rescue StandardError
        ref
      end
    end
  end
end
