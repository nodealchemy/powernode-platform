# frozen_string_literal: true

# IMP-99e8e4701150 — enable/verify_setup split pending enrolment from
# confirmed 2FA (see User#start_two_factor_setup! / #confirm_two_factor_setup!
# for why); disable/regenerate_backup_codes now require re-authentication via
# a current TOTP code or an unused backup code; backup codes are returned in
# plaintext exactly once (verify_setup / regenerate_backup_codes) and stored
# only as bcrypt digests from then on — GET backup_codes, which used to let a
# caller re-fetch them at will, is gone.
class Api::V1::TwoFactorsController < ApplicationController
  include AuditLogging

  # POST /api/v1/two_factor/enable
  #
  # Starts (or restarts) enrolment: stores a PENDING secret and returns only
  # the QR code and manual entry key. Nothing here activates 2FA or mints
  # backup codes — POST /two_factor/verify_setup does that, once the caller
  # proves the pending secret against their authenticator app.
  def enable
    if current_user.two_factor_enabled?
      return render_error(
        "Two-factor authentication is already enabled for this account",
        :conflict
      )
    end

    begin
      current_user.start_two_factor_setup!
      log_audit_event("two_factor_setup_started", current_user)

      render_success(
        message: "Scan the QR code with your authenticator app, then verify a code to finish enabling two-factor authentication",
        data: {
          qr_code: current_user.two_factor_pending_qr_code,
          manual_entry_key: current_user.two_factor_pending_secret,
          expires_at: current_user.two_factor_pending_expires_at
        }
      )
    rescue StandardError => e
      Rails.logger.error "2FA enable error: #{e.message}"
      render_error(
        "Failed to enable two-factor authentication",
        :internal_server_error
      )
    end
  end

  # POST /api/v1/two_factor/verify_setup
  #
  # Verifies `token` against the PENDING secret. On success this is the
  # moment 2FA actually activates: the confirmed secret is set, backup codes
  # are minted and returned ONCE (never retrievable again), and the pending
  # secret is cleared.
  def verify_setup
    token = params[:token]

    unless token.present?
      return render_error(
        "Verification token is required",
        :bad_request
      )
    end

    if current_user.two_factor_enabled?
      return render_error(
        "Two-factor authentication is already enabled for this account",
        :conflict
      )
    end

    unless current_user.two_factor_pending?
      message = current_user.two_factor_pending_expired? ?
        "Two-factor setup has expired. Please start the setup process again." :
        "Two-factor authentication setup not found. Please start the setup process again."
      return render_error(message, :bad_request)
    end

    backup_codes = current_user.confirm_two_factor_setup!(token)

    if backup_codes
      log_audit_event("two_factor_enabled", current_user)
      log_audit_event("backup_codes_generated", current_user)

      render_success(
        message: "Two-factor authentication has been enabled",
        data: { backup_codes: backup_codes }
      )
    else
      render_error(
        "Invalid verification token. Please try again.",
        :bad_request
      )
    end
  end

  # DELETE /api/v1/two_factor/disable
  #
  # Requires a current TOTP code or an unused backup code — 2FA cannot be
  # turned off by a bare authenticated session alone.
  def disable
    unless current_user.two_factor_enabled?
      return render_error(
        "Two-factor authentication is not enabled for this account",
        :bad_request
      )
    end

    unless current_user.verify_two_factor_or_backup_code(params[:code])
      # 422, deliberately NOT 401: this is an authenticated session (JWT
      # already verified by ApplicationController) supplying a wrong/missing
      # re-auth code, not an expired/invalid token. api.ts's response
      # interceptor treats a 401 as "session expired" and auto-refreshes +
      # replays the request — replaying THIS request with a fresh access
      # token would just fail the same way and could surface as a spurious
      # logout. 422 is "your request was well-formed but semantically wrong"
      # (a bad code), which is exactly this case.
      return render_error(
        "A valid authentication code or backup code is required to disable two-factor authentication",
        :unprocessable_content
      )
    end

    current_user.disable_two_factor!
    log_audit_event("two_factor_disabled", current_user)

    render_success(
      message: "Two-factor authentication has been disabled"
    )
  end

  # GET /api/v1/two_factor/status
  def status
    render_success(
      data: {
        two_factor_enabled: current_user.two_factor_enabled?,
        backup_codes_count: current_user.two_factor_backup_codes_count,
        enabled_at: current_user.two_factor_enabled_at
      }
    )
  end

  # POST /api/v1/two_factor/regenerate_backup_codes
  #
  # Requires a current TOTP code or an unused backup code, same as disable.
  # Returns the new codes in plaintext, once — every previously issued code
  # (used or not) stops working immediately.
  def regenerate_backup_codes
    unless current_user.two_factor_enabled?
      return render_error(
        "Two-factor authentication must be enabled to regenerate backup codes",
        :bad_request
      )
    end

    unless current_user.verify_two_factor_or_backup_code(params[:code])
      # 422, not 401 — see the identical comment in #disable above.
      return render_error(
        "A valid authentication code or backup code is required to regenerate backup codes",
        :unprocessable_content
      )
    end

    backup_codes = current_user.regenerate_backup_codes!
    log_audit_event("backup_codes_generated", current_user)

    render_success(
      message: "Backup codes regenerated successfully",
      data: {
        backup_codes: backup_codes
      }
    )
  end

  private

  def two_factor_params
    params.permit(:token, :code)
  end
end
