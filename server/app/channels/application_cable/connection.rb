# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      # Extract token from query parameters or headers
      token = request.params[:token] || extract_token_from_headers

      if token
        begin
          # Use UserToken authentication instead of JWT
          user_token = UserToken.authenticate(token)
          
          if user_token&.user&.active?
            # Update token usage tracking
            user_token.touch_last_used!(
              ip: request.remote_ip,
              user_agent: request.headers['User-Agent']
            )
            
            Rails.logger.info "ActionCable: Authentication successful for #{user_token.user.email}"
            user_token.user
          else
            Rails.logger.warn "ActionCable: Invalid token or inactive user"
            reject_unauthorized_connection
          end
        rescue StandardError => e
          Rails.logger.error "ActionCable authentication failed: #{e.message}"
          reject_unauthorized_connection
        end
      else
        Rails.logger.warn "ActionCable: No token provided"
        reject_unauthorized_connection
      end
    end

    def extract_token_from_headers
      # Check Authorization header
      auth_header = request.headers["Authorization"]
      if auth_header&.start_with?("Bearer ")
        auth_header.split(" ").last
      end
    end
  end
end
