# frozen_string_literal: true

class ImpersonationService
  class Error < StandardError; end
  class PermissionDeniedError < Error; end
  class InvalidUserError < Error; end
  class SessionNotFoundError < Error; end
  class SelfImpersonationError < Error; end

  def initialize(current_user)
    @current_user = current_user
  end

  def start_impersonation(target_user_id:, reason: nil, ip_address: nil, user_agent: nil)
    target_user = User.find(target_user_id)
    
    validate_impersonation_request!(target_user)
    
    # Create new impersonation session
    session = ImpersonationSession.create_session!(
      impersonator: @current_user,
      impersonated_user: target_user,
      reason: reason,
      ip_address: ip_address,
      user_agent: user_agent
    )

    # Log the impersonation start
    AuditLog.create!(
      user: @current_user,
      account: @current_user.account,
      action: 'impersonation.started',
      resource_type: 'User',
      resource_id: target_user.id,
      source: 'admin_panel',
      ip_address: ip_address,
      user_agent: user_agent,
      metadata: {
        impersonated_user_email: target_user.email,
        reason: reason,
        session_id: session.id
      }
    )

    # Generate impersonation token
    generate_impersonation_token(session, target_user)
  end

  def end_impersonation(session_token)
    session = ImpersonationSession.active.find_by!(session_token: session_token)
    
    unless session.impersonator == @current_user
      raise PermissionDeniedError, 'You can only end your own impersonation sessions'
    end

    session.end_session!

    # Log the impersonation end
    AuditLog.create!(
      user: @current_user,
      account: @current_user.account,
      action: 'impersonation.ended',
      resource_type: 'User',
      resource_id: session.impersonated_user_id,
      source: 'admin_panel',
      metadata: {
        impersonated_user_email: session.impersonated_user.email,
        duration: session.duration.to_i,
        session_id: session.id
      }
    )

    session
  end

  def list_active_sessions(account_id = nil)
    account_id ||= @current_user.account_id
    
    ImpersonationSession.active
                       .for_account(account_id)
                       .includes(:impersonator, :impersonated_user)
                       .recent
  end

  def get_session_history(account_id = nil, limit: 50)
    account_id ||= @current_user.account_id
    
    ImpersonationSession.for_account(account_id)
                       .includes(:impersonator, :impersonated_user)
                       .recent
                       .limit(limit)
  end

  def validate_impersonation_token(token)
    begin
      payload = JwtService.decode(token)
      
      return nil unless payload[:type] == 'impersonation'
      
      session = ImpersonationSession.find_by(id: payload[:session_id])
      return nil unless session&.active?
      
      # Check if session has expired
      if session.expired?
        session.end_session!
        return nil
      end
      
      session
    rescue StandardError
      nil
    end
  end

  def self.cleanup_expired_sessions
    ImpersonationSession.cleanup_expired_sessions
  end

  private

  def validate_impersonation_request!(target_user)
    # Check if current user has impersonation permission
    unless @current_user.has_permission?('users.impersonate') || @current_user.owner? || @current_user.admin?
      raise PermissionDeniedError, 'You do not have permission to impersonate other users'
    end

    # Check if target user exists and is in the same account
    # System administrators can impersonate users from any account
    unless @current_user.admin? || target_user.account == @current_user.account
      raise InvalidUserError, 'You can only impersonate users in your own account'
    end

    # Prevent self-impersonation
    if target_user == @current_user
      raise SelfImpersonationError, 'You cannot impersonate yourself'
    end

    # Check if target user is active
    unless target_user.active?
      raise InvalidUserError, 'Cannot impersonate inactive user'
    end

    # Prevent impersonating owners if current user is not owner
    if target_user.owner? && !@current_user.owner?
      raise PermissionDeniedError, 'Only owners can impersonate other owners'
    end

    # Prevent system administrators from impersonating other system administrators
    if target_user.admin? && @current_user.admin?
      raise PermissionDeniedError, 'System administrators cannot impersonate other system administrators'
    end
  end

  def generate_impersonation_token(session, target_user)
    payload = {
      user_id: target_user.id,
      impersonator_id: @current_user.id,
      session_id: session.id,
      type: 'impersonation',
      exp: (Time.current + ImpersonationSession::MAX_SESSION_DURATION).to_i
    }

    JwtService.encode(payload)
  end
end