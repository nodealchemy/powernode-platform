# frozen_string_literal: true

module Ai
  module Improvement
    # READING the discovery clock's run history.
    #
    # A run is recorded as an `AuditLog` row under the action
    # `ai.improvement_discovery.run`: one per account per tick for the dispatch
    # (written by Api::V1::Internal::Ai::ImprovementDiscoveryController), and
    # one per repository result the executor hands back (written by .record!).
    # The `phase` key says which. That storage choice
    # is deliberate — see the lane report — but it must not leak into every
    # caller as a hand-rolled `AuditLog.where(action: "...")`. An ad-hoc query
    # is not the tool: each copy would have to re-derive the action name, the
    # ordering and the account scope, and each copy is somewhere the shape can
    # drift.
    #
    # So "when did discovery last run for this account, and why did it decline"
    # is ONE call.
    module DiscoveryRun
      ACTION = "ai.improvement_discovery.run"

      # The most recent run for an account, or nil when discovery has never run
      # for it. Nil is a real answer and callers must handle it: it means "no
      # tick has been recorded", which is NOT the same as "ran and found
      # nothing".
      def self.last_for(account)
        return nil if account.blank?

        scope_for(account).first
      end

      # The most recent runs, newest first.
      def self.recent(account, limit: 10)
        return AuditLog.none if account.blank?

        scope_for(account).limit(limit)
      end

      # The summary a run recorded: per-linter statuses, counts, the skip
      # reason, the environment it resolved. Empty hash when nothing has run.
      def self.last_summary_for(account)
        last_for(account)&.metadata || {}
      end

      # THE ONE WRITER for a run record that no internal request carries: the
      # executor hands a repository's result back through
      # `DiscoveryRunService#ingest!`, which records it here. Never raises: the
      # offers are already filed by the time this runs, and a lost record is
      # logged rather than turned into a failed ingest.
      def self.record!(account:, summary:)
        AuditLog.create!(
          account_id: account.id,
          user_id: nil,
          action: ACTION,
          resource_type: "Account",
          resource_id: account.id,
          metadata: summary.merge(account_id: account.id, timestamp: Time.current.iso8601)
        )
      rescue StandardError => e
        Rails.logger.error("[ImprovementDiscovery] failed to record run for account #{account.id}: #{e.class}")
        nil
      end

      def self.scope_for(account)
        AuditLog.where(action: ACTION, account_id: account.id)
                .order(created_at: :desc, id: :desc)
      end
      private_class_method :scope_for
    end
  end
end
