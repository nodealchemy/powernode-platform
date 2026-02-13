# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Intelligence
        class ResellersController < ApplicationController
          include EnterpriseFeatureGate
          require_enterprise_feature "intelligence"
          before_action :validate_permissions

          # GET /api/v1/ai/intelligence/reseller/performance_scores
          def performance_scores
            result = service.performance_scores

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/reseller/commission_optimization
          def commission_optimization
            result = service.commission_optimization

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/reseller/referral_churn_risks
          def referral_churn_risks
            result = service.referral_churn_risks

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
