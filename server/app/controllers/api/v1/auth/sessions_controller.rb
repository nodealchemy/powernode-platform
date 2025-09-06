# frozen_string_literal: true

class Api::V1::Auth::SessionsController < ApplicationController
  # Rate limiting is now included in ApplicationController
  include UserSerialization

  skip_before_action :authenticate_request, only: [ :create, :refresh ]

  # POST /api/v1/sessions
  def create
    user = User.find_by(email: login_params[:email]&.downcase)

    # Check if account is locked before attempting authentication
    if user&.locked?
      render json: {
        success: false,
        error: "Your account is temporarily locked due to multiple failed login attempts. Please try again later."
      }, status: :unauthorized
      return
    end

    if user&.authenticate(login_params[:password])
      if user.active? && user.account.active?
        # Check if user has 2FA enabled
        if user.two_factor_enabled?
          # Generate 2FA verification token
          two_fa_result = UserToken.create_token_for_user(user, type: '2fa', expires_in: 10.minutes)
          
          # Create partial audit log entry
          AuditLog.create!(
            user: user,
            account: user.account,
            action: "login_2fa_required",
            resource_type: "User",
            resource_id: user.id,
            source: "api",
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            metadata: { login_method: "password", step: "2fa_required" }
          )

          render json: {
            success: true,
            requires_2fa: true,
            verification_token: two_fa_result[:token],
            message: "Two-factor authentication required. Please provide your verification code."
          }, status: :ok
          return
        end

        # Normal login without 2FA - create traditional tokens
        access_result = UserToken.create_token_for_user(user, type: 'access')
        refresh_result = UserToken.create_token_for_user(user, type: 'refresh', expires_in: 7.days)
        user.record_login!

        # Create audit log entry
        AuditLog.create!(
          user: user,
          account: user.account,
          action: "login",
          resource_type: "User",
          resource_id: user.id,
          source: "api",
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          metadata: { login_method: "password" }
        )

        response_data = {
          success: true,
          user: user_data(user),
          account: account_data(user.account),
          access_token: access_result[:token],
          refresh_token: refresh_result[:token],
          expires_at: access_result[:user_token].expires_at
        }

        # Add warning if email is not verified
        unless user.email_verified?
          response_data[:warning] = "Please complete email verification to secure your account"
        end

        render json: response_data, status: :ok
      else
        error_message = if user.status == "suspended"
          "Account is suspended"
        elsif user.status == "inactive"
          "Account is inactive"
        else
          "Account access denied"
        end

        render json: {
          success: false,
          error: error_message
        }, status: :unauthorized
      end
    else

      # Failed login attempt is already recorded in User#authenticate
      user.reload if user # Reload to get updated failed_login_attempts

      if user&.locked?
        render json: {
          success: false,
          error: "Your account has been temporarily locked due to multiple failed login attempts. Please try again later."
        }, status: :unauthorized
      else
        render json: {
          success: false,
          error: "Invalid email or password"
        }, status: :unauthorized
      end
    end
  end

  # POST /api/v1/sessions/refresh
  def refresh
    refresh_token = params[:refresh_token]
    return render_error("Refresh token required", status: :bad_request) unless refresh_token

    begin
      # Find and validate refresh token
      user_token = UserToken.find_by_token(refresh_token)
      unless user_token&.active? && user_token&.token_type == 'refresh'
        return render_error("Invalid or expired refresh token", status: :unauthorized)
      end

      # Generate new access token using the refresh token
      new_access_result = user_token.refresh!
      unless new_access_result
        return render_error("Unable to refresh token", status: :unauthorized)
      end

      render json: {
        success: true,
        access_token: new_access_result[:token],
        refresh_token: refresh_token, # Keep same refresh token
        expires_at: new_access_result[:user_token].expires_at
      }, status: :ok
    rescue StandardError => e
      Rails.logger.error "Token refresh error: #{e.message}"
      Rails.logger.error "Token refresh backtrace: #{e.backtrace.join("\n")}"
      render_error("Invalid refresh token", status: :unauthorized)
    end
  end

  # DELETE /api/v1/sessions
  def destroy
    # Revoke the current access token and any provided refresh token
    begin
      # Revoke current access token if available
      if current_user_token
        current_user_token.revoke!(reason: "logout")
      end

      # Also revoke refresh token if provided
      if params[:refresh_token].present?
        refresh_token = UserToken.find_by_token(params[:refresh_token])
        refresh_token&.revoke!(reason: "logout")
      end
    rescue => e
      Rails.logger.error "Error revoking tokens: #{e.message}"
      # Continue with logout even if revoking fails
    end

    # Create audit log entry for logout
    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: "logout",
      resource_type: "User",
      resource_id: current_user.id,
      source: "api",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: { logout_method: "api" }
    )

    render json: {
      success: true,
      message: "Successfully logged out"
    }, status: :ok
  end

  # GET /api/v1/sessions/current
  def current
    render json: {
      success: true,
      user: user_data(current_user)
    }, status: :ok
  end

  # POST /api/v1/auth/verify-2fa
  def verify_2fa
    verification_token = params[:verification_token]
    two_factor_code = params[:code]

    unless verification_token.present?
      render json: {
        success: false,
        error: "Verification token is required"
      }, status: :bad_request
      return
    end

    unless two_factor_code.present?
      render json: {
        success: false,
        error: "Two-factor authentication code is required"
      }, status: :bad_request
      return
    end

    begin
      # Find and validate 2FA token
      two_fa_token = UserToken.find_by_token(verification_token)
      unless two_fa_token&.active? && two_fa_token.token_type == '2fa'
        return render json: {
          success: false,
          error: "Invalid or expired verification token"
        }, status: :unauthorized
      end

      user = two_fa_token.user
      
      # Verify the 2FA code
      unless user.verify_two_factor_token(two_factor_code)
        return render json: {
          success: false,
          error: "Invalid two-factor authentication code"
        }, status: :unauthorized
      end

      # Revoke the 2FA token (it's now used)
      two_fa_token.revoke!(reason: "2fa_used")

      # Generate access and refresh tokens
      access_result = UserToken.create_token_for_user(user, type: 'access')
      refresh_result = UserToken.create_token_for_user(user, type: 'refresh', expires_in: 7.days)
      user.record_login!

      # Create successful login audit log entry
      AuditLog.create!(
        user: user,
        account: user.account,
        action: "login",
        resource_type: "User",
        resource_id: user.id,
        source: "api",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { login_method: "password_2fa", step: "2fa_verified" }
      )

      response_data = {
        success: true,
        user: user_data(user),
        account: account_data(user.account),
        access_token: access_result[:token],
        refresh_token: refresh_result[:token],
        expires_at: access_result[:user_token].expires_at
      }

      # Add warning if email is not verified
      unless user.email_verified?
        response_data[:warning] = "Please complete email verification to secure your account"
      end

      render json: response_data, status: :ok
    rescue StandardError => e
      Rails.logger.error "2FA verification error: #{e.message}"
      render json: {
        success: false,
        error: "Authentication verification failed"
      }, status: :unauthorized
    end
  end

  private

  def login_params
    # Handle both nested session params and direct params for backward compatibility
    if params[:session].present?
      params.require(:session).permit(:email, :password)
    else
      params.permit(:email, :password)
    end
  end

  # user_data and account_data methods are now provided by UserSerialization concern

  # Rate limiting configuration
  def should_rate_limit?
    action_name == "create"
  end

end
