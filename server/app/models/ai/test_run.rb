# frozen_string_literal: true

module Ai
  class TestRun < ApplicationRecord
    self.table_name = "ai_test_runs"

    # Associations
    belongs_to :account
    belongs_to :sandbox, class_name: "Ai::Sandbox"
    belongs_to :triggered_by, class_name: "User", optional: true

    has_many :test_results, class_name: "Ai::TestResult", foreign_key: :test_run_id, dependent: :destroy

    # Validations
    validates :run_id, presence: true, uniqueness: true
    validates :run_type, presence: true, inclusion: {
      in: %w[manual scheduled ci_triggered regression smoke]
    }
    validates :status, presence: true, inclusion: {
      in: %w[pending running completed failed cancelled timeout]
    }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :by_type, ->(type) { where(run_type: type) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :set_run_id, on: :create

    # Methods
    def pending?
      status == "pending"
    end

    def running?
      status == "running"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def start!
      update!(status: "running", started_at: Time.current)
      sandbox.increment!(:test_runs_count)
    end

    def complete!
      calculate_results
      duration = started_at.present? ? ((Time.current - started_at) * 1000).to_i : nil

      update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: duration
      )
    end

    def fail!(error_summary = {})
      calculate_results
      duration = started_at.present? ? ((Time.current - started_at) * 1000).to_i : nil

      update!(
        status: "failed",
        completed_at: Time.current,
        duration_ms: duration,
        summary: summary.merge(error: error_summary)
      )
    end

    def cancel!
      update!(status: "cancelled", completed_at: Time.current)
    end

    def timeout!
      update!(status: "timeout", completed_at: Time.current)
    end

    def pass_rate
      return 0 if total_scenarios.zero?

      (passed_scenarios.to_f / total_scenarios * 100).round(2)
    end

    def all_passed?
      completed? && failed_scenarios.zero? && skipped_scenarios.zero?
    end

    def add_scenario(scenario)
      self.scenario_ids ||= []
      self.scenario_ids << scenario.id.to_s unless scenario_ids.include?(scenario.id.to_s)
      increment!(:total_scenarios)
      save!
    end

    def record_result(result)
      case result.status
      when "passed"
        increment!(:passed_scenarios)
        increment!(:passed_assertions, result.passed_assertions_count)
      when "failed"
        increment!(:failed_scenarios)
        increment!(:failed_assertions, result.failed_assertions_count)
      when "skipped"
        increment!(:skipped_scenarios)
      end

      increment!(:total_assertions, result.total_assertions_count)
    end

    private

    def set_run_id
      self.run_id ||= SecureRandom.uuid
    end

    def calculate_results
      results = test_results.reload

      update!(
        passed_scenarios: results.passed.count,
        failed_scenarios: results.failed.count,
        skipped_scenarios: results.skipped.count,
        passed_assertions: results.sum { |r| r.passed_assertions_count },
        failed_assertions: results.sum { |r| r.failed_assertions_count },
        total_assertions: results.sum { |r| r.total_assertions_count },
        summary: generate_summary(results)
      )
    end

    def generate_summary(results)
      {
        total_scenarios: total_scenarios,
        passed: passed_scenarios,
        failed: failed_scenarios,
        skipped: skipped_scenarios,
        pass_rate: pass_rate,
        total_duration_ms: results.sum(&:duration_ms),
        total_tokens: results.sum(&:tokens_used),
        total_cost_usd: results.sum(&:cost_usd)
      }
    end
  end
end
