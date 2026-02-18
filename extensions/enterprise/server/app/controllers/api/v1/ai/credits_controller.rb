# frozen_string_literal: true

module Api
  module V1
    module Ai
      # Credits Controller - Manage AI credit operations
      #
      # Handles credit balance, purchases, transfers, and usage.
      #
      class CreditsController < ApplicationController
        # GET /api/v1/ai/credits/balance
        def balance
          result = credit_service.get_balance
          render_success(result)
        end

        # GET /api/v1/ai/credits/transactions
        def transactions
          result = credit_service.get_transaction_history(
            limit: params[:limit]&.to_i || 50,
            offset: params[:offset]&.to_i || 0,
            transaction_type: params[:transaction_type]
          )
          render_success(result)
        end

        # GET /api/v1/ai/credits/packs
        def packs
          result = credit_service.get_available_packs
          render_success(packs: result)
        end

        # POST /api/v1/ai/credits/purchases
        def create_purchase
          result = credit_service.initiate_purchase(
            pack_id: params[:pack_id],
            quantity: params[:quantity]&.to_i || 1,
            payment_method: params[:payment_method],
            user: current_user
          )

          if result
            render_success(result, status: :created)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/credits/purchases/:id/complete
        def complete_purchase
          result = credit_service.complete_purchase(
            purchase_id: params[:id],
            payment_reference: params[:payment_reference]
          )

          if result
            render_success(result)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/credits/transfers
        def create_transfer
          to_account = Account.find_by(id: params[:to_account_id])

          unless to_account
            render_error("Destination account not found", status: :not_found)
            return
          end

          result = credit_service.initiate_transfer(
            to_account: to_account,
            amount: params[:amount].to_f,
            description: params[:description],
            user: current_user
          )

          if result
            render_success(result, status: :created)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/credits/transfers/:id/approve
        def approve_transfer
          result = credit_service.approve_transfer(
            transfer_id: params[:id],
            user: current_user
          )

          if result
            render_success(result)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/credits/transfers/:id/complete
        def complete_transfer
          result = credit_service.complete_transfer(transfer_id: params[:id])

          if result
            render_success(result)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/credits/transfers/:id/cancel
        def cancel_transfer
          result = credit_service.cancel_transfer(
            transfer_id: params[:id],
            reason: params[:reason]
          )

          if result
            render_success(result)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/credits/deduct
        def deduct
          result = credit_service.deduct_credits(
            amount: params[:amount].to_f,
            operation_type: params[:operation_type],
            reference: params[:reference],
            description: params[:description],
            metadata: params[:metadata] || {}
          )

          if result
            render_success(result)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/credits/calculate_cost
        def calculate_cost
          result = credit_service.calculate_operation_cost(
            operation_type: params[:operation_type],
            provider_type: params[:provider_type],
            model_name: params[:model_name],
            metrics: params[:metrics]&.to_unsafe_h || {}
          )

          if result
            render_success(result)
          else
            render_error("No rate found for this operation", status: :not_found)
          end
        end

        # GET /api/v1/ai/credits/usage_analytics
        def usage_analytics
          period = (params[:period_days]&.to_i || 30).days
          result = credit_service.get_usage_analytics(period: period)
          render_success(result)
        end

        # POST /api/v1/ai/credits/enable_reseller
        def enable_reseller
          result = credit_service.enable_reseller(
            discount_percentage: params[:discount_percentage]&.to_f || 15
          )

          if result
            render_success(result)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/credits/reseller_stats
        def reseller_stats
          result = credit_service.get_reseller_stats

          if result
            render_success(result)
          else
            render_error(credit_service.errors.join(", "), status: :unprocessable_content)
          end
        end

        private

        def credit_service
          @credit_service ||= ::Ai::CreditManagementService.new(current_account)
        end
      end
    end
  end
end
