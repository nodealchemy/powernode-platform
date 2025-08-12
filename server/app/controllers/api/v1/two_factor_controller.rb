# frozen_string_literal: true

class Api::V1::TwoFactorController < ApplicationController
  # POST /api/v1/two_factor/enable
  def enable
    if current_user.two_factor_enabled?
      render json: {
        success: false,
        error: "Two-factor authentication is already enabled for this account"
      }, status: :conflict
      return
    end

    begin
      secret = current_user.enable_two_factor!
      
      render json: {
        success: true,
        message: "Two-factor authentication has been enabled",
        qr_code: current_user.two_factor_qr_code,
        manual_entry_key: secret,
        backup_codes: current_user.two_factor_backup_codes
      }, status: :ok
    rescue => e
      Rails.logger.error "2FA enable error: #{e.message}"
      render json: {
        success: false,
        error: "Failed to enable two-factor authentication"
      }, status: :internal_server_error
    end
  end

  # POST /api/v1/two_factor/verify_setup
  def verify_setup
    token = params[:token]
    
    unless token.present?
      render json: {
        success: false,
        error: "Verification token is required"
      }, status: :bad_request
      return
    end

    unless current_user.two_factor_secret.present?
      render json: {
        success: false,
        error: "Two-factor authentication setup not found. Please start the setup process again."
      }, status: :bad_request
      return
    end

    if current_user.verify_two_factor_token(token)
      # 2FA setup is verified, user can now use it for login
      render json: {
        success: true,
        message: "Two-factor authentication setup verified successfully"
      }, status: :ok
    else
      render json: {
        success: false,
        error: "Invalid verification token. Please try again."
      }, status: :bad_request
    end
  end

  # DELETE /api/v1/two_factor/disable
  def disable
    unless current_user.two_factor_enabled?
      render json: {
        success: false,
        error: "Two-factor authentication is not enabled for this account"
      }, status: :bad_request
      return
    end

    current_user.disable_two_factor!

    render json: {
      success: true,
      message: "Two-factor authentication has been disabled"
    }, status: :ok
  end

  # GET /api/v1/two_factor/status
  def status
    render json: {
      success: true,
      two_factor_enabled: current_user.two_factor_enabled?,
      backup_codes_count: current_user.two_factor_backup_codes.size,
      enabled_at: current_user.two_factor_enabled_at
    }, status: :ok
  end

  # POST /api/v1/two_factor/regenerate_backup_codes
  def regenerate_backup_codes
    unless current_user.two_factor_enabled?
      render json: {
        success: false,
        error: "Two-factor authentication must be enabled to regenerate backup codes"
      }, status: :bad_request
      return
    end

    backup_codes = current_user.regenerate_backup_codes!

    render json: {
      success: true,
      message: "Backup codes regenerated successfully",
      backup_codes: backup_codes
    }, status: :ok
  end

  # GET /api/v1/two_factor/backup_codes
  def backup_codes
    unless current_user.two_factor_enabled?
      render json: {
        success: false,
        error: "Two-factor authentication is not enabled"
      }, status: :bad_request
      return
    end

    render json: {
      success: true,
      backup_codes: current_user.two_factor_backup_codes,
      generated_at: current_user.two_factor_backup_codes_generated_at
    }, status: :ok
  end

  private

  def two_factor_params
    params.permit(:token)
  end
end