# frozen_string_literal: true

class Api::V1::Admin::UsersController < ApplicationController
  before_action :require_admin!
  before_action :find_user, only: [:show, :impersonate]
  before_action :rate_limit_impersonation, only: [:impersonate]

  # GET /api/v1/admin/users
  def index
    # For system admin, return ALL users across ALL accounts
    @users = User.includes(:account).order(:created_at)
    render json: {
      success: true,
      data: @users.map { |user| user_summary(user) }
    }
  end

  # GET /api/v1/admin/users/:id
  def show
    render json: {
      success: true,
      data: user_summary(@user)
    }
  end

  # POST /api/v1/admin/users/:id/impersonate
  def impersonate
    service = ImpersonationService.new(current_user)
    
    begin
      token = service.start_impersonation(
        target_user_id: @user.id,
        reason: params[:reason],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      render json: {
        success: true,
        message: 'Impersonation started successfully',
        data: {
          token: token,
          target_user: user_summary(@user),
          expires_at: (Time.current + ImpersonationSession::MAX_SESSION_DURATION).iso8601
        }
      }, status: :created
    rescue ImpersonationService::Error => e
      render json: {
        success: false,
        error: e.message,
        code: e.error_code
      }, status: e.http_status
    rescue => e
      Rails.logger.error "Impersonation error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      render json: {
        success: false,
        error: 'Failed to start impersonation',
        code: 'impersonation_failed'
      }, status: :internal_server_error
    end
  end

  private

  def find_user
    # For admin operations, find user across all accounts
    @user = User.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found('User not found')
  end

  def rate_limit_impersonation
    cache_key = "impersonation_attempts:#{current_user.id}"
    attempts = Rails.cache.read(cache_key) || 0
    
    if attempts >= 5
      render json: {
        success: false,
        error: 'Too many impersonation attempts. Please try again later.',
        code: 'rate_limit_exceeded'
      }, status: :too_many_requests
      return
    end
    
    Rails.cache.write(cache_key, attempts + 1, expires_in: 1.hour)
  end

  def user_summary(user)
    {
      id: user.id,
      email: user.email,
      full_name: "#{user.first_name} #{user.last_name}".strip,
      role: user.role,
      status: user.status,
      email_verified: user.email_verified?,
      last_login_at: user.last_login_at&.iso8601,
      created_at: user.created_at.iso8601,
      account: {
        id: user.account.id,
        name: user.account.name
      }
    }
  end
end