# frozen_string_literal: true

module Ai
  class PerformanceBenchmark < ApplicationRecord
    self.table_name = "ai_performance_benchmarks"

    # Associations
    belongs_to :account
    belongs_to :sandbox, class_name: "Ai::Sandbox", optional: true
    belongs_to :target_workflow, class_name: "Ai::Workflow", optional: true
    belongs_to :target_agent, class_name: "Ai::Agent", optional: true
    belongs_to :created_by, class_name: "User", optional: true

    # Validations
    validates :benchmark_id, presence: true, uniqueness: true
    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: %w[active paused archived] }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }
    scope :for_workflow, ->(workflow) { where(target_workflow: workflow) }
    scope :for_agent, ->(agent) { where(target_agent: agent) }
    scope :recent, -> { order(last_run_at: :desc) }

    # Callbacks
    before_validation :set_benchmark_id, on: :create

    # Methods
    def active?
      status == "active"
    end

    def paused?
      status == "paused"
    end

    def target
      target_workflow || target_agent
    end

    def target_type
      return "workflow" if target_workflow.present?
      return "agent" if target_agent.present?

      nil
    end

    def activate!
      update!(status: "active")
    end

    def pause!
      update!(status: "paused")
    end

    def archive!
      update!(status: "archived")
    end

    def record_results!(results)
      increment!(:run_count)

      score = calculate_score(results)
      trend = determine_trend(score)

      update!(
        latest_results: results,
        latest_score: score,
        trend: trend,
        last_run_at: Time.current
      )
    end

    def set_baseline!(metrics)
      update!(baseline_metrics: metrics)
    end

    def meets_thresholds?(results)
      return true if thresholds.blank?

      thresholds.all? do |metric, threshold|
        actual = results[metric]
        next true if actual.nil?

        case threshold
        when Hash
          max = threshold["max"]
          min = threshold["min"]
          (max.nil? || actual <= max) && (min.nil? || actual >= min)
        else
          actual <= threshold
        end
      end
    end

    def threshold_violations(results)
      return [] if thresholds.blank?

      violations = []
      thresholds.each do |metric, threshold|
        actual = results[metric]
        next if actual.nil?

        case threshold
        when Hash
          if threshold["max"] && actual > threshold["max"]
            violations << { metric: metric, actual: actual, threshold: threshold["max"], type: "exceeded_max" }
          end
          if threshold["min"] && actual < threshold["min"]
            violations << { metric: metric, actual: actual, threshold: threshold["min"], type: "below_min" }
          end
        else
          if actual > threshold
            violations << { metric: metric, actual: actual, threshold: threshold, type: "exceeded" }
          end
        end
      end
      violations
    end

    def compare_to_baseline(results)
      return {} if baseline_metrics.blank?

      comparison = {}
      baseline_metrics.each do |metric, baseline_value|
        actual = results[metric]
        next if actual.nil?

        diff = actual - baseline_value
        diff_percent = baseline_value.nonzero? ? (diff / baseline_value * 100).round(2) : 0

        comparison[metric] = {
          baseline: baseline_value,
          actual: actual,
          diff: diff,
          diff_percent: diff_percent,
          improved: diff < 0 # Lower is better for most metrics
        }
      end
      comparison
    end

    private

    def set_benchmark_id
      self.benchmark_id ||= SecureRandom.uuid
    end

    def calculate_score(results)
      return 0 if baseline_metrics.blank?

      scores = []
      baseline_metrics.each do |metric, baseline|
        actual = results[metric]
        next if actual.nil? || baseline.nil? || baseline.zero?

        # Score based on how much better/worse than baseline
        # 100 = same as baseline, >100 = better, <100 = worse
        ratio = baseline / actual.to_f
        scores << (ratio * 100).clamp(0, 200)
      end

      scores.empty? ? 0 : (scores.sum / scores.length).round(1)
    end

    def determine_trend(score)
      return "stable" if latest_score.nil?

      diff = score - latest_score
      return "improving" if diff > 5
      return "degrading" if diff < -5

      "stable"
    end
  end
end
