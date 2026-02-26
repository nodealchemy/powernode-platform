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
          token = request.headers["Authorization"]&.split(" ")&.last
          return render_error("Service authentication required", status: :unauthorized) unless token

          begin
            payload = Security::JwtService.decode(token)
            worker = ::Worker.find_by(id: payload[:sub]) if payload[:type] == "worker"
          rescue StandardError
            worker = nil
          end

          unless worker&.active?
            render_error("Service authentication required", status: :unauthorized)
          end
        end
      end
    end
  end
end
