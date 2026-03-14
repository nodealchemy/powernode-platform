# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Intelligence
        class ReviewsController < ApplicationController
          before_action :validate_permissions

          # POST /api/v1/ai/intelligence/reviews/sentiment_analysis
          def sentiment_analysis
            result = service.sentiment_analysis(review_id: params[:review_id])

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/reviews/spam_detection
          def spam_detection
            result = service.spam_detection

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/intelligence/reviews/generate_response
          def generate_response
            result = service.generate_response(review_id: params[:review_id])

            if result[:success]
              render_success(data: result)
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # GET /api/v1/ai/intelligence/reviews/agent_quality
          def agent_quality
            result = service.agent_quality_assessment

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
            @service ||= ::Ai::Intelligence::ReviewIntelligenceService.new(account: current_account)
          end
        end
      end
    end
  end
end
