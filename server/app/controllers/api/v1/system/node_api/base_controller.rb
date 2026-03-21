# frozen_string_literal: true

module Api
  module V1
    module System
      module NodeApi
        # Base controller for Node API endpoints
        # Handles instance-token authentication for node instance self-service
        # Instances use JWT token via X-Instance-Token header or Authorization Bearer
        class BaseController < ApplicationController
          # Skip default authenticate_request and use instance-specific auth
          skip_before_action :authenticate_request
          before_action :authenticate_instance!

          private

          # Authenticate instance via JWT token
          def authenticate_instance!
            token = extract_instance_token_from_request
            return render_unauthorized("Instance token required") unless token

            begin
              payload = JwtService.decode(token)

              unless payload[:type] == "instance"
                return render_unauthorized("Invalid token type")
              end

              @current_instance = ::System::NodeInstance.find(payload[:sub])

              unless @current_instance.active?
                return render_unauthorized("Instance is not active")
              end
            rescue StandardError => e
              return render_unauthorized("Invalid instance token: #{e.message}")
            rescue ActiveRecord::RecordNotFound
              return render_unauthorized("Instance not found")
            end
          end

          # Extract token from X-Instance-Token header or Authorization Bearer
          def extract_instance_token_from_request
            # Prefer X-Instance-Token header
            token = request.headers["X-Instance-Token"]
            return token if token.present?

            # Fallback to Authorization header
            auth_header = request.headers["Authorization"]
            return nil unless auth_header&.start_with?("Bearer ")

            auth_header.split(" ", 2).last
          end

          # Access current instance
          attr_reader :current_instance

          # Get node from current instance
          def current_node
            @current_node ||= current_instance.node
          end

          # Get account from current instance
          def current_account
            @current_account ||= current_node.account
          end

          # Get template from current node
          def current_template
            @current_template ||= current_node.node_template
          end

          # Standard error handler for record not found
          def render_record_not_found(resource_type)
            render_not_found(resource_type)
          end
        end
      end
    end
  end
end
