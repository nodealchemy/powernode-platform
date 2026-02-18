# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Intelligence
        class PipelinesController < ApplicationController
          include EnterpriseFeatureGate
          require_enterprise_feature "intelligence"
          before_action :validate_permissions

          # POST /api/v1/ai/intelligence/pipeline/analyze_failure
          def analyze_failure
            result = service.analyze_failure(
              pipeline_run_id: params[:pipeline_run_id]
            )

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/pipeline/health
          def health
            result = service.health_check

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/pipeline/trends
          def trends
            result = service.failure_trends(
              period_days: params[:days]&.to_i || 30
            )

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
            @service ||= ::Ai::Intelligence::PipelineIntelligenceService.new(account: current_account)
          end
        end
      end
    end
  end
end
