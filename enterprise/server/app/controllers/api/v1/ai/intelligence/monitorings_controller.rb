# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Intelligence
        class MonitoringsController < ApplicationController
          include EnterpriseFeatureGate
          require_enterprise_feature "intelligence"
          before_action :validate_permissions

          # GET /api/v1/ai/intelligence/monitoring/predictive_failure
          def predictive_failure
            result = service.predictive_failure(service_name: params[:service_name])

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/monitoring/self_healing
          def self_healing
            result = service.self_healing_recommendations

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/monitoring/sla_breach_risk
          def sla_breach_risk
            result = service.sla_breach_risk

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
            @service ||= ::Ai::Intelligence::OpsIntelligenceService.new(account: current_account)
          end
        end
      end
    end
  end
end
