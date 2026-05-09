# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    identified_by :current_worker

    def connect
      find_verified_identity
      transmit_minted_tokens!
    end

    private

    def find_verified_identity
      token = request.params[:token] || extract_token_from_headers
      refresh_param = request.params[:refresh_token]

      if token
        begin
          if token.include?(".") # JWT tokens contain dots
            payload = decode_or_refresh(token, refresh_param)
            return if payload.nil?

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
      elsif refresh_param.present?
        # Standalone-refresh path: no live access token (e.g. tab suspended
        # past access TTL but refresh is still valid). Mint a fresh access
        # from the refresh and authenticate against that — collapses HTTP
        # /auth/refresh + WS reconnect into a single round-trip.
        begin
          authenticate_via_refresh!(refresh_param)
        rescue StandardError => e
          Rails.logger.warn "ActionCable: refresh-only auth failed: #{e.message}"
          reject_unauthorized_connection
        end
      else
        Rails.logger.warn "ActionCable: No token provided"
        reject_unauthorized_connection
      end
    end

    # Decode the access token. If decode raises with an "expired" message AND
    # a refresh token was supplied alongside it, mint a fresh access token,
    # stash it for post-connect transmit, and return the *new* access payload
    # so the rest of the auth flow runs against a fresh subject.
    def decode_or_refresh(access_token, refresh_token)
      Security::JwtService.decode(access_token)
    rescue StandardError => e
      message = e.message.to_s
      expired = message.match?(/expired/i)
      raise(e) unless expired && refresh_token.present?

      tokens = Security::JwtService.refresh_access_token(refresh_token)
      @minted_tokens = tokens
      Security::JwtService.decode(tokens[:access_token])
    end

    def authenticate_via_refresh!(refresh_token)
      tokens = Security::JwtService.refresh_access_token(refresh_token)
      @minted_tokens = tokens
      payload = Security::JwtService.decode(tokens[:access_token])
      authenticate_user(payload)
    end

    # Push the freshly-minted tokens to the client over the live cable so
    # the frontend can swap them into auth state without a separate HTTP
    # /auth/refresh round-trip.
    #
    # In tests, ActionCable's TestConnection module skips initializing
    # `@coder` (Rails 8.x: actioncable's test_case.rb), so transmit would
    # raise NoMethodError. Production code always has both — guard the
    # call so the test surface stays clean while keeping the production
    # behavior identical.
    def transmit_minted_tokens!
      return unless @minted_tokens
      return unless instance_variable_defined?(:@coder) && @coder

      transmit(
        type: "auth_refreshed",
        access_token: @minted_tokens[:access_token],
        refresh_token: @minted_tokens[:refresh_token],
        expires_at: @minted_tokens[:expires_at],
        refresh_expires_at: @minted_tokens[:refresh_expires_at]
      )
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
