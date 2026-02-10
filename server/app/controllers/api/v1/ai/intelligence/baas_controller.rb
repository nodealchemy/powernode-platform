# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Intelligence
        class BaasController < ApplicationController
          before_action :validate_permissions

          # GET /api/v1/ai/intelligence/baas/usage_anomalies
          def usage_anomalies
            result = service.usage_anomalies(tenant_id: params[:tenant_id])

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/baas/tenant_churn
          def tenant_churn
            result = service.tenant_churn_prediction

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/baas/pricing_recommendations
          def pricing_recommendations
            result = service.pricing_recommendations

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/baas/api_fraud
          def api_fraud
            result = service.api_fraud_detection

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          private

          def validate_permissions
            return if current_worker || current_service

            require_permission("ai.intelligence.view")
          end

          def service
            @service ||= ::Ai::Intelligence::PlatformIntelligenceService.new(account: current_account)
          end
        end
      end
    end
  end
end
