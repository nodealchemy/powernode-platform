# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Outcome Billing Controller - Success-based AI billing
      #
      # Handles outcome definitions, SLA contracts, billing records, and violations.
      #
      class OutcomeBillingController < ApplicationController
        before_action :authenticate_user!

        # ==========================================================================
        # OUTCOME DEFINITIONS
        # ==========================================================================

        # GET /api/v1/ai/outcome_billing/definitions
        def definitions
          result = billing_service.list_definitions(
            outcome_type: params[:outcome_type],
            is_active: params[:is_active] == "true" ? true : (params[:is_active] == "false" ? false : nil),
            limit: params[:limit]&.to_i || 50,
            offset: params[:offset]&.to_i || 0
          )
          render_success(result)
        end

        # GET /api/v1/ai/outcome_billing/definitions/:id
        def show_definition
          result = billing_service.get_definition(params[:id])

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :not_found)
          end
        end

        # POST /api/v1/ai/outcome_billing/definitions
        def create_definition
          result = billing_service.create_definition(definition_params)

          if result
            render_success(result, status: :created)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH /api/v1/ai/outcome_billing/definitions/:id
        def update_definition
          result = billing_service.update_definition(params[:id], definition_params)

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # ==========================================================================
        # SLA CONTRACTS
        # ==========================================================================

        # GET /api/v1/ai/outcome_billing/contracts
        def contracts
          result = billing_service.list_contracts(
            status: params[:status],
            limit: params[:limit]&.to_i || 50,
            offset: params[:offset]&.to_i || 0
          )
          render_success(result)
        end

        # GET /api/v1/ai/outcome_billing/contracts/:id
        def show_contract
          result = billing_service.get_contract(params[:id])

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :not_found)
          end
        end

        # POST /api/v1/ai/outcome_billing/contracts
        def create_contract
          result = billing_service.create_contract(contract_params)

          if result
            render_success(result, status: :created)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/outcome_billing/contracts/:id/activate
        def activate_contract
          result = billing_service.activate_contract(params[:id])

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/outcome_billing/contracts/:id/suspend
        def suspend_contract
          result = billing_service.suspend_contract(params[:id], reason: params[:reason])

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/outcome_billing/contracts/:id/cancel
        def cancel_contract
          result = billing_service.cancel_contract(params[:id])

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # ==========================================================================
        # BILLING RECORDS
        # ==========================================================================

        # GET /api/v1/ai/outcome_billing/records
        def records
          result = billing_service.get_billing_records(
            definition_id: params[:definition_id],
            status: params[:status],
            source_type: params[:source_type],
            billable_only: params[:billable_only] == "true",
            unbilled_only: params[:unbilled_only] == "true",
            limit: params[:limit]&.to_i || 50,
            offset: params[:offset]&.to_i || 0
          )
          render_success(result)
        end

        # POST /api/v1/ai/outcome_billing/records
        def create_record
          result = billing_service.record_outcome(record_params)

          if result
            render_success(result, status: :created)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH /api/v1/ai/outcome_billing/records/:id/complete
        def complete_record
          result = billing_service.complete_outcome(params[:id], complete_params)

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/outcome_billing/records/mark_billed
        def mark_billed
          record_ids = params[:record_ids]

          unless record_ids.is_a?(Array) && record_ids.any?
            render_error("record_ids must be a non-empty array", status: :bad_request)
            return
          end

          result = billing_service.mark_as_billed(
            record_ids,
            invoice_line_item_id: params[:invoice_line_item_id]
          )
          render_success(result)
        end

        # ==========================================================================
        # SLA VIOLATIONS
        # ==========================================================================

        # GET /api/v1/ai/outcome_billing/violations
        def violations
          result = billing_service.get_violations(
            contract_id: params[:contract_id],
            credit_status: params[:credit_status],
            violation_type: params[:violation_type],
            limit: params[:limit]&.to_i || 50,
            offset: params[:offset]&.to_i || 0
          )
          render_success(result)
        end

        # POST /api/v1/ai/outcome_billing/violations/:id/approve
        def approve_violation
          result = billing_service.approve_violation_credit(params[:id])

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/outcome_billing/violations/:id/apply
        def apply_violation
          result = billing_service.apply_violation_credit(params[:id])

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/outcome_billing/violations/:id/reject
        def reject_violation
          result = billing_service.reject_violation_credit(params[:id], reason: params[:reason])

          if result
            render_success(result)
          else
            render_error(billing_service.errors.join(", "), status: :unprocessable_entity)
          end
        end

        # ==========================================================================
        # ANALYTICS
        # ==========================================================================

        # GET /api/v1/ai/outcome_billing/summary
        def summary
          period = (params[:period_days]&.to_i || 30).days
          result = billing_service.get_billing_summary(period: period)
          render_success(result)
        end

        # GET /api/v1/ai/outcome_billing/sla_performance
        def sla_performance
          period = (params[:period_days]&.to_i || 30).days
          result = billing_service.get_sla_performance(period: period)
          render_success(result)
        end

        private

        def billing_service
          @billing_service ||= ::Ai::OutcomeBillingService.new(current_account)
        end

        def definition_params
          params.permit(
            :name, :description, :outcome_type, :category, :validation_method,
            :base_price_usd, :price_per_token, :price_per_minute,
            :min_charge_usd, :max_charge_usd, :quality_threshold,
            :free_tier_count, :sla_enabled, :sla_target_percentage, :sla_credit_percentage,
            success_criteria: {}, volume_tiers: []
          )
        end

        def contract_params
          params.permit(
            :outcome_definition_id, :name, :contract_type,
            :success_rate_target, :latency_p95_target_ms, :availability_target,
            :breach_credit_percentage, :max_monthly_credit_percentage,
            :monthly_commitment_usd, :price_multiplier, :measurement_window_hours
          )
        end

        def record_params
          params.permit(
            :outcome_definition_id, :sla_contract_id, :source_type, :source_id,
            :source_name, :status, :is_successful, :quality_score,
            :duration_ms, :tokens_used, :started_at, :completed_at,
            metadata: {}
          )
        end

        def complete_params
          params.permit(:status, :is_successful, :quality_score)
        end
      end
    end
  end
end
