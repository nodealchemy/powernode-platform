# frozen_string_literal: true

class Api::V1::TwoFactorsController < ApplicationController
  # POST /api/v1/two_factor/enable
  def enable
    if current_user.two_factor_enabled?
      return render_error(
        "Two-factor authentication is already enabled for this account",
        :conflict
      )
    end

    begin
      secret = current_user.enable_two_factor!

      render_success(
        message: "Two-factor authentication has been enabled",
        data: {
          qr_code: current_user.two_factor_qr_code,
          manual_entry_key: secret,
          backup_codes: current_user.two_factor_backup_codes
        }
      )
    rescue => e
      Rails.logger.error "2FA enable error: #{e.message}"
      render_error(
        "Failed to enable two-factor authentication",
        :internal_server_error
      )
    end
  end

  # POST /api/v1/two_factor/verify_setup
  def verify_setup
    token = params[:token]

    unless token.present?
      return render_error(
        "Verification token is required",
        :bad_request
      )
    end

    unless current_user.two_factor_secret.present?
      return render_error(
        "Two-factor authentication setup not found. Please start the setup process again.",
        :bad_request
      )
    end

    if current_user.verify_two_factor_token(token)
      # 2FA setup is verified, user can now use it for login
      render_success(
        message: "Two-factor authentication setup verified successfully"
      )
    else
      render_error(
        "Invalid verification token. Please try again.",
        :bad_request
      )
    end
  end

  # DELETE /api/v1/two_factor/disable
  def disable
    unless current_user.two_factor_enabled?
      return render_error(
        "Two-factor authentication is not enabled for this account",
        :bad_request
      )
    end

    current_user.disable_two_factor!

    render_success(
      message: "Two-factor authentication has been disabled"
    )
  end

  # GET /api/v1/two_factor/status
  def status
    render_success(
      data: {
        two_factor_enabled: current_user.two_factor_enabled?,
        backup_codes_count: current_user.two_factor_backup_codes.size,
        enabled_at: current_user.two_factor_enabled_at
      }
    )
  end

  # POST /api/v1/two_factor/regenerate_backup_codes
  def regenerate_backup_codes
    unless current_user.two_factor_enabled?
      return render_error(
        "Two-factor authentication must be enabled to regenerate backup codes",
        :bad_request
      )
    end

    backup_codes = current_user.regenerate_backup_codes!

    render_success(
      message: "Backup codes regenerated successfully",
      data: {
        backup_codes: backup_codes
      }
    )
  end

  # GET /api/v1/two_factor/backup_codes
  def backup_codes
    unless current_user.two_factor_enabled?
      return render_error(
        "Two-factor authentication is not enabled",
        :bad_request
      )
    end

    render_success(
      data: {
        backup_codes: current_user.two_factor_backup_codes,
        generated_at: current_user.two_factor_backup_codes_generated_at
      }
    )
  end

  private

  def two_factor_params
    params.permit(:token)
  end
end
