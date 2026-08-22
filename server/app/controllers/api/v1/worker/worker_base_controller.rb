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

        attr_reader :current_worker

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
            return render_error("Service authentication required", status: :unauthorized)
          end

          @current_worker = worker
          # Signature-checked bearer token — unforgeable, so record it as such
          # (see Authentication#worker_identity_cryptographically_verified?).
          @current_worker_auth = :jwt
        end

        # Scope an account-owned relation to the authenticated worker's account.
        #
        # System workers (is_system: true) process all accounts' work by design,
        # so they receive the relation unconstrained. Account workers
        # (is_system: false) are constrained to their own account, preventing
        # cross-account reads/mutations through the worker API.
        def account_scoped(relation)
          return relation if current_worker&.system?

          relation.where(account: current_worker&.account)
        end
      end
    end
  end
end
