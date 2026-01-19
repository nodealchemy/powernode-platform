# frozen_string_literal: true

module Ai
  class TestScenario < ApplicationRecord
    self.table_name = "ai_test_scenarios"

    # Associations
    belongs_to :account
    belongs_to :sandbox, class_name: "Ai::Sandbox"
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :target_workflow, class_name: "Ai::Workflow", optional: true
    belongs_to :target_agent, class_name: "Ai::Agent", optional: true

    has_many :test_results, class_name: "Ai::TestResult", foreign_key: :scenario_id, dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: { scope: :sandbox_id }
    validates :scenario_type, presence: true, inclusion: {
      in: %w[unit integration regression performance security chaos custom]
    }
    validates :status, presence: true, inclusion: { in: %w[draft active disabled archived] }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :draft, -> { where(status: "draft") }
    scope :by_type, ->(type) { where(scenario_type: type) }
    scope :for_workflow, ->(workflow) { where(target_workflow: workflow) }
    scope :for_agent, ->(agent) { where(target_agent: agent) }
    scope :with_tags, ->(tags) { where("tags ?| array[:tags]", tags: tags) }

    # Methods
    def active?
      status == "active"
    end

    def draft?
      status == "draft"
    end

    def activate!
      update!(status: "active")
    end

    def disable!
      update!(status: "disabled")
    end

    def archive!
      update!(status: "archived")
    end

    def can_run?
      active? && (target_workflow.present? || target_agent.present?)
    end

    def target
      target_workflow || target_agent
    end

    def target_type
      return "workflow" if target_workflow.present?
      return "agent" if target_agent.present?

      nil
    end

    def record_run!(passed:)
      increment!(:run_count)
      if passed
        increment!(:pass_count)
      else
        increment!(:fail_count)
      end

      # Update pass rate
      new_pass_rate = run_count > 0 ? (pass_count.to_f / run_count * 100).round(2) : 0
      update!(pass_rate: new_pass_rate, last_run_at: Time.current)
    end

    def evaluate_assertions(actual_output)
      return [] if assertions.blank?

      results = []
      assertions.each_with_index do |assertion, index|
        result = evaluate_assertion(assertion, actual_output)
        results << {
          index: index,
          assertion: assertion,
          passed: result[:passed],
          message: result[:message],
          actual: result[:actual],
          expected: result[:expected]
        }
      end
      results
    end

    def should_retry?(retry_count)
      retry_count < max_retries
    end

    private

    def evaluate_assertion(assertion, actual_output)
      field = assertion["field"]
      operator = assertion["operator"]
      expected = assertion["expected"]

      actual = extract_value(actual_output, field)

      case operator
      when "equals"
        { passed: actual == expected, actual: actual, expected: expected, message: nil }
      when "contains"
        passed = actual.to_s.include?(expected.to_s)
        { passed: passed, actual: actual, expected: expected, message: passed ? nil : "Value does not contain expected" }
      when "matches"
        passed = actual.to_s.match?(Regexp.new(expected.to_s))
        { passed: passed, actual: actual, expected: expected, message: passed ? nil : "Value does not match pattern" }
      when "greater_than"
        { passed: actual.to_f > expected.to_f, actual: actual, expected: expected, message: nil }
      when "less_than"
        { passed: actual.to_f < expected.to_f, actual: actual, expected: expected, message: nil }
      when "exists"
        { passed: !actual.nil?, actual: actual, expected: "exists", message: nil }
      when "not_empty"
        { passed: actual.present?, actual: actual, expected: "not empty", message: nil }
      else
        { passed: false, actual: actual, expected: expected, message: "Unknown operator: #{operator}" }
      end
    end

    def extract_value(data, field)
      return nil if data.blank? || field.blank?

      field.to_s.split(".").reduce(data) do |obj, key|
        break nil if obj.nil?

        if obj.is_a?(Hash)
          obj[key] || obj[key.to_sym]
        elsif obj.is_a?(Array) && key.match?(/^\d+$/)
          obj[key.to_i]
        else
          nil
        end
      end
    end
  end
end
