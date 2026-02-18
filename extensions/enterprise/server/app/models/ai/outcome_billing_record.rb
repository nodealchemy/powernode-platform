# frozen_string_literal: true

# Outcome Billing Record Model - Individual outcome billing events
#
# Records individual billable outcomes with pricing and SLA tracking.
#
module Ai
  class OutcomeBillingRecord < ApplicationRecord
    self.table_name = "ai_outcome_billing_records"

    # Associations
    belongs_to :account
    belongs_to :outcome_definition, class_name: "Ai::OutcomeDefinition"
    belongs_to :sla_contract, class_name: "Ai::SlaContract", optional: true
    belongs_to :validated_by, class_name: "User", optional: true

    # Validations
    validates :source_type, presence: true
    validates :source_id, presence: true
    validates :status, presence: true, inclusion: {
      in: %w[pending processing successful failed timeout cancelled refunded]
    }

    # Scopes
    scope :for_account, ->(account) { where(account: account) }
    scope :for_definition, ->(definition) { where(outcome_definition: definition) }
    scope :successful, -> { where(status: "successful") }
    scope :failed, -> { where(status: %w[failed timeout]) }
    scope :billable, -> { where(is_billable: true) }
    scope :billed, -> { where(is_billed: true) }
    scope :unbilled, -> { where(is_billable: true, is_billed: false) }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }
    scope :recent, ->(period = 30.days) { where("created_at >= ?", period.ago) }
    scope :ordered_by_time, -> { order(created_at: :desc) }

    # Callbacks
    before_save :calculate_charges, if: :status_changed?
    after_save :update_sla_metrics, if: :saved_change_to_status?

    # Instance methods
    def successful?
      status == "successful"
    end

    def calculate_charges
      return unless outcome_definition
      return unless %w[successful failed timeout].include?(status)

      self.base_charge_usd = outcome_definition.base_price_usd

      if tokens_used && outcome_definition.price_per_token
        self.token_charge_usd = (tokens_used * outcome_definition.price_per_token).round(4)
      end

      if duration_ms && outcome_definition.price_per_minute
        minutes = duration_ms / 60_000.0
        self.time_charge_usd = (minutes * outcome_definition.price_per_minute).round(4)
      end

      subtotal = (base_charge_usd || 0) + (token_charge_usd || 0) + (time_charge_usd || 0)
      self.final_charge_usd = (subtotal - (discount_usd || 0)).round(4)

      # Only charge for successful outcomes (or based on definition settings)
      self.is_billable = successful? && final_charge_usd.positive?
    end

    def update_sla_metrics
      return unless sla_contract
      return unless %w[successful failed timeout].include?(status)

      sla_contract.record_outcome(successful: successful?)
    end

    def mark_as_billed!(invoice_line_item_id: nil)
      update!(
        is_billed: true,
        billed_at: Time.current,
        invoice_line_item_id: invoice_line_item_id
      )
    end

    def refund!
      return false unless is_billed

      update!(
        status: "refunded",
        is_billable: false
      )
    end

    def validate_outcome!(validated_by_user: nil, quality_score: nil)
      update!(
        validated_at: Time.current,
        validated_by: validated_by_user,
        quality_score: quality_score
      )
    end

    def met_quality_threshold?
      return true if outcome_definition.quality_threshold.nil?
      return false if quality_score.nil?

      quality_score >= outcome_definition.quality_threshold
    end

    def summary
      {
        id: id,
        outcome_definition_id: outcome_definition_id,
        outcome_name: outcome_definition.name,
        source_type: source_type,
        source_id: source_id,
        source_name: source_name,
        status: status,
        is_successful: is_successful,
        quality_score: quality_score&.to_f,
        duration_ms: duration_ms,
        tokens_used: tokens_used,
        charges: {
          base_usd: base_charge_usd&.to_f,
          token_usd: token_charge_usd&.to_f,
          time_usd: time_charge_usd&.to_f,
          discount_usd: discount_usd&.to_f,
          final_usd: final_charge_usd&.to_f
        },
        is_billable: is_billable,
        is_billed: is_billed,
        billed_at: billed_at,
        sla_contract_id: sla_contract_id,
        counted_for_sla: counted_for_sla,
        started_at: started_at,
        completed_at: completed_at,
        created_at: created_at
      }
    end
  end
end
