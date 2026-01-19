# frozen_string_literal: true

module Ai
  class DeploymentRisk < ApplicationRecord
    self.table_name = "ai_deployment_risks"

    # Associations
    belongs_to :account
    belongs_to :pipeline_execution, class_name: "Ai::PipelineExecution", optional: true
    belongs_to :assessed_by, class_name: "User", optional: true

    # Validations
    validates :assessment_id, presence: true, uniqueness: true
    validates :deployment_type, presence: true
    validates :target_environment, presence: true
    validates :risk_level, presence: true, inclusion: { in: %w[low medium high critical] }
    validates :status, presence: true, inclusion: { in: %w[pending assessed approved rejected overridden] }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :assessed, -> { where(status: "assessed") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :high_risk, -> { where(risk_level: %w[high critical]) }
    scope :by_environment, ->(env) { where(target_environment: env) }
    scope :requiring_approval, -> { where(requires_approval: true) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :set_assessment_id, on: :create

    # Methods
    def pending?
      status == "pending"
    end

    def assessed?
      status == "assessed"
    end

    def approved?
      status == "approved"
    end

    def rejected?
      status == "rejected"
    end

    def high_risk?
      %w[high critical].include?(risk_level)
    end

    def critical?
      risk_level == "critical"
    end

    def assess!(risk_factors:, change_analysis: {}, impact_analysis: {}, recommendations: [], mitigations: [])
      calculated_score = calculate_risk_score(risk_factors)
      calculated_level = determine_risk_level(calculated_score)

      update!(
        status: "assessed",
        risk_score: calculated_score,
        risk_level: calculated_level,
        risk_factors: risk_factors,
        change_analysis: change_analysis,
        impact_analysis: impact_analysis,
        recommendations: recommendations,
        mitigations: mitigations,
        assessed_at: Time.current,
        requires_approval: calculated_level.in?(%w[high critical])
      )
    end

    def approve!(user:, rationale: nil)
      update!(
        status: "approved",
        decision: "proceed",
        decision_rationale: rationale,
        assessed_by: user,
        decision_at: Time.current
      )
    end

    def reject!(user:, rationale: nil)
      update!(
        status: "rejected",
        decision: "abort",
        decision_rationale: rationale,
        assessed_by: user,
        decision_at: Time.current
      )
    end

    def override!(user:, rationale:)
      update!(
        status: "overridden",
        decision: "proceed_with_caution",
        decision_rationale: rationale,
        assessed_by: user,
        decision_at: Time.current
      )
    end

    def delay!(user:, rationale: nil)
      update!(
        status: "rejected",
        decision: "delay",
        decision_rationale: rationale,
        assessed_by: user,
        decision_at: Time.current
      )
    end

    private

    def set_assessment_id
      self.assessment_id ||= SecureRandom.uuid
    end

    def calculate_risk_score(factors)
      return 0 if factors.blank?

      # Weighted risk scoring
      weights = {
        "code_complexity" => 0.15,
        "test_coverage" => 0.15,
        "deployment_frequency" => 0.10,
        "rollback_capability" => 0.15,
        "dependencies_changed" => 0.10,
        "security_vulnerabilities" => 0.20,
        "performance_impact" => 0.15
      }

      total_score = 0
      total_weight = 0

      factors.each do |factor|
        name = factor["name"]
        score = factor["score"].to_f
        weight = weights[name] || 0.1

        total_score += score * weight
        total_weight += weight
      end

      return 0 if total_weight.zero?

      (total_score / total_weight * 100).round
    end

    def determine_risk_level(score)
      case score
      when 0..25 then "low"
      when 26..50 then "medium"
      when 51..75 then "high"
      else "critical"
      end
    end
  end
end
