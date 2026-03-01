# frozen_string_literal: true

module Devops
  class RunnerHealthService
    STALE_THRESHOLD = 5.minutes

    def initialize(account: nil)
      @account = account
    end

    # Check health of all runners, mark stale ones offline
    def check_health
      runners = runners_scope.online
      marked_offline = 0

      runners.find_each do |runner|
        next if runner.recently_active?

        runner.mark_offline!
        marked_offline += 1
        Rails.logger.info "[RunnerHealth] Marked runner #{runner.name} (#{runner.id}) offline (stale)"
      rescue StandardError => e
        Rails.logger.error "[RunnerHealth] Failed to check runner #{runner.id}: #{e.message}"
      end

      { checked: runners.count, marked_offline: marked_offline }
    end

    # Sync runner statuses from all providers
    def sync_all_runner_statuses
      synced = 0

      credentials_scope.active.each do |credential|
        lifecycle = RunnerLifecycleService.new(account: credential.account)
        synced += lifecycle.sync_runners(credential_id: credential.id)
      rescue StandardError => e
        Rails.logger.error "[RunnerHealth] Failed to sync runners for credential #{credential.id}: #{e.message}"
      end

      synced
    end

    # Compute capacity summary
    def capacity_summary
      runners = runners_scope
      total = runners.count
      online = runners.online.count
      busy = runners.busy.count
      available = runners.available.count

      {
        total: total,
        online: online,
        offline: runners.offline.count,
        busy: busy,
        available: available,
        utilization_pct: total.positive? ? (((total - available).to_f / total) * 100).round(1) : 0
      }
    end

    private

    def runners_scope
      @account ? Devops::GitRunner.where(account: @account) : Devops::GitRunner.all
    end

    def credentials_scope
      @account ? @account.git_provider_credentials : Devops::GitProviderCredential.all
    end
  end
end
