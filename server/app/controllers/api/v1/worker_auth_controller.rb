# frozen_string_literal: true

class Api::V1::WorkerAuthController < ApplicationController
  skip_before_action :authenticate_request, only: [ :authenticate_user, :verify_session, :verify, :verify_platform_token ]
  before_action :authenticate_service_request, only: [ :authenticate_user, :verify_session, :verify_platform_token ]

  # POST /api/v1/service/verify
  # Service token verification for worker communication
  def verify
    if authenticate_service_token
      render_success({
        valid: true,
        service: "powernode_worker",
        timestamp: Time.current.iso8601
      })
    else
      render_error("Invalid service token", status: :unauthorized)
    end
  end

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

    # Check if user has admin permissions for Sidekiq access
    unless user.has_permission?("admin.access") || user.has_permission?("system.admin")
      Rails.logger.warn "Insufficient permissions for: #{email}"
      return render_error("Insufficient permissions to access worker interface", status: :forbidden)
    end

    # Generate session token for the worker interface
    session_token = generate_session_token(user)

    # Store session with expiration (24 hours for worker interface)
    Rails.cache.write(
      "worker_session:#{session_token}",
      {
        user_id: user.id,
        user_email: user.email,
        permissions: user.permissions.pluck(:resource, :action).map { |r, a| "#{r}.#{a}" },
        created_at: Time.current.iso8601
      },
      expires_in: 24.hours
    )

    Rails.logger.info "Worker authentication successful for user: #{email}"

    render_success({
      valid: true,
      session_token: session_token,
      user_email: user.email,
      expires_at: (Time.current + 24.hours).iso8601,
      permissions: user.permissions.pluck(:resource, :action).map { |r, a| "#{r}.#{a}" }
    })
  rescue StandardError => e
    Rails.logger.error "Worker authentication error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render_error("Authentication failed", status: :internal_server_error)
  end

  # POST /api/v1/worker_auth/verify_platform_token
  # Verify a platform JWT for Sidekiq web interface access.
  # Accepts an access/refresh token issued by JwtService, validates the user
  # exists, is active, email-verified, and has admin permissions.
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

    unless payload[:type].in?(%w[access refresh])
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

    # Generate session token for the worker interface
    session_token = generate_session_token(user)

    Rails.cache.write(
      "worker_session:#{session_token}",
      {
        user_id: user.id,
        user_email: user.email,
        permissions: user.permissions.pluck(:resource, :action).map { |r, a| "#{r}.#{a}" },
        created_at: Time.current.iso8601
      },
      expires_in: 24.hours
    )

    Rails.logger.info "Worker platform token verified for user: #{user.email}"

    render_success({
      valid: true,
      session_token: session_token,
      user_email: user.email,
      expires_at: (Time.current + 24.hours).iso8601
    })
  end

  # POST /api/v1/service/verify_session
  # Verify session token for authenticated Sidekiq web interface users
  def verify_session
    session_token = params[:session_token]

    unless session_token.present?
      return render_error("Session token is required", status: :bad_request)
    end

    session_data = Rails.cache.read("worker_session:#{session_token}")

    if session_data
      # Verify user still exists and has permissions
      user = User.find_by(id: session_data[:user_id])

      if user && (user.has_permission?("admin.access") || user.has_permission?("system.admin"))
        render_success({
          valid: true,
          user_email: session_data[:user_email],
          permissions: session_data[:permissions],
          expires_at: (Time.current + 24.hours).iso8601
        })
      else
        # User no longer exists or lost permissions, invalidate session
        Rails.cache.delete("worker_session:#{session_token}")
        render_error("Session invalid - user permissions changed", status: :unauthorized)
      end
    else
      render_error("Invalid or expired session token", status: :unauthorized)
    end
  end

  private

  def authenticate_service_request
    unless authenticate_service_token
      render_error("Service authentication required", status: :unauthorized)
    end
  end

  def authenticate_service_token
    auth_header = request.headers["Authorization"]
    return false unless auth_header&.start_with?("Bearer ")

    token = auth_header.split(" ").last
    return false if token.blank?

    # JWT-only worker authentication
    begin
      payload = Security::JwtService.decode(token)
      return false unless payload[:type] == "worker"

      worker = Worker.find_by(id: payload[:sub], status: "active")
      return false unless worker&.system?

      @current_worker = worker
      true
    rescue StandardError
      false
    end
  end

  def generate_session_token(user)
    # Generate secure session token using a simple UUID for now
    # In production, this would use proper JWT with secure secrets
    SecureRandom.uuid
  end
end
