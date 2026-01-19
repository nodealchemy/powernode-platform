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
      return render_error(
        "Your account is temporarily locked due to multiple failed login attempts. Please try again later.",
        :unauthorized
      )
    end

    if user&.authenticate(login_params[:password])
      if user.active? && user.account.active?
        # Check if user has 2FA enabled
        if user.two_factor_enabled?
          # Generate 2FA verification token
          metadata = {
            ip: request.remote_ip,
            user_agent: request.user_agent
          }
          two_fa_result = Security::JwtService.generate_2fa_token(user, metadata: metadata)

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

          render_success({
            requires_2fa: true,
            verification_token: two_fa_result[:token]
          },
            message: "Two-factor authentication required. Please provide your verification code."
          )
          return
        end

        # Normal login without 2FA - create JWT tokens
        metadata = {
          ip: request.remote_ip,
          user_agent: request.user_agent
        }

        token_result = Security::JwtService.generate_user_tokens(user, metadata: metadata)
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
          access_token: token_result[:access_token],
          refresh_token: token_result[:refresh_token],
          expires_at: token_result[:expires_at]
        }

        # Add warning if email is not verified
        unless user.email_verified?
          response_data[:warning] = "Please complete email verification to secure your account"
        end

        render_success({
          user: response_data[:user],
          account: response_data[:account],
          access_token: response_data[:access_token],
          refresh_token: response_data[:refresh_token],
          expires_at: response_data[:expires_at]
        }.merge(response_data[:warning] ? { warning: response_data[:warning] } : {}))
      else
        error_message = if user.status == "suspended"
          "Account is suspended"
        elsif user.status == "inactive"
          "Account is inactive"
        else
          "Account access denied"
        end

        render_error(error_message, status: :unauthorized)
      end
    else

      # Failed login attempt is already recorded in User#authenticate
      user.reload if user # Reload to get updated failed_login_attempts

      if user&.locked?
        render_error(
          "Your account has been temporarily locked due to multiple failed login attempts. Please try again later.",
          :unauthorized
        )
      else
        render_error("Invalid email or password", status: :unauthorized)
      end
    end
  end

  # POST /api/v1/sessions/refresh
  def refresh
    refresh_token = params[:refresh_token]
    return render_error("Refresh token required", status: :bad_request) unless refresh_token

    begin
      # Use JWT service to refresh the token
      token_result = Security::JwtService.refresh_access_token(refresh_token)

      render_success({
        access_token: token_result[:access_token],
        refresh_token: token_result[:refresh_token],
        expires_at: token_result[:expires_at]
      }
      )
    rescue StandardError => e
      Rails.logger.error "Token refresh error: #{e.message}"
      Rails.logger.error "Token refresh backtrace: #{e.backtrace.join("\n")}"

      # Check if this is a permissions change that requires re-login
      if e.message.include?("Permissions changed")
        render_error("Authentication required - please log in again", status: :unauthorized)
      else
        render_error("Invalid or expired refresh token", status: :unauthorized)
      end
    end
  end

  # DELETE /api/v1/sessions
  def destroy
    # Blacklist the current access token and any provided refresh token
    begin
      # Get current token from authorization header
      if request.headers["Authorization"]
        current_token = request.headers["Authorization"].split(" ").last
        Security::JwtService.blacklist_token(current_token, reason: "logout", user_id: current_user.id)
      end

      # Also blacklist refresh token if provided
      if params[:refresh_token].present?
        Security::JwtService.blacklist_token(params[:refresh_token], reason: "logout", user_id: current_user.id)
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

    render_success(message: "Successfully logged out")
  end

  # GET /api/v1/sessions/current
  def current
    render_success({
      user: user_data(current_user)
    })
  end

  # POST /api/v1/auth/verify-2fa
  def verify_2fa
    verification_token = params[:verification_token]
    two_factor_code = params[:code]

    unless verification_token.present?
      return render_error(
        "Verification token is required",
        :bad_request
      )
    end

    unless two_factor_code.present?
      return render_error(
        "Two-factor authentication code is required",
        :bad_request
      )
    end

    begin
      # Use JWT service to verify 2FA and get full tokens
      token_result = Security::JwtService.verify_2fa_token(verification_token, two_factor_code)

      # Get user from the token result (user info should be in the JWT)
      payload = Security::JwtService.decode(token_result[:access_token])
      user = User.find(payload[:sub])
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
        access_token: token_result[:access_token],
        refresh_token: token_result[:refresh_token],
        expires_at: token_result[:expires_at]
      }

      # Add warning if email is not verified
      unless user.email_verified?
        response_data[:warning] = "Please complete email verification to secure your account"
      end

      render_success({
        user: response_data[:user],
        account: response_data[:account],
        access_token: response_data[:access_token],
          refresh_token: response_data[:refresh_token],
          expires_at: response_data[:expires_at]
        }.merge(response_data[:warning] ? { warning: response_data[:warning] } : {})
      )
    rescue StandardError => e
      Rails.logger.error "2FA verification error: #{e.message}"
      render_error(
        "Authentication verification failed",
        :unauthorized
      )
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
