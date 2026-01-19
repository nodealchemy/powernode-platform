# frozen_string_literal: true

module Ai
  class TestResult < ApplicationRecord
    self.table_name = "ai_test_results"

    # Associations
    belongs_to :test_run, class_name: "Ai::TestRun"
    belongs_to :scenario, class_name: "Ai::TestScenario"

    # Validations
    validates :result_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: %w[passed failed skipped error timeout] }

    # Scopes
    scope :passed, -> { where(status: "passed") }
    scope :failed, -> { where(status: "failed") }
    scope :skipped, -> { where(status: "skipped") }
    scope :errors, -> { where(status: "error") }
    scope :timeouts, -> { where(status: "timeout") }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :set_result_id, on: :create

    # Methods
    def passed?
      status == "passed"
    end

    def failed?
      status == "failed"
    end

    def skipped?
      status == "skipped"
    end

    def error?
      status == "error"
    end

    def timeout?
      status == "timeout"
    end

    def start!
      update!(started_at: Time.current)
    end

    def complete!(status:, actual_output:, assertion_results: [], error_details: {}, metrics: {}, tokens: 0, cost: 0)
      duration = started_at.present? ? ((Time.current - started_at) * 1000).to_i : nil

      update!(
        status: status,
        completed_at: Time.current,
        duration_ms: duration,
        actual_output: actual_output,
        assertion_results: assertion_results,
        error_details: error_details,
        metrics: metrics,
        tokens_used: tokens,
        cost_usd: cost
      )

      # Update scenario statistics
      scenario.record_run!(passed: passed?)

      # Update test run counters
      test_run.record_result(self)
    end

    def passed_assertions_count
      return 0 if assertion_results.blank?

      assertion_results.count { |r| r["passed"] }
    end

    def failed_assertions_count
      return 0 if assertion_results.blank?

      assertion_results.count { |r| !r["passed"] }
    end

    def total_assertions_count
      assertion_results&.length || 0
    end

    def failed_assertion_messages
      return [] if assertion_results.blank?

      assertion_results
        .reject { |r| r["passed"] }
        .map { |r| r["message"] || "Assertion failed" }
    end

    def retry!
      return false unless failed? || error? || timeout?
      return false unless scenario.should_retry?(retry_attempt)

      increment!(:retry_attempt)
      update!(status: "pending", started_at: nil, completed_at: nil)
      true
    end

    private

    def set_result_id
      self.result_id ||= SecureRandom.uuid
    end
  end
end
