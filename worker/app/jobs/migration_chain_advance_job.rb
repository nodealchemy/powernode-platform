# frozen_string_literal: true

# P9.5 — Multi-hop migration chain advancement job.
#
# Ticks every 60s via Sidekiq cron (declared in worker/config/sidekiq.yml
# under :migration_chain_advance). POSTs to the server's worker_api
# endpoint, which invokes ::System::Migrations::ChainSweepService.run!.
# That service walks every active MigrationChain (planned or in_flight)
# and advances one hop per chain per tick.
#
# Cadence rationale: 60s is the balance between per-hop latency
# (operator sees a 3-hop chain complete in ~3 min) and worker load.
# Cooperative scheduling — one hop per chain per tick — prevents a
# long chain from monopolizing the worker thread; many short chains
# still progress concurrently.
#
# Plan reference: P9.5 multi-hop migration chains.
class MigrationChainAdvanceJob < BaseJob
  sidekiq_options queue: :system, retry: 1

  def execute(args = {})
    log_info "[MigrationChainAdvanceJob] starting migration-chain sweep"

    body = {}
    body[:account_id] = args["account_id"] if args["account_id"]

    response = api_client.post(
      "/api/v1/system/worker_api/migration_chains/advance",
      body
    )

    if response["success"]
      data = response["data"] || {}
      log_info "[MigrationChainAdvanceJob] sweep complete: " \
               "swept=#{data['swept']} advanced=#{data['advanced']} " \
               "completed=#{data['completed']} failed=#{data['failed']}"
      data
    else
      log_error "[MigrationChainAdvanceJob] sweep failed: #{response['error']}"
      raise response["error"] || "migration_chain_advance_failed"
    end
  end
end
