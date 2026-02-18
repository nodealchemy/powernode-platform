# frozen_string_literal: true

# SLA Violation Model - Track SLA breaches for credit calculation
#
# Records SLA violations and manages credit issuance.
#
module Ai
  class SlaViolation < ApplicationRecord
    self.table_name = "ai_sla_violations"

    # Associations
    belongs_to :account
    belongs_to :sla_contract, class_name: "Ai::SlaContract"

    # Validations
    validates :violation_type, presence: true, inclusion: {
      in: %w[success_rate latency availability quality]
    }
    validates :severity, presence: true, inclusion: {
      in: %w[minor major critical]
    }
    validates :period_start, presence: true
    validates :period_end, presence: true
    validates :target_value, presence: true, numericality: true
    validates :actual_value, presence: true, numericality: true
    validates :credit_percentage, presence: true, numericality: {
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    }
    validates :credit_amount_usd, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :credit_status, presence: true, inclusion: {
      in: %w[pending approved applied rejected waived]
    }

    # Scopes
    scope :for_account, ->(account) { where(account: account) }
    scope :for_contract, ->(contract) { where(sla_contract: contract) }
    scope :pending_credit, -> { where(credit_status: "pending") }
    scope :approved, -> { where(credit_status: "approved") }
    scope :applied, -> { where(credit_status: "applied") }
    scope :by_type, ->(type) { where(violation_type: type) }
    scope :by_severity, ->(severity) { where(severity: severity) }
    scope :recent, ->(period = 90.days) { where("created_at >= ?", period.ago) }
    scope :ordered_by_time, -> { order(created_at: :desc) }

    # Instance methods
    def approve!
      return false unless credit_status == "pending"

      update!(credit_status: "approved")
    end

    def apply_credit!
      return false unless credit_status == "approved"

      transaction do
        # Add credit to account
        account_credit = account.ai_account_credits.first_or_create!
        account_credit.add_credits(
          credit_amount_usd,
          transaction_type: "refund",
          description: "SLA violation credit: #{violation_type}",
          metadata: {
            sla_violation_id: id,
            sla_contract_id: sla_contract_id,
            period_start: period_start,
            period_end: period_end
          }
        )

        update!(
          credit_status: "applied",
          credit_applied_at: Time.current
        )

        true
      end
    rescue ActiveRecord::RecordInvalid
      false
    end

    def reject!(reason: nil)
      return false unless credit_status == "pending"

      update!(
        credit_status: "rejected",
        description: reason || description
      )
    end

    def waive!(reason: nil)
      return false unless %w[pending approved].include?(credit_status)

      update!(
        credit_status: "waived",
        description: reason || description
      )
    end

    def deviation_severity_color
      case severity
      when "critical" then "red"
      when "major" then "orange"
      else "yellow"
      end
    end

    def summary
      {
        id: id,
        sla_contract_id: sla_contract_id,
        contract_name: sla_contract.name,
        violation_type: violation_type,
        severity: severity,
        period: {
          start: period_start,
          end: period_end
        },
        metrics: {
          target: target_value.to_f,
          actual: actual_value.to_f,
          deviation_percentage: deviation_percentage&.to_f,
          affected_outcomes: affected_outcomes_count
        },
        credit: {
          percentage: credit_percentage.to_f,
          amount_usd: credit_amount_usd.to_f,
          status: credit_status,
          applied_at: credit_applied_at
        },
        description: description,
        created_at: created_at
      }
    end
  end
end
