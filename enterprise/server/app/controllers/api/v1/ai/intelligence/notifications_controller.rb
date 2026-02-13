# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Intelligence
        class NotificationsController < ApplicationController
          include EnterpriseFeatureGate
          require_enterprise_feature "intelligence"
          before_action :validate_permissions

          # POST /api/v1/ai/intelligence/notifications/smart_routing
          def smart_routing
            result = service.smart_routing(notification_id: params[:notification_id])

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/notifications/fatigue_analysis
          def fatigue_analysis
            result = service.fatigue_analysis(user_id: params[:user_id])

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/notifications/digest_recommendations
          def digest_recommendations
            result = service.digest_recommendations

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
