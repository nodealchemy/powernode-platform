# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user, :current_account, :current_worker
  end

  private

  def authenticate_request
    header = request.headers["Authorization"]
    header = header.split(" ").last if header

    return render_unauthorized("Access token required") unless header

    begin
      payload = JwtService.decode(header)
      
      # Check if this is an impersonation token
      if payload[:type] == 'impersonation'
        handle_impersonation_token(payload)
      else
        handle_regular_token(payload)
      end

      return render_unauthorized("User inactive") unless @current_user.active?
      return render_unauthorized("Account suspended") unless @current_account.active?

      @current_user.record_login! if should_record_login?
    rescue StandardError => e
      if e.message.include?("expired")
        render_unauthorized("Access token expired")
      elsif e.message.include?("Invalid token")
        render_unauthorized("Invalid access token")
      else
        render_unauthorized("Invalid access token")
      end
    end
  end

  def authenticate_optional
    header = request.headers["Authorization"]
    return unless header

    header = header.split(" ").last

    begin
      payload = JwtService.decode(header)
      @current_user = User.find(payload[:user_id])
      @current_account = @current_user.account

      if @current_user.active? && @current_account.active?
        @current_user.record_login! if should_record_login?
      else
        @current_user = nil
        @current_account = nil
      end
    rescue StandardError
      @current_user = nil
      @current_account = nil
    end
  end

  def render_unauthorized(message = "Unauthorized")
    render json: { success: false, error: message }, status: :unauthorized
  end

  def should_record_login?
    # Only record login once per hour to avoid excessive database writes
    # Don't record login for impersonation sessions
    return false if impersonating?
    
    current_user.last_login_at.nil? || current_user.last_login_at < 1.hour.ago
  end

  def handle_regular_token(payload)
    @current_user = User.find(payload[:user_id])
    @current_account = @current_user.account
    @impersonator = nil
    @impersonation_session = nil
  end

  def handle_impersonation_token(payload)
    @impersonation_session = ImpersonationSession.find_by(id: payload[:session_id])
    
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

    # Add impersonation header for client identification
    response.set_header('X-Impersonation-Active', 'true')
    response.set_header('X-Impersonator-Email', @impersonator.email)
    response.set_header('X-Impersonation-Session', @impersonation_session.id)
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
    unless current_user&.has_permission?(permission_name)
      render_forbidden("Permission denied: #{permission_name}")
    end
  end

  def require_any_permission(*permission_names)
    unless permission_names.any? { |p| current_user&.has_permission?(p) }
      render_forbidden("Permission denied: requires one of #{permission_names.join(', ')}")
    end
  end

  def require_all_permissions(*permission_names)
    unless permission_names.all? { |p| current_user&.has_permission?(p) }
      render_forbidden("Permission denied: requires all of #{permission_names.join(', ')}")
    end
  end
  
  # Deprecated: Use permission checks instead
  def require_admin!
    # Legacy method - redirects to permission check
    require_any_permission('admin.access', 'system.admin')
  end

  # Check if user has permission without rendering error
  def can?(permission_name)
    current_user&.has_permission?(permission_name) || false
  end

  # Check if user can access a resource action
  def can_access?(resource, action)
    can?("#{resource}.#{action}")
  end

  # Render forbidden response
  def render_forbidden(message = "Access denied")
    render json: {
      success: false,
      error: message
    }, status: :forbidden
  end

  # Worker authentication methods
  def authenticate_worker_request!
    worker_token = extract_worker_token
    return render_unauthorized("Worker token required") unless worker_token

    @current_worker = Worker.authenticate(worker_token)
    return render_unauthorized("Invalid or inactive worker token") unless @current_worker

    true
  end

  def authenticate_worker_optional
    worker_token = extract_worker_token
    return unless worker_token

    begin
      @current_worker = Worker.authenticate(worker_token)
    rescue StandardError
      @current_worker = nil
    end
  end

  def extract_worker_token
    auth_header = request.headers['Authorization']
    return nil unless auth_header&.start_with?('Bearer ')
    
    token = auth_header.split(' ', 2).last
    # Worker tokens start with 'swt_'
    token if token&.start_with?('swt_')
  end

  # Check if current request is from a worker
  def worker_authenticated?
    @current_worker.present?
  end
end
