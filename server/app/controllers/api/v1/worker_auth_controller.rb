# frozen_string_literal: true

# Sidekiq web UI authentication endpoints.
#
# Callers: ONLY `powernode-worker-web` (Sinatra app on port 4567 that
# serves Sidekiq web UI). The worker forwards user-credential requests
# from its login form to the platform; this controller validates the
# USER credentials and returns a worker-local session token.
#
# Auth model: mTLS. The worker presents its mTLS client cert via Faraday
# SSL options (WorkerCertManager); Traefik terminates on the
# `<slug>-worker-auth` router (mTLS-required) and forwards the verified
# CN — which is the NodeInstance.id — via `X-Forwarded-Tls-Client-Cert-Info`.
# This controller resolves the Worker via `node_instance_id` (shared with
# Internal::InternalBaseController via MtlsClientAuthentication).
class Api::V1::WorkerAuthController < ApplicationController
  include MtlsClientAuthentication

  skip_before_action :authenticate_request
  before_action :authenticate_worker_via_mtls!

  # POST /api/v1/worker_auth/authenticate_user
  # Authenticate user credentials for Sidekiq web interface
  def authenticate_user
    Rails.logger.info "Worker auth attempt started"

    email = params[:email]&.strip&.downcase
    password = params[:password]

    unless email.present? && password.present?
      return render_error("Email and password are required", status: :bad_request)
    end

    Rails.logger.info "Attempting authentication for email: #{email}"
    user = User.find_by(email: email)

    unless user
      Rails.logger.warn "User not found: #{email}"
      return render_error("Invalid email or password", status: :unauthorized)
    end

    if !user.authenticate(password)
      Rails.logger.warn "Password authentication failed for: #{email}"
      return render_error("Invalid email or password", status: :unauthorized)
    end

    unless user.email_verified?
      Rails.logger.warn "Email not verified for: #{email}"
      return render_error("Email not verified", status: :unauthorized)
    end

    unless user.has_permission?("admin.access") || user.has_permission?("system.admin")
      Rails.logger.warn "Insufficient permissions for: #{email}"
      return render_error("Insufficient permissions to access worker interface", status: :forbidden)
    end

    session_token = generate_session_token(user)
    store_worker_session!(session_token, user)

    Rails.logger.info "Worker authentication successful for user: #{email}"

    render_success({
      valid: true,
      session_token: session_token,
      user_email: user.email,
      expires_at: (Time.current + 24.hours).iso8601,
      permissions: user.permission_names
    })
  rescue StandardError => e
    Rails.logger.error "Worker authentication error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render_error("Authentication failed", status: :internal_server_error)
  end

  # POST /api/v1/worker_auth/verify_platform_token
  # Verify a platform JWT for Sidekiq web interface access.
  # Body carries the USER's platform access token; mTLS verifies the
  # CALLER (worker) at the transport layer.
  def verify_platform_token
    token = params[:token]

    unless token.present?
      return render_error("Token is required", status: :bad_request)
    end

    begin
      payload = Security::JwtService.decode(token)
    rescue StandardError => e
      Rails.logger.warn "Worker platform token verification failed: #{e.message}"
      return render_error("Invalid or expired token", status: :unauthorized)
    end

    # Only a short-lived ACCESS token may mint a worker session. A refresh
    # token is long-lived (7-day) and meant solely for /sessions/refresh —
    # accepting one here would let a stolen refresh token open a 24h admin
    # Sidekiq-web session.
    unless payload[:type] == "access"
      return render_error("Invalid token type", status: :unauthorized)
    end

    user = User.find_by(id: payload[:sub])
    unless user&.active?
      return render_error("User not found or inactive", status: :unauthorized)
    end

    unless user.email_verified?
      return render_error("Email not verified", status: :unauthorized)
    end

    unless user.has_permission?("admin.access") || user.has_permission?("system.admin")
      return render_error("Insufficient permissions to access worker interface", status: :forbidden)
    end

    session_token = generate_session_token(user)
    store_worker_session!(session_token, user)

    Rails.logger.info "Worker platform token verified for user: #{user.email}"

    render_success({
      valid: true,
      session_token: session_token,
      user_email: user.email,
      expires_at: (Time.current + 24.hours).iso8601
    })
  end

  # POST /api/v1/worker_auth/verify_session
  # Verify session token for authenticated Sidekiq web interface users
  def verify_session
    session_token = params[:session_token]

    unless session_token.present?
      return render_error("Session token is required", status: :bad_request)
    end

    session_data = Rails.cache.read("worker_session:#{session_token}")

    if session_data
      user = User.find_by(id: session_data[:user_id])

      if user && (user.has_permission?("admin.access") || user.has_permission?("system.admin"))
        render_success({
          valid: true,
          user_email: session_data[:user_email],
          permissions: session_data[:permissions],
          expires_at: (Time.current + 24.hours).iso8601
        })
      else
        Rails.cache.delete("worker_session:#{session_token}")
        render_error("Session invalid - user permissions changed", status: :unauthorized)
      end
    else
      render_error("Invalid or expired session token", status: :unauthorized)
    end
  end

  private

  def generate_session_token(_user)
    SecureRandom.uuid
  end

  # The cached `permissions` array is a 24h snapshot that nothing busts (a raw-SQL
  # permission migration will not touch it). Traced for IMP-4b5fffbf5421: NO
  # authorization decision reads it, so it is not an unbusted authorization store.
  # Its only reader is #verify_session, which echoes it into the response body
  # after re-deriving the actual verdict LIVE from the User row
  # (has_permission?("admin.access") || has_permission?("system.admin")) and
  # deleting the entry when that now fails. On the consumer side, worker's
  # app/middleware/sidekiq_web_auth.rb reads only `valid`, `session_token`,
  # `user_email` and `expires_at` from that body — it never reads `permissions`.
  # So the snapshot is display data with no live consumer; recorded here so the
  # next reader does not re-investigate it.
  def store_worker_session!(session_token, user)
    Rails.cache.write(
      "worker_session:#{session_token}",
      {
        user_id: user.id,
        user_email: user.email,
        permissions: user.permission_names,
        created_at: Time.current.iso8601
      },
      expires_in: 24.hours
    )
  end
end
