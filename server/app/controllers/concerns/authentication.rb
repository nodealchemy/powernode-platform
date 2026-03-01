# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user, :current_account, :current_worker, :current_jwt_payload
  end

  private

  def authenticate_request
    header = request.headers["Authorization"]
    header = header.split(" ").last if header

    return render_unauthorized("Access token required") unless header

    # JWT-only token authentication
    begin
      payload = Security::JwtService.decode(header)

      case payload[:type]
      when "access"
        handle_user_token(payload)
      when "worker"
        handle_worker_token(payload)
      when "impersonation"
        handle_impersonation_jwt_token(payload)
      else
        return render_unauthorized("Invalid token type")
      end

      # Validate user/account status for user tokens
      if @current_user
        return render_unauthorized("User inactive") unless @current_user.active?
        return render_unauthorized("No account associated") unless @current_account
        return render_unauthorized("Account suspended") unless @current_account.active?
        @current_user.record_login! if should_record_login?
      end

      return
    rescue StandardError
      render_unauthorized("Invalid access token")
    end
  end

  def authenticate_optional
    header = request.headers["Authorization"]
    return unless header

    header = header.split(" ").last

    begin
      # JWT-only authentication
      payload = Security::JwtService.decode(header)

      case payload[:type]
      when "access"
        user = User.find(payload[:sub])
        if user&.active? && user.account&.active?
          @current_user = user
          @current_account = user.account
          @current_user.record_login! if should_record_login?
        end
      when "worker"
        worker = Worker.find(payload[:sub])
        @current_worker = worker if worker&.active?
        @current_account = @current_worker&.account
      when "impersonation"
        handle_impersonation_jwt_token(payload)
      end
    rescue StandardError
      @current_user = nil
      @current_account = nil
      @current_worker = nil
    end
  end

  def should_record_login?
    # Only record login once per hour to avoid excessive database writes
    # Don't record login for impersonation sessions
    return false if impersonating?

    current_user.last_login_at.nil? || current_user.last_login_at < 1.hour.ago
  end

  def handle_user_token(payload)
    @current_user = User.find(payload[:sub])
    @current_account = @current_user.account
    @current_jwt_payload = payload
    @impersonator = nil
    @impersonation_session = nil
  end

  def handle_worker_token(payload)
    @current_worker = Worker.find(payload[:sub])
    @current_account = @current_worker.account
    @current_jwt_payload = payload
  end

  def handle_impersonation_jwt_token(payload)
    # Get impersonation session ID from JWT metadata
    session_id = payload[:session_id]
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
    @current_jwt_payload = payload

    # Add impersonation header for client identification
    response.set_header("X-Impersonation-Active", "true")
  end

  def impersonating?
    @impersonation_session.present?
  end

  def impersonator
    @impersonator
  end

  def impersonation_session
    @impersonation_session
  end

  # Permission checking methods (NEVER use roles for access control)
  def require_permission(permission_name)
    unless has_permission?(permission_name)
      render_forbidden("Permission denied: #{permission_name}")
    end
  end

  def require_any_permission(*permission_names)
    unless permission_names.any? { |p| has_permission?(p) }
      render_forbidden("Permission denied: requires one of #{permission_names.join(', ')}")
    end
  end

  def require_all_permissions(*permission_names)
    unless permission_names.all? { |p| has_permission?(p) }
      render_forbidden("Permission denied: requires all of #{permission_names.join(', ')}")
    end
  end

  # Deprecated: Use permission checks instead
  def require_admin!
    # Legacy method - redirects to permission check
    require_any_permission("admin.access", "system.admin")
  end

  # Check if current entity (user or worker) has permission without rendering error
  def has_permission?(permission_name)
    # For JWT tokens, check permissions directly from token payload (faster)
    if @current_jwt_payload&.dig(:permissions)&.include?(permission_name)
      return true
    end

    # Fallback to database checks
    return current_user.has_permission?(permission_name) if current_user
    return current_worker.has_permission?(permission_name) if current_worker
    false
  end

  # Alias for backwards compatibility
  def can?(permission_name)
    has_permission?(permission_name)
  end

  # Check if current entity can access a resource action
  def can_access?(resource, action)
    has_permission?("#{resource}.#{action}")
  end

  # Note: render_unauthorized and render_forbidden are provided by ApiResponse concern
  # ApplicationController includes ApiResponse after Authentication, so those methods take precedence

  def extract_bearer_token
    auth_header = request.headers["Authorization"]
    return nil unless auth_header&.start_with?("Bearer ")

    auth_header.split(" ", 2).last
  end

  # Check if current request is from a worker
  def worker_authenticated?
    @current_worker.present?
  end
end
