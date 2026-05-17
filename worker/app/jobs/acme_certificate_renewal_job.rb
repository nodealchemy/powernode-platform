# frozen_string_literal: true

# AcmeCertificateRenewalJob — periodic ACME cert renewal sweep.
#
# Ticks every 6 hours via Sidekiq cron. POSTs to the server's
# worker_api endpoint which invokes Acme::RenewalSweepService.run!.
# That service:
#
#   - Renews certs in `valid` state whose expires_at is within 30 days
#   - Retries cert issuance for certs in `failed` state past the
#     30-minute cooldown
#
# The cooldown is what makes 6h ticks safe: a previously-failed cert
# only retries once per tick at most, and never inside the cooldown
# window, so ACME rate limits stay clear of tight-loop retries.
#
# Plan reference: Decentralized Federation §J + P2.5.5.
class AcmeCertificateRenewalJob < BaseJob
  sidekiq_options queue: :system, retry: 1

  def execute(args = {})
    log_info "[AcmeCertificateRenewalJob] Starting ACME renewal sweep"

    response = api_client.post("/api/v1/system/worker_api/acme/renewal_sweep", {})

    if response["success"]
      data = response["data"] || {}
      log_info "[AcmeCertificateRenewalJob] sweep complete: " \
               "renewed=#{data['renewed_count']} failed=#{data['failed_count']} " \
               "skipped=#{data['skipped_count']}"
      data
    else
      log_warn "[AcmeCertificateRenewalJob] sweep API returned non-success: #{response.inspect}"
      { renewed: 0, failed: 0, error: response["error"] }
    end
  rescue StandardError => e
    log_error "[AcmeCertificateRenewalJob] sweep failed", e
    raise
  end
end
