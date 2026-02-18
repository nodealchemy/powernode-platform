# frozen_string_literal: true

# SLA Contract Model - Account-specific SLA agreements
#
# Manages SLA contracts with success rate targets and credit guarantees.
#
module Ai
  class SlaContract < ApplicationRecord
    self.table_name = "ai_sla_contracts"

    # Associations
    belongs_to :account
    belongs_to :outcome_definition, class_name: "Ai::OutcomeDefinition", optional: true
    has_many :violations, class_name: "Ai::SlaViolation", dependent: :destroy
    has_many :billing_records, class_name: "Ai::OutcomeBillingRecord", dependent: :nullify

    # Validations
    validates :name, presence: true, length: { maximum: 100 }
    validates :contract_type, presence: true, inclusion: {
      in: %w[standard premium enterprise custom]
    }
    validates :status, presence: true, inclusion: {
      in: %w[draft pending_approval active suspended expired cancelled]
    }
    validates :success_rate_target, presence: true, numericality: {
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    }
    validates :breach_credit_percentage, presence: true, numericality: {
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    }
    validates :measurement_window_hours, presence: true, numericality: { greater_than: 0 }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :for_account, ->(account) { where(account: account) }
    scope :expiring_soon, ->(within = 30.days) {
      where("expires_at IS NOT NULL AND expires_at <= ?", within.from_now)
        .where(status: "active")
    }
    scope :needs_measurement, -> {
      where("current_period_end <= ?", Time.current)
        .where(status: "active")
    }

    # Instance methods
    def active?
      status == "active" && (expires_at.nil? || expires_at > Time.current)
    end

    def record_outcome(successful:)
      increment!(:current_period_total)
      increment!(:current_period_successful) if successful

      update_success_rate!
      check_for_breach!
    end

    def update_success_rate!
      return if current_period_total.zero?

      rate = (current_period_successful.to_f / current_period_total * 100).round(4)
      update!(current_success_rate: rate)
    end

    def check_for_breach!
      return unless current_success_rate && success_rate_target
      return if current_period_breached

      if current_success_rate < success_rate_target
        update!(current_period_breached: true)
        create_violation!
      end
    end

    def create_violation!
      violations.create!(
        account: account,
        violation_type: "success_rate",
        severity: calculate_severity,
        period_start: current_period_start,
        period_end: current_period_end || Time.current,
        target_value: success_rate_target,
        actual_value: current_success_rate,
        deviation_percentage: (success_rate_target - current_success_rate).round(4),
        affected_outcomes_count: current_period_total,
        credit_percentage: calculate_credit_percentage,
        credit_amount_usd: calculate_credit_amount
      )
    end

    def calculate_severity
      deviation = success_rate_target - (current_success_rate || 0)
      return "critical" if deviation >= 10
      return "major" if deviation >= 5
      "minor"
    end

    def calculate_credit_percentage
      [ breach_credit_percentage, max_monthly_credit_percentage ].compact.min
    end

    def calculate_credit_amount
      return 0 unless monthly_commitment_usd

      (monthly_commitment_usd * calculate_credit_percentage / 100).round(2)
    end

    def reset_period!
      update!(
        current_period_start: Time.current,
        current_period_end: measurement_window_hours.hours.from_now,
        current_period_total: 0,
        current_period_successful: 0,
        current_success_rate: nil,
        current_period_breached: false
      )
    end

    def activate!
      return false unless %w[draft pending_approval].include?(status)

      update!(
        status: "active",
        activated_at: Time.current,
        current_period_start: Time.current,
        current_period_end: measurement_window_hours.hours.from_now
      )
    end

    def suspend!(reason: nil)
      update!(status: "suspended")
    end

    def cancel!
      update!(
        status: "cancelled",
        cancelled_at: Time.current
      )
    end

    def summary
      {
        id: id,
        name: name,
        contract_type: contract_type,
        status: status,
        targets: {
          success_rate: success_rate_target.to_f,
          latency_p95_ms: latency_p95_target_ms&.to_f,
          availability: availability_target&.to_f
        },
        pricing: {
          monthly_commitment_usd: monthly_commitment_usd&.to_f,
          price_multiplier: price_multiplier&.to_f,
          breach_credit_percentage: breach_credit_percentage.to_f
        },
        current_period: {
          start: current_period_start,
          end: current_period_end,
          total: current_period_total,
          successful: current_period_successful,
          success_rate: current_success_rate&.to_f,
          breached: current_period_breached
        },
        measurement_window_hours: measurement_window_hours,
        activated_at: activated_at,
        expires_at: expires_at
      }
    end
  end
end
