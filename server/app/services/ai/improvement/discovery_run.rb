# frozen_string_literal: true

module Ai
  module Improvement
    # READING the discovery clock's run history.
    #
    # A run is recorded as an `AuditLog` row per account per tick, under the
    # action `ai.improvement_discovery.run`, written by
    # Api::V1::Internal::Ai::ImprovementDiscoveryController. That storage choice
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

      def self.scope_for(account)
        AuditLog.where(action: ACTION, account_id: account.id)
                .order(created_at: :desc, id: :desc)
      end
      private_class_method :scope_for
    end
  end
end
