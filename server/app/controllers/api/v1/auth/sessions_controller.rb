# frozen_string_literal: true

class Api::V1::Auth::SessionsController < ApplicationController
  include RateLimiting unless Rails.env.development?

  skip_before_action :authenticate_request, only: [ :create, :refresh ]

  # POST /api/v1/sessions
  def create
    user = User.find_by(email: login_params[:email]&.downcase)

    # Check if account is locked before attempting authentication
    if user&.locked?
      # Still increment rate limit for locked accounts
      increment_rate_limit_count if respond_to?(:increment_rate_limit_count)
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
          two_fa_token = JwtService.generate_2fa_token(user)
          
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
            verification_token: two_fa_token[:token],
            message: "Two-factor authentication required. Please provide your verification code."
          }, status: :ok
          return
        end

        # Normal login without 2FA
        tokens = JwtService.generate_tokens(user)
        # record_login! is now called in authenticate method

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
          access_token: tokens[:access_token],
          refresh_token: tokens[:refresh_token],
          expires_at: tokens[:expires_at]
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
      # Authentication failed - increment rate limit counter
      increment_rate_limit_count if respond_to?(:increment_rate_limit_count)

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
    tokens = JwtService.refresh_access_token(params[:refresh_token])

    render json: {
      success: true,
      access_token: tokens[:access_token],
      refresh_token: tokens[:refresh_token],
      expires_at: tokens[:expires_at]
    }, status: :ok
  rescue StandardError => e
    error_message = case e.message
    when /expired/i
                      "Refresh token has expired"
    when /Invalid token type/
                      "Invalid token type"
    when /User not found/
                      "Invalid refresh token"
    else
                      "Invalid refresh token"
    end

    render json: {
      success: false,
      error: error_message,
      message: e.message
    }, status: :unauthorized
  end

  # DELETE /api/v1/sessions
  def destroy
    # Blacklist the access token
    begin
      header = request.headers["Authorization"]
      if header
        token = header.split(" ").last
        JwtService.blacklist_token(token, current_user, reason: "logout")
      end

      # Also blacklist refresh token if provided
      if params[:refresh_token].present?
        JwtService.blacklist_token(params[:refresh_token], current_user, reason: "logout")
      end
    rescue => e
      Rails.logger.error "Error blacklisting tokens: #{e.message}"
      # Continue with logout even if blacklisting fails
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
      tokens = JwtService.verify_2fa_token(verification_token, two_factor_code)
      
      # Get user from verified token
      payload = JwtService.decode(verification_token)
      user = User.find(payload[:user_id])

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
        access_token: tokens[:access_token],
        refresh_token: tokens[:refresh_token],
        expires_at: tokens[:expires_at]
      }

      # Add warning if email is not verified
      unless user.email_verified?
        response_data[:warning] = "Please complete email verification to secure your account"
      end

      render json: response_data, status: :ok
    rescue StandardError => e
      error_message = case e.message
      when /Invalid 2FA code/
        "Invalid two-factor authentication code"
      when /expired/i
        "Verification token has expired"
      when /Invalid token type/
        "Invalid verification token"
      when /User not found/
        "Invalid verification token"
      else
        "Invalid verification token or 2FA code"
      end

      render json: {
        success: false,
        error: error_message
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

  def user_data(user)
    {
      id: user.id,
      email: user.email,
      firstName: user.first_name,
      lastName: user.last_name,
      fullName: user.full_name,
      role: user.role,
      status: user.status,
      emailVerified: user.email_verified?,
      lastLoginAt: user.last_login_at,
      account: account_data(user.account)
    }
  end

  def account_data(account)
    {
      id: account.id,
      name: account.name,
      subdomain: account.subdomain,
      status: account.status
    }
  end

  # Rate limiting configuration
  def should_rate_limit?
    action_name == "create"
  end

  def rate_limit_max_attempts
    6 # Max 6 login attempts per IP
  end

  def rate_limit_window_seconds
    300 # 5 minutes window
  end
end
