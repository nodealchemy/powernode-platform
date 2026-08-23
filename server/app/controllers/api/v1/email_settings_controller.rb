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

      # Update each setting (handle both provider and email_provider)
      permitted_params.each do |key, value|
        # Normalize provider key
        setting_key = key == "provider" ? "email_provider" : key

        if setting_key.ends_with?("_password") || setting_key.ends_with?("_api_key") || setting_key.ends_with?("_secret_key")
          # Encrypt sensitive values
          AdminSetting.set("#{setting_key}_encrypted", encrypt_password(value))
        else
          AdminSetting.set(setting_key, value)
        end
      end

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
    smtp_password   = decrypt_password(AdminSetting.get("smtp_password_encrypted", ""))
    sendgrid_api_key = decrypt_password(AdminSetting.get("sendgrid_api_key_encrypted", ""))
    ses_secret_key  = decrypt_password(AdminSetting.get("ses_secret_key_encrypted", ""))
    mailgun_api_key = decrypt_password(AdminSetting.get("mailgun_api_key_encrypted", ""))

    {
      provider: AdminSetting.get("email_provider", "smtp"),
      smtp_enabled: AdminSetting.get("smtp_enabled", false),
      smtp_host: AdminSetting.get("smtp_host", ""),
      smtp_port: AdminSetting.get("smtp_port", 587),
      smtp_username: AdminSetting.get("smtp_username", ""),
      smtp_password: secret_field(smtp_password, reveal_secrets),
      smtp_password_set: smtp_password.present?,
      smtp_encryption: AdminSetting.get("smtp_encryption", "tls"),
      smtp_authentication: AdminSetting.get("smtp_authentication", true),
      smtp_from_address: AdminSetting.get("smtp_from_address", "noreply@powernode.dev"),
      smtp_from_name: AdminSetting.get("smtp_from_name", "Powernode"),
      smtp_domain: AdminSetting.get("smtp_domain", "powernode.dev"),

      # Additional provider settings
      sendgrid_api_key: secret_field(sendgrid_api_key, reveal_secrets),
      sendgrid_api_key_set: sendgrid_api_key.present?,
      ses_access_key: AdminSetting.get("ses_access_key", ""),
      ses_secret_key: secret_field(ses_secret_key, reveal_secrets),
      ses_secret_key_set: ses_secret_key.present?,
      ses_region: AdminSetting.get("ses_region", "us-east-1"),
      mailgun_api_key: secret_field(mailgun_api_key, reveal_secrets),
      mailgun_api_key_set: mailgun_api_key.present?,
      mailgun_domain: AdminSetting.get("mailgun_domain", ""),

      # Email behavior settings
      email_verification_expiry_hours: AdminSetting.get("email_verification_expiry_hours", 24),
      password_reset_expiry_hours: AdminSetting.get("password_reset_expiry_hours", 2),
      max_email_retries: AdminSetting.get("max_email_retries", 3),
      email_retry_delay_seconds: AdminSetting.get("email_retry_delay_seconds", 60)
    }
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

  def decrypt_password(encrypted_value)
    return "" if encrypted_value.blank?

    ::Security::CredentialEncryptionService.decrypt_value(encrypted_value).to_s
  rescue ::Security::CredentialEncryptionService::DecryptionError
    # Backward compatibility: values written before encryption was added were
    # stored as plaintext and cannot be decrypted. Treat them as their literal
    # value so existing configs keep sending mail until next save re-encrypts.
    encrypted_value
  end

  def encrypt_password(value)
    return "" if value.blank?

    ::Security::CredentialEncryptionService.encrypt_value(value)
  end

  def require_admin_permission
    # Allow admin users with proper permission
    return if current_user&.has_permission?("admin.settings.email")

    # Allow any authenticated worker (workers have system-level access)
    return if current_worker.present?

    render_error("Access denied. Email settings management required.", status: :forbidden)
  end
end
