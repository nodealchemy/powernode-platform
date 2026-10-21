# frozen_string_literal: true

# Retries cleanup that had to follow a committed account deletion (the Vault purge
# after Account#destroy!). The server runs no Sidekiq, so the CADENCE lives here and
# the WORK lives behind /api/v1/internal/platform/purge_tasks/sweep; the server owns
# the task rows, backoff and retry limits.
class PlatformPurgeSweepJob < BaseJob
  sidekiq_options queue: 'maintenance', retry: 1

  SWEEP_PATH = '/api/v1/internal/platform/purge_tasks/sweep'

  def execute(_args = {})
    response = api_client.post(SWEEP_PATH, {})
    data = response['data'] || response
    log_info "[PlatformPurgeSweepJob] completed=#{data['completed'].to_i} " \
             "failed=#{data['failed'].to_i} pending=#{data['pending'].to_i}"
    data
  end
end
