# frozen_string_literal: true

class Api::V1::ImpersonationsController < ApplicationController
  skip_before_action :authenticate_request, only: [:validate_token]
  before_action :require_admin!, except: [:validate_token]
  before_action :require_permission, only: [:create, :destroy]
  before_action :find_target_user, only: [:create]
  before_action :rate_limit_impersonation, only: [:create]

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

      render json: {
        success: true,
        message: 'Impersonation started successfully',
        data: {
          token: token,
          target_user: user_summary(@target_user),
          expires_at: (Time.current + ImpersonationSession::MAX_SESSION_DURATION).iso8601
        }
      }, status: :created
    rescue ImpersonationService::Error => e
      render json: {
        success: false,
        error: e.message
      }, status: :unprocessable_content
    end
  end

  # DELETE /api/v1/impersonations
  def destroy
    session_token = params[:session_token]
    return render_bad_request('Session token required') unless session_token

    begin
      Rails.logger.info "Attempting to end impersonation session with token: #{session_token[0..10]}..." if session_token
      
      # If we're currently in an impersonation session (current user is impersonated),
      # we need to use the original impersonator for the service
      service_user = impersonating? ? impersonator : current_user
      service = ImpersonationService.new(service_user)
      
      session = service.end_impersonation(session_token)
      
      Rails.logger.info "Impersonation session ended successfully: #{session.id}"
      
      render json: {
        success: true,
        message: 'Impersonation ended successfully',
        data: {
          duration: session.duration.to_i
        }
      }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn "Impersonation session not found: #{e.message}"
      render_not_found(e)
    rescue ImpersonationService::Error => e
      Rails.logger.warn "Impersonation service error: #{e.message}"
      render json: {
        success: false,
        error: e.message
      }, status: :unprocessable_content
    rescue StandardError => e
      Rails.logger.error "Unexpected error ending impersonation: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
      
      render json: {
        success: false,
        error: 'Failed to end impersonation session',
        code: 'impersonation_end_failed'
      }, status: :internal_server_error
    end
  end

  # GET /api/v1/impersonation
  def index
    service = ImpersonationService.new(current_user)
    active_sessions = service.list_active_sessions

    render json: {
      success: true,
      data: active_sessions.map { |session| session_summary(session) }
    }
  end

  # GET /api/v1/impersonation/history
  def history
    service = ImpersonationService.new(current_user)
    limit = [params[:limit]&.to_i || 50, 200].min
    
    sessions = service.get_session_history(limit: limit)

    render json: {
      success: true,
      data: sessions.map { |session| session_summary(session) },
      pagination: {
        limit: limit,
        total: sessions.length
      }
    }
  end

  # GET /api/v1/impersonation/users
  def impersonatable_users
    # System Administrators can impersonate users from any account
    if current_user.admin?
      users = User.includes(:account)
                  .active
                  .where.not(id: current_user.id)
                  .order(:first_name, :last_name)
      
      # System admins can impersonate anyone except other system admins
      users = users.where.not(role: 'admin')
    else
      # Regular account users can only impersonate within their account
      users = current_account.users
                            .active
                            .where.not(id: current_user.id)
                            .order(:first_name, :last_name)

      # Filter out owners if current user is not owner
      users = users.where.not(role: 'owner') unless current_user.owner?
    end

    render json: {
      success: true,
      data: users.map { |user| user_summary_with_account(user) }
    }
  end

  # POST /api/v1/impersonation/validate
  def validate_token
    token = params[:token]
    return render_bad_request('Token required') unless token

    begin
      # Decode the token to get the impersonator user
      payload = JwtService.decode(token)
      
      unless payload[:type] == 'impersonation'
        return render json: {
          success: true,
          valid: false,
          message: 'Invalid token type'
        }
      end
      
      impersonator = User.find_by(id: payload[:impersonator_id])
      unless impersonator
        return render json: {
          success: true,
          valid: false,
          message: 'Impersonator user not found'
        }
      end
      
      # Create service with the impersonator user
      service = ImpersonationService.new(impersonator)
      session = service.validate_impersonation_token(token)

      if session
        render json: {
          success: true,
          valid: true,
          data: {
            session: session_summary(session),
            expires_at: (session.started_at + ImpersonationSession::MAX_SESSION_DURATION).iso8601
          }
        }
      else
        render json: {
          success: true,
          valid: false,
          message: 'Invalid or expired impersonation token'
        }
      end
    rescue StandardError => e
      # Handle JWT decode errors and other token validation errors
      if e.message.include?('Invalid token') || e.message.include?('blacklisted')
        Rails.logger.warn "Invalid impersonation token: #{e.message}"
        render json: {
          success: true,
          valid: false,
          message: 'Invalid or expired token'
        }
      # Handle user not found errors
      elsif e.is_a?(ActiveRecord::RecordNotFound) || e.message.include?('not found')
        Rails.logger.warn "Impersonator user not found: #{e.message}"
        render json: {
          success: true,
          valid: false,
          message: 'Impersonator user not found'
        }
      else
        # Handle unexpected errors
        Rails.logger.error "Error validating impersonation token: #{e.message}"
        render json: {
          success: false,
          error: 'Token validation failed'
        }, status: :internal_server_error
      end
    end
  end

  private

  def require_permission
    unless current_user.has_permission?('users.impersonate') || current_user.owner? || current_user.admin?
      render_forbidden('You do not have permission to manage impersonation')
    end
  end

  def find_target_user
    user_id = params[:user_id]
    return render_bad_request('User ID required') unless user_id

    # System Administrators can impersonate users from any account
    if current_user.admin?
      @target_user = User.find(user_id)
      
      # System admins cannot impersonate other system admins
      if @target_user.admin?
        return render json: {
          success: false,
          error: 'Cannot impersonate other system administrators'
        }, status: :forbidden
      end
    else
      # Regular users can only impersonate within their account
      @target_user = current_account.users.find(user_id)
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: current_user.admin? ? 'User not found' : 'User not found in your account'
    }, status: :not_found
  end

  def user_summary(user)
    {
      id: user.id,
      email: user.email,
      full_name: user.full_name,
      role: user.role,
      status: user.status,
      last_login_at: user.last_login_at&.iso8601
    }
  end

  def user_summary_with_account(user)
    base_summary = user_summary(user)
    
    # Add account information for system admins
    if current_user.admin? && user.account
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

  # POST /api/v1/impersonation/cleanup_expired (for worker service)
  def cleanup_expired
    skip_authorization # Service-to-service call
    
    begin
      cleaned_count = ImpersonationSession.cleanup_expired_sessions
      
      render json: {
        success: true,
        cleaned_up_count: cleaned_count,
        message: "Successfully cleaned up #{cleaned_count} expired sessions"
      }
    rescue StandardError => e
      Rails.logger.error "Error cleaning up expired impersonation sessions: #{e.message}"
      
      render json: {
        success: false,
        error: "Failed to cleanup expired sessions: #{e.message}"
      }, status: :internal_server_error
    end
  end

  def render_bad_request(message)
    render json: {
      success: false,
      error: message
    }, status: :bad_request
  end

  def rate_limit_impersonation
    # Rate limiting: Use SystemSettingsService for configurable limits
    max_attempts = SystemSettingsService.rate_limit_setting('impersonation_attempts_per_hour')
    cache_key = "impersonation_attempts:#{current_user.id}"
    attempts = Rails.cache.read(cache_key) || 0
    
    if attempts >= max_attempts
      render json: {
        success: false,
        error: 'Too many impersonation attempts. Please try again later.'
      }, status: :too_many_requests
      return
    end
    
    Rails.cache.write(cache_key, attempts + 1, expires_in: 1.hour)
  end
end