# frozen_string_literal: true

# M2 Self-Serve Hardening (BYOC) — onboarding bookkeeping endpoint.
#
# The FirstRunWizard polls #status to decide whether to surface the
# BYOC flow on each load; #complete flips the per-account flag and
# kicks off the System extension's per-account template seed body
# (idempotent, safe to re-run).
#
# Permission model: any authenticated user inside the account can
# read or complete their own account's onboarding — this is operator-
# bootstrap UX, not a privileged operation. Per-permission gates on
# downstream provider/credential CRUD live on the System extension's
# ProviderCredentialsController.
class Api::V1::OnboardingController < ApplicationController
  # GET /api/v1/onboarding/status
  def status
    account = current_user.account
    render_success(data: status_payload(account))
  end

  # POST /api/v1/onboarding/complete
  # Body (optional): { provider_credential_id, provider_type } — the
  # FirstRunWizard sends the cred it just created so the backend can
  # record which provider closed the loop. Both fields are optional
  # (skip path sends nothing); they're stashed in metadata for audit.
  def complete
    account = current_user.account

    unless account.onboarding_completed?
      account.mark_onboarding_complete!(
        provider_credential_id: params[:provider_credential_id].presence,
        provider_type: params[:provider_type].presence
      )
      seed_templates_safely(account)
    end

    render_success(data: status_payload(account.reload))
  end

  private

  def status_payload(account)
    {
      completed: account.onboarding_completed?,
      has_credentials: account_has_active_credentials?(account),
      completed_at: account.onboarding_completed_at&.iso8601
    }
  end

  # System extension may be disabled in core mode — guard the
  # association lookup so the endpoint stays usable for self-hosted
  # installs that haven't pulled the System extension.
  def account_has_active_credentials?(account)
    return false unless account.respond_to?(:system_provider_credentials)
    account.system_provider_credentials.where(is_active: true).exists?
  end

  # Account.after_create_commit already ran AccountBootstrapService,
  # but operators landing on a brand-new install before the hook fired
  # (or after a failed first run) should still get the catalog seeded
  # when they finish the wizard. seed_templates_for is idempotent.
  def seed_templates_safely(account)
    return unless defined?(::System::AccountBootstrapService)
    ::System::AccountBootstrapService.seed_templates_for(account)
  rescue StandardError => e
    Rails.logger.error(
      "[OnboardingController#complete] seed_templates_for failed for account #{account.id}: " \
      "#{e.class}: #{e.message}"
    )
  end
end
