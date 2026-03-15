# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    identified_by :current_worker

    def connect
      find_verified_identity
    end

    private

    def find_verified_identity
      token = request.params[:token] || extract_token_from_headers

      if token
        begin
          if token.include?(".") # JWT tokens contain dots
            payload = Security::JwtService.decode(token)

            case payload[:type]
            when "worker"
              authenticate_worker(payload)
            when "access"
              authenticate_user(payload)
            else
              Rails.logger.warn "ActionCable: Invalid token type for WebSocket: #{payload[:type]}"
              reject_unauthorized_connection
            end
          else
            authenticate_legacy_user(token)
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

    def authenticate_worker(payload)
      worker = Worker.find(payload[:sub])

      if worker&.active?
        Rails.logger.info "ActionCable: Worker authentication successful for #{worker.name}"
        self.current_worker = worker
      else
        Rails.logger.warn "ActionCable: Worker inactive"
        reject_unauthorized_connection
      end
    end

    def authenticate_user(payload)
      user = User.find(payload[:sub])

      if user&.active? && user.account&.active?
        Rails.logger.info "ActionCable: JWT authentication successful for #{user.email}"
        self.current_user = user
      else
        Rails.logger.warn "ActionCable: User inactive (JWT)"
        reject_unauthorized_connection
      end
    end

    def authenticate_legacy_user(token)
      Rails.logger.warn "[DEPRECATED] UserToken authentication used for ActionCable. Migrate to JWT tokens."
      user_token = UserToken.authenticate(token)

      if user_token&.user&.active?
        user_token.touch_last_used!(
          ip: request.remote_ip,
          user_agent: request.headers["User-Agent"]
        )

        Rails.logger.info "ActionCable: UserToken authentication successful for #{user_token.user.email}"
        self.current_user = user_token.user
      else
        Rails.logger.warn "ActionCable: Invalid UserToken or inactive user"
        reject_unauthorized_connection
      end
    end

    def extract_token_from_headers
      auth_header = request.headers["Authorization"]
      if auth_header&.start_with?("Bearer ")
        auth_header.split(" ").last
      end
    end
  end
end
