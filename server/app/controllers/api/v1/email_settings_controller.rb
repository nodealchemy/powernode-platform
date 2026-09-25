# frozen_string_literal: true

class Api::V1::EmailSettingsController < ApplicationController
  before_action :require_admin_permission

  # GET /api/v1/email_settings
  # Used by worker service to fetch SMTP configuration.
  #
  # SECURITY: only the worker (which actually sends mail) receives the real
  # decrypted secrets, and only when its identity was established
  # CRYPTOGRAPHICALLY. Human/UI callers receive masked indicators so SMTP
  # passwords and provider API keys are never exposed through the admin UI.
  def show
    email_settings = fetch_email_settings(reveal_secrets: worker_may_read_secrets?)

    render_success(email_settings)
  end

  # PUT /api/v1/email_settings
  # Update email configuration
  def update
    begin
      # Handle nested parameter structure from frontend
      email_data = params[:email_settings] || params[:email_setting]&.fetch(:email_settings, nil) || {}

      # secreview §22: validate against the RAW value, before .permit strips it.
      # permit() silently drops a key whose value isn't a permitted scalar
      # (e.g. a JSON array/object for email_verification_expiry_hours), so
      # checking permitted_params afterward would miss exactly the malformed
      # inputs this guard exists to catch.
      raw_params = email_data.is_a?(ActionController::Parameters) ? email_data : ActionController::Parameters.new(email_data)
      if raw_params.key?(:email_verification_expiry_hours) &&
         !AdminSetting.valid_email_verification_expiry_hours?(raw_params[:email_verification_expiry_hours])
        render_error(
          "email_verification_expiry_hours must be an integer between 1 and #{AdminSetting::EMAIL_VERIFICATION_EXPIRY_HOURS_MAX}",
          status: :unprocessable_content
        )
        return
      end

      # Convert to hash and then permit parameters
      permitted_params = if email_data.is_a?(ActionController::Parameters)
        email_data.permit(
          :email_provider, :provider, :smtp_enabled, :smtp_host, :smtp_port, :smtp_username,
          :smtp_password, :smtp_encryption, :smtp_authentication, :smtp_from_address,
          :smtp_from_name, :smtp_domain, :sendgrid_api_key, :ses_access_key,
          :ses_secret_key, :ses_region, :mailgun_api_key, :mailgun_domain,
          :email_verification_expiry_hours, :password_reset_expiry_hours,
          :max_email_retries, :email_retry_delay_seconds
        )
      else
        ActionController::Parameters.new(email_data).permit(
          :email_provider, :provider, :smtp_enabled, :smtp_host, :smtp_port, :smtp_username,
          :smtp_password, :smtp_encryption, :smtp_authentication, :smtp_from_address,
          :smtp_from_name, :smtp_domain, :sendgrid_api_key, :ses_access_key,
          :ses_secret_key, :ses_region, :mailgun_api_key, :mailgun_domain,
          :email_verification_expiry_hours, :password_reset_expiry_hours,
          :max_email_retries, :email_retry_delay_seconds
        )
      end

      ::Admin::SystemSettings.update_email_settings!(permitted_params)

      # Trigger email settings refresh in worker (async operation)
      begin
        WorkerJobService.enqueue_refresh_email_settings
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.warn "Failed to notify worker of email settings change: #{e.message}"
        # Continue - don't fail the update if worker notification fails
        # The worker service will pick up changes on next polling cycle
      rescue StandardError => e
        Rails.logger.error "Unexpected error notifying worker service: #{e.message}"
        # Continue - worker service unavailability shouldn't block settings updates
      end

      render_success({
        message: "Email settings updated successfully"
      })
    rescue StandardError => e
      Rails.logger.error "Failed to update email settings: #{e.message}"
      render_error(
        "Failed to update email settings",
        status: :unprocessable_content
      )
    end
  end

  # POST /api/v1/email_settings/test
  # Test email configuration
  def test
    test_email = params[:email]

    unless test_email.present?
      render_error("Email address is required", status: :unprocessable_content)
      return
    end

    # Send test email request to worker service
    begin
      # Use WorkerJobService to enqueue the test email job
      WorkerJobService.enqueue_test_email(test_email)

      render_success({
        message: "Test email queued for delivery to #{test_email}"
      })
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to queue test email: #{e.message}"
      render_error(
        "Failed to queue test email. Please check worker service status.",
        status: :service_unavailable
      )
    rescue StandardError => e
      Rails.logger.error "Failed to queue test email: #{e.message}"
      render_error(
        "Failed to queue test email. Please check worker service status.",
        status: :service_unavailable
      )
    end
  end

  private

  def fetch_email_settings(reveal_secrets:)
    settings = ::Admin::SystemSettings.email_settings

    settings.merge(
      smtp_password: secret_field(settings[:smtp_password], reveal_secrets),
      smtp_password_set: settings[:smtp_password].present?,
      sendgrid_api_key: secret_field(settings[:sendgrid_api_key], reveal_secrets),
      sendgrid_api_key_set: settings[:sendgrid_api_key].present?,
      ses_secret_key: secret_field(settings[:ses_secret_key], reveal_secrets),
      ses_secret_key_set: settings[:ses_secret_key].present?,
      mailgun_api_key: secret_field(settings[:mailgun_api_key], reveal_secrets),
      mailgun_api_key_set: settings[:mailgun_api_key].present?
    )
  end

  # Whether THIS caller may receive the decrypted SMTP password and provider
  # API keys.
  #
  # `current_worker.present?` is NOT sufficient. Worker identity can also be
  # established from `X-Forwarded-Tls-Client-Cert-Info` alone
  # (Security::MtlsTrust#verify_request's no-PEM branch), which is a header the
  # client controls unless the reverse proxy strips it. Core attaches
  # Core::IngressConfigWriter::STRIP_FORWARDED_CLIENT_CERT_MW to the backend
  # routers it writes itself, but on a composed hub the per-account routers come
  # from the system extension's ACME writer, which carries no strip AND outranks
  # the host-login routers on Traefik's rule-length priority. The strip is
  # therefore NOT a property core can prove. Composed with a worker CN that may
  # be a published constant (Workers::EnsureSystemWorker::DEV_SENTINEL_NODE_ID,
  # retained by a dev-bootstrapped database until its first non-development
  # boot revokes it), "any worker" would hand
  # plaintext mail credentials to an unauthenticated caller.
  #
  # So the reveal is gated on an identity the caller cannot forge — a
  # signature-checked worker JWT, or a client-cert leaf verified against our own
  # CA (the posture the proxy produces with passTLSClientCert pem=true). Defence
  # in depth: this holds even when the forged header survives the ingress.
  #
  # ACCEPTED RESIDUAL: a forwarded-CN-only worker still authenticates and still
  # reads the NON-secret delivery config (smtp_host, smtp_username,
  # smtp_from_address, provider, and the `*_set` booleans) — the same surface a
  # human admin sees. Only the four secret values are withheld.
  def worker_may_read_secrets?
    return true if worker_identity_cryptographically_verified?

    # A worker that reached us on the unverifiable path gets the mask. That is
    # the safe answer, but it is also indistinguishable from a misconfigured
    # proxy: if this hub's pass-tls middleware does not forward the cert PEM,
    # the REAL worker lands here and mail loses its SMTP password with no other
    # symptom. Log it so the degradation is diagnosable instead of silent.
    if current_worker.present?
      Rails.logger.warn(
        "[EmailSettings] masking secrets for worker #{current_worker.id}: identity came from the " \
        "forwarded-CN header with no verifiable client cert. If this is the real worker, the ingress " \
        "is not forwarding the client-cert PEM (passTLSClientCert pem=true) and mail delivery will " \
        "lose its credentials."
      )
    end

    false
  end

  # Return the real secret only when the caller is allowed to see it (a
  # cryptographically identified worker, which sends the mail). For UI callers
  # and unverifiable worker identities, never echo the value — return "".
  def secret_field(value, reveal)
    reveal ? value : ""
  end

  def require_admin_permission
    # Allow admin users with proper permission
    return if current_user&.has_permission?("admin.settings.email")

    # Allow any authenticated worker (workers have system-level access)
    return if current_worker.present?

    render_error("Access denied. Email settings management required.", status: :forbidden)
  end
end
