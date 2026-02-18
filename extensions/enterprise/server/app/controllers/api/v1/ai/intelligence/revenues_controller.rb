# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Intelligence
        class RevenuesController < ApplicationController
          include EnterpriseFeatureGate
          require_enterprise_feature "intelligence"
          before_action :validate_permissions

          # GET /api/v1/ai/intelligence/revenue/forecast
          def forecast
            result = service.forecast_accuracy_analysis

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/revenue/churn_risks
          def churn_risks
            result = service.churn_risk_report

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/revenue/health_scores
          def health_scores
            result = service.health_score_distribution

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          private

          def validate_permissions
            return if current_worker || current_service

            require_permission("ai.intelligence.view")
          end

          def service
            @service ||= ::Ai::Intelligence::RevenueIntelligenceService.new(account: current_account)
          end
        end
      end
    end
  end
end
