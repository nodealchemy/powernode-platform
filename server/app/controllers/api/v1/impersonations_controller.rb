# frozen_string_literal: true

class Api::V1::ImpersonationsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :validate_token, :destroy ]
  before_action :require_impersonation_permission, only: [ :create ]
  # destroy (stop impersonation) should be available to any authenticated user
  before_action :require_admin_access, only: [ :index, :history, :impersonatable_users, :cleanup_expired ]
  before_action :find_target_user, only: [ :create ]

  # POST /api/v1/impersonation
  def create
    service = ImpersonationService.new(current_user)

    begin
      token = service.start_impersonation(
        target_user_id: @target_user.id,
        reason: params[:reason],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      render_success(
        message: "Impersonation started successfully",
        data: {
          token: token,
          target_user: user_summary(@target_user),
          expires_at: (Time.current + ImpersonationSession::MAX_SESSION_DURATION).iso8601
        },
        status: :created
      )
    rescue ImpersonationService::Error => e
      render_error(e.message, status: :unprocessable_content)
    end
  end

  # DELETE /api/v1/impersonations
  def destroy
    session_token = params[:session_token]
    return render_error("Session token required", status: :bad_request) unless session_token

    # Manual authentication for destroy action since we skip the before_action
    header = request.headers["Authorization"]
    header = header.split(" ").last if header

    if header
      begin
        # Try to authenticate the current token
        user_token = UserToken.authenticate(header)
        if user_token
          if user_token.token_type == "impersonation"
            handle_impersonation_token(user_token)
          else
            handle_regular_token(user_token)
          end
        end
      rescue => e
        Rails.logger.warn "Failed to authenticate during impersonation destroy: #{e.message}"
      end
    end

    # If we couldn't authenticate, we can still try to end the session using just the session_token
    # This is important because impersonation tokens might be expired but we still want to cleanup

    begin
      Rails.logger.info "Attempting to end impersonation session with token: #{session_token[0..10]}..." if session_token

      # First try to find UserToken to get the impersonator
      user_token = UserToken.find_by_token(session_token)
      service_user = current_user

      if user_token && user_token.token_type == "impersonation"
        # For impersonation tokens, ALWAYS use the impersonator from metadata
        # (current_user is the impersonated user, not the impersonator)
        impersonator_id = user_token.metadata["impersonator_id"]
        if impersonator_id
          service_user = User.find_by(id: impersonator_id)
        end
      else
        # Legacy handling - try to find session directly
        session = ImpersonationSession.find_by(session_token: session_token)
        service_user = service_user || session&.impersonator
      end

      unless service_user
        return render_error("Unable to authenticate impersonation end request", status: :unauthorized)
      end

      # Let the service handle all the token validation and session cleanup
      service = ImpersonationService.new(service_user)
      session = service.end_impersonation(session_token)

      Rails.logger.info "Impersonation session ended successfully: #{session.id}"

      render_success(
        message: "Impersonation ended successfully",
        data: {
          duration: session.duration.to_i
        }
      )
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn "Impersonation session not found: #{e.message}"
      render_not_found(e)
    rescue ImpersonationService::Error => e
      Rails.logger.warn "Impersonation service error: #{e.message}"
      render_error(e.message, status: :unprocessable_content)
    rescue StandardError => e
      Rails.logger.error "Unexpected error ending impersonation: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?

      render_error("Failed to end impersonation session", :internal_server_error, code: "impersonation_end_failed")
    end
  end

  # GET /api/v1/impersonation
  def index
    service = ImpersonationService.new(current_user)
    active_sessions = service.list_active_sessions

    render_success(
      data: active_sessions.map { |session| session_summary(session) }
    )
  end

  # GET /api/v1/impersonation/history
  def history
    service = ImpersonationService.new(current_user)
    limit = [ params[:limit]&.to_i || 50, 200 ].min

    sessions = service.get_session_history(limit: limit)

    render_success(
      data: sessions.map { |session| session_summary(session) },
      pagination: {
        limit: limit,
        total: sessions.length
      }
    )
  end

  # GET /api/v1/impersonation/users
  def impersonatable_users
    # System Administrators can impersonate users from any account
    if current_user.has_permission?("admin.access")
      users = User.includes(:account)
                  .active
                  .where.not(id: current_user.id)
                  .order(:name)

      # System admins can impersonate anyone except other system admins
      users = users.where.not(role: "admin")
    else
      # Regular account users can only impersonate within their account
      users = current_account.users
                            .active
                            .where.not(id: current_user.id)
                            .order(:name)

      # Filter out owners if current user is not owner
      users = users.where.not(role: "owner") unless current_user.has_permission?("account.manage")
    end

    render_success(
      data: users.map { |user| user_summary_with_account(user) }
    )
  end

  # POST /api/v1/impersonation/validate
  def validate_token
    token = params[:token]
    return render_error("Token required", status: :bad_request) unless token

    begin
      # Try UserToken first (new system), then fall back to JWT (legacy)
      user_token = UserToken.find_by_token(token)
      session = nil

      if user_token && user_token.token_type == "impersonation"
        # This is a UserToken - get impersonator from metadata
        impersonator_id = user_token.metadata["impersonator_id"]
        impersonator = User.find_by(id: impersonator_id)

        unless impersonator
          return render_success(
            data: {
              valid: false,
              message: "Impersonator user not found"
            }
          )
        end

        # Create service with the impersonator user
        service = ImpersonationService.new(impersonator)
        session = service.validate_impersonation_token(token)
      elsif token.include?(".")
        # Legacy JWT token handling
        begin
          # Decode the token to get the impersonator user
          payload = JwtService.decode(token)

          unless payload[:type] == "impersonation"
            return render_success(
              data: {
                valid: false,
                message: "Invalid token type"
              }
            )
          end

          impersonator = User.find_by(id: payload[:impersonator_id])
          unless impersonator
            return render_success(
              data: {
                valid: false,
                message: "Impersonator user not found"
              }
            )
          end

          # Create service with the impersonator user
          service = ImpersonationService.new(impersonator)
          session = service.validate_impersonation_token(token)
        rescue JWT::DecodeError, JWT::ExpiredSignature => e
          return render_success(
            data: {
              valid: false,
              message: "Invalid or expired token"
            }
          )
        end
      else
        return render_success(
          data: {
            valid: false,
            message: "Invalid token format"
          }
        )
      end

      # Handle the session result
      if session
        render_success(
          data: {
            valid: true,
            session: session_summary(session),
            expires_at: (session.started_at + ImpersonationSession::MAX_SESSION_DURATION).iso8601
          }
        )
      else
        render_success(
          data: {
            valid: false,
            message: "Invalid or expired impersonation token"
          }
        )
      end
    rescue StandardError => e
      # Handle unexpected errors
      Rails.logger.error "Error validating impersonation token: #{e.message}"
      render_error("Token validation failed", status: :internal_server_error)
    end
  end

  # POST /api/v1/impersonation/cleanup_expired (for worker service)
  def cleanup_expired
    skip_authorization # Service-to-service call

    begin
      cleaned_count = ImpersonationSession.cleanup_expired_sessions

      render_success(
        data: {
          cleaned_up_count: cleaned_count
        },
        message: "Successfully cleaned up #{cleaned_count} expired sessions"
      )
    rescue StandardError => e
      Rails.logger.error "Error cleaning up expired impersonation sessions: #{e.message}"

      render_error("Failed to cleanup expired sessions: #{e.message}", status: :internal_server_error)
    end
  end

  private

  def require_admin_access
    unless current_user.has_permission?("admin.access")
      render_forbidden("You do not have permission to access this resource")
    end
  end

  def require_impersonation_permission
    unless current_user.has_permission?("admin.user.impersonate") || current_user.has_permission?("account.manage") || current_user.has_permission?("admin.access")
      render_forbidden("You do not have permission to manage impersonation")
    end
  end

  def find_target_user
    user_id = params[:user_id]
    return render_error("User ID required", status: :bad_request) unless user_id

    # System Administrators can impersonate users from any account
    if current_user.has_permission?("admin.access")
      @target_user = User.find(user_id)

      # System admins cannot impersonate other system admins
      if @target_user.admin?
        render_error("Cannot impersonate other system administrators", status: :forbidden)
      end
    else
      # Regular users can only impersonate within their account
      @target_user = current_account.users.find(user_id)
    end
  rescue ActiveRecord::RecordNotFound
    render_error(
      current_user.has_permission?("admin.access") ? "User not found" : "User not found in your account",
      :not_found
    )
  end

  def user_summary(user)
    {
      id: user.id,
      email: user.email,
      full_name: user.full_name,
      roles: user.role_names,
      permissions: user.permission_names,
      status: user.status,
      last_login_at: user.last_login_at&.iso8601
    }
  end

  def user_summary_with_account(user)
    base_summary = user_summary(user)

    # Add account information for system admins
    if current_user.has_permission?("admin.access") && user.account
      base_summary[:account] = {
        id: user.account.id,
        name: user.account.name,
        status: user.account.status
      }
    end

    base_summary
  end

  def session_summary(session)
    {
      id: session.id,
      session_token: session.session_token,
      impersonator: user_summary(session.impersonator),
      impersonated_user: user_summary(session.impersonated_user),
      reason: session.reason,
      started_at: session.started_at&.iso8601,
      ended_at: session.ended_at&.iso8601,
      duration: session.duration&.to_i,
      active: session.active?,
      expired: session.expired?
    }
  end

  # Authentication helper methods for destroy action
  def handle_impersonation_token(user_token)
    # Get impersonation session ID from token metadata
    session_id = user_token.metadata["session_id"]
    @impersonation_session = ImpersonationSession.find_by(id: session_id)

    unless @impersonation_session&.active?
      raise StandardError, "Invalid impersonation session"
    end

    if @impersonation_session.expired?
      @impersonation_session.end_session!
      raise StandardError, "Impersonation session expired"
    end

    # Set the impersonated user as current user
    @current_user = @impersonation_session.impersonated_user
    @current_account = @current_user.account
    @impersonator = @impersonation_session.impersonator
    @current_user_token = user_token
  end

  def handle_regular_token(user_token)
    @current_user = user_token.user
    @current_account = @current_user.account
    @current_user_token = user_token
  end
end
