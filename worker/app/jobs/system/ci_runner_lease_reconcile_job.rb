# frozen_string_literal: true

module System
  # Campaign 019f5885 inc3 — every-60s CI runner lease reconcile tick.
  #
  # POSTs to the server's worker_api endpoint, which invokes
  # System::CiRunnerLeaseSweepService for each account with active leases: it
  # correlates each lease against Gitea run state + publish arrival and drives it
  # toward release + recycle (and reaps orphaned fleet-* runners). The server runs
  # no Sidekiq and the worker is HTTP-only, so all reconcile logic lives on the
  # server — this job is purely the cron tick + retry mechanism (mirrors
  # MigrationChainAdvanceJob).
  class CiRunnerLeaseReconcileJob < BaseJob
    sidekiq_options queue: :default, retry: 1

    def execute(args = {})
      body = {}
      body[:account_id] = args["account_id"] if args.is_a?(Hash) && args["account_id"]

      response = api_client.post("/api/v1/system/worker_api/ci_runner_leases/advance", body)

      if response["success"]
        data = response["data"] || {}
        log_info "[CiRunnerLeaseReconcileJob] sweep complete: " \
                 "accounts=#{data['accounts_swept']} advanced=#{data['advanced']} " \
                 "released=#{data['released']} flagged=#{data['flagged']} " \
                 "errored=#{data['errored']} orphans_reaped=#{data['orphans_reaped']}"
        data
      else
        log_error "[CiRunnerLeaseReconcileJob] sweep failed: #{response['error']}"
        raise response["error"] || "ci_runner_lease_advance_failed"
      end
    end
  end
end
