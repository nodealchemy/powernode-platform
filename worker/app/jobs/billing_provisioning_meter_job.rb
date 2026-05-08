# frozen_string_literal: true

require_relative 'base_job'

# Self-Serve Hardening M1 — hourly rollup pass for the provisioning meter.
#
# Walks Billing::ProvisioningUsageRecord.pending on the backend, accrues
# `metered` hours since the last event for currently-running NodeInstances,
# and at month-end (run on day 1 of the new month) rolls all pending rows
# into Billing::InvoiceLineItem entries on the active subscription's open
# invoice.
#
# Per the worker architecture the actual rollup logic lives behind the
# internal API — this job posts to /api/v1/internal/billing/provisioning/meter/rollup
# with the current timestamp; the controller dispatches to
# Billing::ProvisioningMeterService and its sibling collaborators.
class BillingProvisioningMeterJob < BaseJob
  sidekiq_options queue: 'billing', retry: 3

  ROLLUP_PATH = '/api/v1/internal/billing/provisioning/meter/rollup'

  def execute(now_iso = nil)
    log_info("Starting billing provisioning meter rollup at #{Time.current}")

    payload = { now: now_iso || Time.current.iso8601 }

    result = with_api_retry do
      api_client.post(ROLLUP_PATH, payload)
    end

    if result.is_a?(Hash) && result['success'] == false
      log_warn("Billing provisioning meter rollup reported failure",
               error: result['error'])
      return result
    end

    metered  = result.is_a?(Hash) ? result.dig('data', 'metered_count').to_i : 0
    invoiced = result.is_a?(Hash) ? result.dig('data', 'invoiced_count').to_i : 0
    log_info("Billing provisioning meter rollup completed",
             metered: metered, invoiced: invoiced)
    result
  rescue StandardError => e
    log_error("BillingProvisioningMeterJob failed: #{e.message}", e)
    raise
  end
end
