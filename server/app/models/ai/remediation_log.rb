# frozen_string_literal: true

module Ai
  class RemediationLog < ApplicationRecord
    belongs_to :account

    RESULTS = %w[success failure skipped rate_limited].freeze
    ACTION_TYPES = %w[provider_failover workflow_retry alert_escalation].freeze

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
