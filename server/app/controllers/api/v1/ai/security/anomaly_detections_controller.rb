# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Security
        class AnomalyDetectionsController < ApplicationController
          before_action :validate_permissions

          # POST /api/v1/ai/security/anomaly_detection/analyze
          def analyze
            agent = current_account.ai_agents.find(params[:agent_id])
            result = service.analyze_agent(
              agent: agent,
              window_minutes: params[:window_minutes]&.to_i || 60
            )

            render_success(data: result)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Agent")
          rescue StandardError => e
            Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/anomaly_detection/check_action
          def check_action
            agent = current_account.ai_agents.find(params[:agent_id])
            result = service.check_action(
              agent: agent,
              action_type: params[:action_type],
              action_context: params[:action_context]&.to_unsafe_h || {}
            )

            render_success(data: result)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Agent")
          rescue StandardError => e
            Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/anomaly_detection/detect_injection
          def detect_injection
            result = service.detect_prompt_injection(
              text: params[:content],
              context: params[:context]&.to_unsafe_h || {}
            )

            render_success(data: result)
          rescue StandardError => e
            Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/anomaly_detection/detect_rogue
          def detect_rogue
            agent = current_account.ai_agents.find(params[:agent_id])
            result = service.detect_rogue_behavior(agent: agent)

            render_success(data: result)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Agent")
          rescue StandardError => e
            Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/security/anomaly_detection/report
          def report
            result = service.security_report

            render_success(data: result)
          rescue StandardError => e
            Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
            render_error(e.message, status: :unprocessable_content)
          end

          private

          def validate_permissions
            return if current_worker

            require_permission("ai.security.manage")
          end

          def service
            @service ||= ::Ai::Security::AgentAnomalyDetectionService.new(account: current_account)
          end
        end
      end
    end
  end
end
