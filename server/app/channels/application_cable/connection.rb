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
          decoded_token = JwtService.decode(token)
          user = User.find(decoded_token["user_id"])
          
          if user&.active?
            user
          else
            reject_unauthorized_connection
          end
        rescue JWT::DecodeError, ActiveRecord::RecordNotFound => e
          Rails.logger.error "ActionCable authentication failed: #{e.message}"
          reject_unauthorized_connection
        end
      else
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