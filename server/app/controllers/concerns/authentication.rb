# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user, :current_account
  end

  private

  def authenticate_request
    header = request.headers["Authorization"]
    header = header.split(" ").last if header

    return render_unauthorized("Access token required") unless header

    begin
      payload = JwtService.decode(header)
      @current_user = User.find(payload[:user_id])
      @current_account = @current_user.account

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

  def require_permission(permission_name)
    render_forbidden("Permission denied") unless current_user&.has_permission?(permission_name)
  end

  def require_role(role_name)
    render_forbidden("Insufficient role") unless current_user&.has_role?(role_name)
  end

  def render_unauthorized(message = "Unauthorized")
    render json: { success: false, error: message }, status: :unauthorized
  end

  def render_forbidden(message = "Forbidden")
    render json: { success: false, error: message }, status: :forbidden
  end

  def should_record_login?
    # Only record login once per hour to avoid excessive database writes
    current_user.last_login_at.nil? || current_user.last_login_at < 1.hour.ago
  end
end
