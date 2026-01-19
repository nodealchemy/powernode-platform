# frozen_string_literal: true

# Outcome Billing Service - Success-based billing operations
#
# Handles all outcome billing operations:
# - Outcome definition management
# - SLA contract management
# - Billing record creation
# - SLA violation tracking
# - Credit application
#
module Ai
  class OutcomeBillingService
    attr_reader :account, :errors

    def initialize(account)
      @account = account
      @errors = []
    end

    # ==========================================================================
    # OUTCOME DEFINITIONS
    # ==========================================================================

    def list_definitions(outcome_type: nil, is_active: nil, limit: 50, offset: 0)
      scope = Ai::OutcomeDefinition
        .where(account: account)
        .or(Ai::OutcomeDefinition.where(is_system: true))
        .order(created_at: :desc)
        .offset(offset)
        .limit(limit)

      scope = scope.where(outcome_type: outcome_type) if outcome_type.present?
      scope = scope.where(is_active: is_active) unless is_active.nil?

      {
        definitions: scope.map(&:summary),
        total_count: scope.except(:limit, :offset).count,
        limit: limit,
        offset: offset
      }
    end

    def get_definition(definition_id)
      definition = find_definition(definition_id)
      return nil unless definition

      definition.summary.merge(
        billing_records_count: definition.billing_records.count,
        success_rate: calculate_definition_success_rate(definition),
        total_revenue: definition.billing_records.successful.billable.sum(:final_charge_usd).to_f
      )
    end

    def create_definition(params)
      definition = Ai::OutcomeDefinition.create!(
        account: account,
        name: params[:name],
        description: params[:description],
        outcome_type: params[:outcome_type],
        category: params[:category],
        validation_method: params[:validation_method] || "automatic",
        success_criteria: params[:success_criteria] || {},
        base_price_usd: params[:base_price_usd],
        price_per_token: params[:price_per_token],
        price_per_minute: params[:price_per_minute],
        min_charge_usd: params[:min_charge_usd],
        max_charge_usd: params[:max_charge_usd],
        quality_threshold: params[:quality_threshold],
        volume_tiers: params[:volume_tiers] || [],
        free_tier_count: params[:free_tier_count] || 0,
        sla_enabled: params[:sla_enabled] || false,
        sla_target_percentage: params[:sla_target_percentage],
        sla_credit_percentage: params[:sla_credit_percentage],
        is_active: true
      )

      definition.summary
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def update_definition(definition_id, params)
      definition = find_definition(definition_id)
      return nil unless definition

      definition.update!(params.slice(
        :name, :description, :category, :validation_method, :success_criteria,
        :base_price_usd, :price_per_token, :price_per_minute, :min_charge_usd,
        :max_charge_usd, :quality_threshold, :volume_tiers, :free_tier_count,
        :sla_enabled, :sla_target_percentage, :sla_credit_percentage, :is_active
      ))

      definition.reload.summary
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    # ==========================================================================
    # SLA CONTRACTS
    # ==========================================================================

    def list_contracts(status: nil, limit: 50, offset: 0)
      scope = Ai::SlaContract
        .where(account: account)
        .order(created_at: :desc)
        .offset(offset)
        .limit(limit)

      scope = scope.where(status: status) if status.present?

      {
        contracts: scope.map(&:summary),
        total_count: scope.except(:limit, :offset).count,
        limit: limit,
        offset: offset
      }
    end

    def get_contract(contract_id)
      contract = find_contract(contract_id)
      return nil unless contract

      contract.summary.merge(
        violations_count: contract.violations.count,
        total_credits_applied: contract.violations.applied.sum(:credit_amount_usd).to_f,
        recent_violations: contract.violations.recent(30.days).map(&:summary)
      )
    end

    def create_contract(params)
      contract = Ai::SlaContract.create!(
        account: account,
        outcome_definition_id: params[:outcome_definition_id],
        name: params[:name],
        contract_type: params[:contract_type] || "standard",
        success_rate_target: params[:success_rate_target],
        latency_p95_target_ms: params[:latency_p95_target_ms],
        availability_target: params[:availability_target],
        breach_credit_percentage: params[:breach_credit_percentage],
        max_monthly_credit_percentage: params[:max_monthly_credit_percentage] || 30,
        monthly_commitment_usd: params[:monthly_commitment_usd],
        price_multiplier: params[:price_multiplier] || 1.0,
        measurement_window_hours: params[:measurement_window_hours] || 720, # 30 days
        status: "draft"
      )

      contract.summary
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def activate_contract(contract_id)
      contract = find_contract(contract_id)
      return nil unless contract

      unless %w[draft pending_approval].include?(contract.status)
        @errors << "Contract cannot be activated from #{contract.status} status"
        return nil
      end

      contract.activate!
      contract.reload.summary
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def suspend_contract(contract_id, reason: nil)
      contract = find_contract(contract_id)
      return nil unless contract

      contract.suspend!(reason: reason)
      contract.reload.summary
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def cancel_contract(contract_id)
      contract = find_contract(contract_id)
      return nil unless contract

      contract.cancel!
      contract.reload.summary
    rescue StandardError => e
      @errors << e.message
      nil
    end

    # ==========================================================================
    # BILLING RECORDS
    # ==========================================================================

    def record_outcome(params)
      definition = Ai::OutcomeDefinition.find(params[:outcome_definition_id])

      record = Ai::OutcomeBillingRecord.create!(
        account: account,
        outcome_definition: definition,
        sla_contract_id: params[:sla_contract_id],
        source_type: params[:source_type],
        source_id: params[:source_id],
        source_name: params[:source_name],
        status: params[:status] || "pending",
        is_successful: params[:is_successful],
        quality_score: params[:quality_score],
        duration_ms: params[:duration_ms],
        tokens_used: params[:tokens_used],
        started_at: params[:started_at],
        completed_at: params[:completed_at],
        metadata: params[:metadata] || {}
      )

      record.summary
    rescue ActiveRecord::RecordNotFound
      @errors << "Outcome definition not found"
      nil
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def complete_outcome(record_id, params)
      record = Ai::OutcomeBillingRecord.find_by(id: record_id, account: account)

      unless record
        @errors << "Billing record not found"
        return nil
      end

      record.update!(
        status: params[:status],
        is_successful: params[:is_successful],
        quality_score: params[:quality_score],
        completed_at: Time.current
      )

      record.reload.summary
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.message
      nil
    end

    def get_billing_records(params = {})
      scope = Ai::OutcomeBillingRecord
        .where(account: account)
        .order(created_at: :desc)
        .offset(params[:offset] || 0)
        .limit(params[:limit] || 50)

      scope = scope.where(outcome_definition_id: params[:definition_id]) if params[:definition_id]
      scope = scope.where(status: params[:status]) if params[:status]
      scope = scope.where(source_type: params[:source_type]) if params[:source_type]
      scope = scope.billable if params[:billable_only]
      scope = scope.unbilled if params[:unbilled_only]

      {
        records: scope.map(&:summary),
        total_count: scope.except(:limit, :offset).count,
        limit: params[:limit] || 50,
        offset: params[:offset] || 0
      }
    end

    def mark_as_billed(record_ids, invoice_line_item_id: nil)
      records = Ai::OutcomeBillingRecord.where(id: record_ids, account: account)

      updated = records.update_all(
        is_billed: true,
        billed_at: Time.current,
        invoice_line_item_id: invoice_line_item_id
      )

      { updated_count: updated, record_ids: record_ids }
    end

    # ==========================================================================
    # SLA VIOLATIONS
    # ==========================================================================

    def get_violations(params = {})
      scope = Ai::SlaViolation
        .where(account: account)
        .order(created_at: :desc)
        .offset(params[:offset] || 0)
        .limit(params[:limit] || 50)

      scope = scope.where(sla_contract_id: params[:contract_id]) if params[:contract_id]
      scope = scope.where(credit_status: params[:credit_status]) if params[:credit_status]
      scope = scope.where(violation_type: params[:violation_type]) if params[:violation_type]

      {
        violations: scope.map(&:summary),
        total_count: scope.except(:limit, :offset).count,
        limit: params[:limit] || 50,
        offset: params[:offset] || 0
      }
    end

    def approve_violation_credit(violation_id)
      violation = find_violation(violation_id)
      return nil unless violation

      violation.approve!
      violation.reload.summary
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def apply_violation_credit(violation_id)
      violation = find_violation(violation_id)
      return nil unless violation

      violation.apply_credit!
      violation.reload.summary
    rescue StandardError => e
      @errors << e.message
      nil
    end

    def reject_violation_credit(violation_id, reason: nil)
      violation = find_violation(violation_id)
      return nil unless violation

      violation.reject!(reason: reason)
      violation.reload.summary
    rescue StandardError => e
      @errors << e.message
      nil
    end

    # ==========================================================================
    # ANALYTICS
    # ==========================================================================

    def get_billing_summary(period: 30.days)
      records = Ai::OutcomeBillingRecord
        .where(account: account)
        .where("created_at >= ?", period.ago)

      successful = records.successful
      failed = records.failed

      {
        period_days: period.to_i / 86400,
        total_outcomes: records.count,
        successful_outcomes: successful.count,
        failed_outcomes: failed.count,
        success_rate: records.count.positive? ? (successful.count.to_f / records.count * 100).round(2) : 0,
        total_revenue: records.billable.billed.sum(:final_charge_usd).to_f,
        pending_revenue: records.billable.unbilled.sum(:final_charge_usd).to_f,
        average_duration_ms: records.where.not(duration_ms: nil).average(:duration_ms).to_f.round(2),
        average_quality_score: records.where.not(quality_score: nil).average(:quality_score).to_f.round(4)
      }
    end

    def get_sla_performance(period: 30.days)
      contracts = Ai::SlaContract.where(account: account, status: "active")

      {
        active_contracts: contracts.count,
        contracts_summary: contracts.map do |contract|
          {
            id: contract.id,
            name: contract.name,
            success_rate_target: contract.success_rate_target.to_f,
            current_success_rate: contract.current_success_rate&.to_f,
            is_meeting_sla: contract.current_success_rate.to_f >= contract.success_rate_target,
            violations_count: contract.violations.where("created_at >= ?", period.ago).count,
            credits_applied: contract.violations.where("created_at >= ?", period.ago).applied.sum(:credit_amount_usd).to_f
          }
        end,
        total_violations: Ai::SlaViolation.where(account: account).where("created_at >= ?", period.ago).count,
        total_credits_applied: Ai::SlaViolation.where(account: account).where("created_at >= ?", period.ago).applied.sum(:credit_amount_usd).to_f
      }
    end

    private

    def find_definition(definition_id)
      definition = Ai::OutcomeDefinition.find_by(id: definition_id)
      unless definition && (definition.account_id == account.id || definition.is_system?)
        @errors << "Outcome definition not found"
        return nil
      end
      definition
    end

    def find_contract(contract_id)
      contract = Ai::SlaContract.find_by(id: contract_id, account: account)
      unless contract
        @errors << "SLA contract not found"
        return nil
      end
      contract
    end

    def find_violation(violation_id)
      violation = Ai::SlaViolation.find_by(id: violation_id, account: account)
      unless violation
        @errors << "Violation not found"
        return nil
      end
      violation
    end

    def calculate_definition_success_rate(definition)
      total = definition.billing_records.count
      return 0 if total.zero?

      successful = definition.billing_records.successful.count
      (successful.to_f / total * 100).round(2)
    end
  end
end
