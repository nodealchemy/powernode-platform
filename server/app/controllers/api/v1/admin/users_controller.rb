# frozen_string_literal: true

class Api::V1::Admin::UsersController < ApplicationController
  before_action :require_admin!
  before_action :find_user, only: [:show, :update, :destroy, :impersonate]
  before_action :find_account, only: [:create]
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

  # POST /api/v1/admin/users
  def create
    @user = @account.users.build(user_params)
    
    # Set default role if not specified
    @user.role ||= @account.plan&.default_role || 'member'
    
    # Generate temporary password
    temp_password = SecureRandom.alphanumeric(12)
    @user.password = temp_password
    @user.password_confirmation = temp_password
    
    if @user.save
      # Send welcome email with login instructions
      UserMailer.welcome_user(@user, temp_password).deliver_later
      
      AuditLog.create!(
        account: @account,
        user: current_user,
        action: 'user.created',
        details: "Created user #{@user.email} in account #{@account.name}",
        ip_address: request.remote_ip
      )
      
      render json: {
        success: true,
        message: 'User created successfully',
        data: user_summary(@user)
      }, status: :created
    else
      render json: {
        success: false,
        error: 'Failed to create user',
        validation_errors: @user.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # PATCH/PUT /api/v1/admin/users/:id
  def update
    # System admins can update any user's basic info but not change admin status
    update_params = user_params
    
    # Prevent system admin role changes unless super admin
    if update_params[:role] == 'admin' && !current_user.super_admin?
      return render json: {
        success: false,
        error: 'You do not have permission to assign admin role'
      }, status: :forbidden
    end
    
    # Prevent users from removing their own admin status
    if @user.id == current_user.id && update_params[:role] && update_params[:role] != 'admin'
      return render json: {
        success: false,
        error: 'You cannot change your own role'
      }, status: :forbidden
    end

    if @user.update(update_params)
      AuditLog.create!(
        account: @user.account,
        user: current_user,
        action: 'user.updated',
        details: "Updated user #{@user.email}",
        ip_address: request.remote_ip
      )
      
      render json: {
        success: true,
        message: 'User updated successfully',
        data: user_summary(@user)
      }
    else
      render json: {
        success: false,
        error: 'Failed to update user',
        validation_errors: @user.errors.full_messages
      }, status: :unprocessable_content
    end
  end

  # DELETE /api/v1/admin/users/:id
  def destroy
    # Prevent self-deletion
    if @user.id == current_user.id
      return render json: {
        success: false,
        error: 'You cannot delete your own account'
      }, status: :forbidden
    end
    
    # Prevent deletion of account owners unless there's another owner
    if @user.owner?
      other_owners = @user.account.users.where(role: 'owner').where.not(id: @user.id)
      if other_owners.empty?
        return render json: {
          success: false,
          error: 'Cannot delete the only account owner. Transfer ownership first.'
        }, status: :forbidden
      end
    end
    
    account = @user.account
    user_email = @user.email
    
    if @user.destroy
      AuditLog.create!(
        account: account,
        user: current_user,
        action: 'user.deleted',
        details: "Deleted user #{user_email}",
        ip_address: request.remote_ip
      )
      
      render json: {
        success: true,
        message: 'User deleted successfully'
      }
    else
      render json: {
        success: false,
        error: 'Failed to delete user',
        validation_errors: @user.errors.full_messages
      }, status: :unprocessable_content
    end
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
  rescue ActiveRecord::RecordNotFound => e
    render_not_found(e)
  end

  def find_account
    account_id = params[:account_id]
    return render_bad_request('Account ID required') unless account_id
    
    @account = Account.find(account_id)
  rescue ActiveRecord::RecordNotFound => e
    render_not_found(e)
  end

  def user_params
    params.require(:user).permit(
      :email, :first_name, :last_name, :role, :phone_number,
      :timezone, :status
    )
  end

  def rate_limit_impersonation
    max_attempts = SystemSettingsService.rate_limit_setting('impersonation_attempts_per_hour')
    cache_key = "impersonation_attempts:#{current_user.id}"
    attempts = Rails.cache.read(cache_key) || 0
    
    if attempts >= max_attempts
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