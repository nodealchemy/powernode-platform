# frozen_string_literal: true

module Api
  module V1
    module Worker
      # Base controller for worker API endpoints
      # Provides service token authentication for worker-to-backend communication
      class WorkerBaseController < ApplicationController
        skip_before_action :authenticate_request
        before_action :authenticate_worker_service!

        private

        def authenticate_worker_service!
          token = request.headers["Authorization"]&.remove("Bearer ")

          unless token.present? && valid_worker_token?(token)
            render_error("Service authentication required", status: :unauthorized)
          end
        end

        def valid_worker_token?(token)
          # Compare with configured worker token
          expected_token = ENV["WORKER_SERVICE_TOKEN"] ||
                           Rails.application.credentials.dig(:worker, :service_token) ||
                           "development_worker_service_token_that_persists_across_restarts"

          return false unless expected_token.present?

          ActiveSupport::SecurityUtils.secure_compare(token, expected_token)
        end
      end
    end
  end
end
