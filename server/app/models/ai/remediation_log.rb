# frozen_string_literal: true

module Ai
  class RemediationLog < ApplicationRecord
    belongs_to :account

    RESULTS = %w[success failure skipped rate_limited].freeze

    # Every action_type any producer may write. This list is a SUPERSET by design
    # — workflow_retry has no production producer today — so the guard on it is
    # containment, not equality.
    #
    # It is enumerated here but produced elsewhere, which is exactly how
    # model_downgrade and context_trim came to execute against live agents with
    # no audit row at all: they were added to the dispatcher and the list did not
    # move, so every log write for them failed the inclusion validation below and
    # was swallowed by log_remediation's rescue. The mechanical link that was
    # missing now lives in
    # spec/services/ai/self_healing/remediation_audit_coverage_spec.rb, which
    # derives the produced set from the producers' own source and reflection:
    # RemediationDispatcher's execute_* methods, #determine_action, and
    # PredictiveMonitorService#determine_preemptive_action (the action_hint path).
    ACTION_TYPES = %w[
      provider_failover
      workflow_retry
      alert_escalation
      model_downgrade
      context_trim
    ].freeze

    validates :trigger_source, presence: true
    validates :trigger_event, presence: true
    validates :action_type, presence: true, inclusion: { in: ACTION_TYPES }
    validates :result, presence: true, inclusion: { in: RESULTS }
    validates :executed_at, presence: true

    scope :recent, ->(limit = 50) { order(executed_at: :desc).limit(limit) }
    scope :successful, -> { where(result: "success") }
    scope :failed, -> { where(result: "failure") }
    scope :by_action_type, ->(type) { where(action_type: type) }
    scope :in_last_hour, -> { where("executed_at >= ?", 1.hour.ago) }
    scope :by_account, ->(account_id) { where(account_id: account_id) }

    def self.hourly_count(account_id)
      by_account(account_id).in_last_hour.count
    end
  end
end
