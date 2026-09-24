# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    identified_by :current_worker
    # Set only for an impersonation-JWT connection — see #authenticate_impersonation.
    # `identified_by` (not a plain attr_accessor) so Channel instances get it
    # delegated automatically (delegate_connection_identifiers), consistent
    # with current_user/current_worker.
    identified_by :impersonator

    def connect
      find_verified_identity
      transmit_minted_tokens!
    end

    private

    def find_verified_identity
      # mTLS arm — workers connect to the /cable router on the
      # websecure-mtls Traefik entrypoint (:443) and present their
      # client cert via WorkerCertManager. Traefik forwards the verified
      # subject CN (= NodeInstance.id) via X-Forwarded-Tls-Client-Cert-Info.
      # Resolve the worker from there and short-circuit before the
      # user-JWT arm.
      if authenticate_worker_via_mtls
        return
      end

      token = request.params[:token] || extract_token_from_headers
      refresh_param = request.params[:refresh_token]

      if token
        begin
          if token.include?(".") # JWT tokens contain dots
            payload = decode_or_refresh(token, refresh_param)
            return if payload.nil?

            case payload[:type]
            when "access"
              authenticate_user(payload)
            when "impersonation"
              authenticate_impersonation(payload)
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

    # Returns truthy if an active worker was identified from the
    # Traefik-forwarded mTLS subject CN; false when no header is present
    # (user-JWT arm takes over) or the CN can't be resolved to an active
    # Worker (connection is rejected immediately to avoid the JWT arm
    # producing a misleading downstream error).
    def authenticate_worker_via_mtls
      # No client cert at all → user-JWT arm takes over (browsers have none).
      return false unless Security::MtlsTrust.client_cert_presented?(request)

      # A cert IS present → it must verify against OUR CA (Federation mTLS
      # Phase 2: peer CAs share the Traefik bundle, so a peer-CA-signed cert
      # must not impersonate a worker here). On any failure, reject — a forged
      # cert must not get a second chance via the JWT arm.
      cn = Security::MtlsTrust.verify_request(request)
      if cn.blank?
        Rails.logger.warn "ActionCable: client cert present but not verified against our CA; rejecting"
        reject_unauthorized_connection
        return true
      end

      worker = Worker.find_by(node_instance_id: cn)
      if worker&.active?
        Rails.logger.info "ActionCable: mTLS authentication successful for worker #{worker.name}"
        self.current_worker = worker
        true
      else
        Rails.logger.warn "ActionCable: mTLS cert CN #{cn} did not resolve to an active worker"
        reject_unauthorized_connection
        true
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

    def authenticate_user(payload)
      user = User.find(payload[:sub])

      if user&.active? && user.account&.active?
        return if reject_for_maintenance!(user)

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
        return if reject_for_maintenance!(user_token.user)

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

    # Mirrors Authentication#handle_impersonation_jwt_token (REST) — resolves
    # the impersonated user as the connection's identity, and tracks the
    # impersonator separately so reject_for_maintenance! can apply the same
    # impersonator exemption the REST/MCP gates already do (an impersonating
    # admin must not be trapped by a maintenance window either).
    def authenticate_impersonation(payload)
      session = ImpersonationSession.find_by(id: payload[:session_id])

      unless session&.active?
        Rails.logger.warn "ActionCable: invalid or inactive impersonation session"
        reject_unauthorized_connection
        return
      end

      if session.expired?
        session.end_session!
        Rails.logger.warn "ActionCable: impersonation session expired"
        reject_unauthorized_connection
        return
      end

      unless session.impersonator_currently_authorized?
        session.end_session!
        Rails.logger.warn "ActionCable: impersonator no longer authorized"
        reject_unauthorized_connection
        return
      end

      user = session.impersonated_user
      impersonator_user = session.impersonator

      unless user&.active? && user.account&.active?
        Rails.logger.warn "ActionCable: impersonated user inactive"
        reject_unauthorized_connection
        return
      end

      return if reject_for_maintenance!(user, impersonator: impersonator_user)

      Rails.logger.info "ActionCable: impersonation authentication successful for #{user.email} (by #{impersonator_user&.email})"
      self.current_user = user
      self.impersonator = impersonator_user
    end

    # Mirrors Authentication#authenticate_request's REST gate and
    # McpTokenAuthentication's MCP gate — see Admin::MaintenanceMode.blocked?.
    # No delegation concept applies to a cable connection (unlike the REST
    # path), so User#has_permission? directly is correct here, same as the
    # MCP/doorkeeper path. `impersonator`, when present, gets the same
    # exemption Authentication#maintenance_exempt_permission? applies on the
    # REST path — an impersonating admin must not be trapped either.
    #
    # N2: rejects via close(reason: "maintenance_mode", reconnect: false) —
    # NOT reject_unauthorized_connection (raises UnauthorizedError, which the
    # server reports as {type: "disconnect", reason: "unauthorized"}).
    # WebSocketManager (frontend) treats "unauthorized" as an expired-session
    # signal: it silently refreshes the token and reconnects — succeeding
    # immediately, since refresh is never itself maintenance-gated — then
    # gets rejected again on the new connection, looping roughly once a
    # second for as long as maintenance mode stays on. A distinct reason
    # lets the frontend recognize "the server is deliberately closing this
    # and reconnecting is pointless right now" instead.
    def reject_for_maintenance!(user, impersonator: nil)
      return false unless Admin::MaintenanceMode.blocked?(request.remote_ip) { |perm| user.has_permission?(perm) || (impersonator && impersonator.has_permission?(perm)) }

      Rails.logger.info "ActionCable: closing #{user.email} — maintenance mode"
      close_for_maintenance!
      true
    end

    # Guarded the same way #transmit_minted_tokens! is: ActionCable::
    # Connection::TestCase's TestConnection module (used by `connect` in
    # connection_spec.rb) never runs the real Base#initialize, so @coder
    # (and @websocket, which the real #close transmits through) are never
    # set — calling the real #close there would raise on a nil websocket.
    # Skipping it in that harness is safe: the meaningful, tested behavior
    # is that current_user is never set, not the wire frame itself.
    def close_for_maintenance!
      return unless instance_variable_defined?(:@coder) && @coder

      close(reason: "maintenance_mode", reconnect: false)
    end

    def extract_token_from_headers
      auth_header = request.headers["Authorization"]
      if auth_header&.start_with?("Bearer ")
        auth_header.split(" ").last
      end
    end
  end
end
