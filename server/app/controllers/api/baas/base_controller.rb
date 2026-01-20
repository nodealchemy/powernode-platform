# frozen_string_literal: true

module Api
  module BaaS
    class BaseController < ActionController::API
      include ActionController::MimeResponds

      before_action :authenticate_baas_request!
      before_action :set_tenant

      attr_reader :current_tenant, :current_api_key

      protected

      def authenticate_baas_request!
        api_key = extract_api_key
        result = ::BaaS::ApiKeyService.authenticate(api_key)

        unless result[:success]
          render_error(result[:error], status: :unauthorized)
          return
        end

        @current_tenant = result[:tenant]
        @current_api_key = result[:api_key]
      end

      def set_tenant
        # Already set by authenticate_baas_request!
      end

      def require_scope(scope)
        unless ::BaaS::ApiKeyService.authorize(current_api_key, scope)
          render_error("Insufficient permissions", status: :forbidden)
        end
      end

      def render_success(data = nil, message: nil, status: :ok, meta: nil)
        response = { success: true }
        response[:data] = data if data
        response[:message] = message if message
        response[:meta] = meta if meta
        render json: response, status: status
      end

      def render_error(message, status: :unprocessable_entity, errors: nil)
        response = {
          success: false,
          error: message
        }
        response[:errors] = errors if errors
        render json: response, status: status
      end

      private

      def extract_api_key
        # Check Authorization header first
        auth_header = request.headers["Authorization"]
        if auth_header&.start_with?("Bearer ")
          return auth_header.sub("Bearer ", "")
        end

        # Check X-API-Key header
        request.headers["X-API-Key"]
      end
    end
  end
end
