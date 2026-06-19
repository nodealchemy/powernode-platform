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

    # Reconcile runner statuses against the provider (the authoritative liveness
    # source). For each credential it syncs every runner the provider reports —
    # refreshing status + last_seen_at — then marks offline ONLY those local
    # "online" runners the provider no longer returns (deregistered/gone).
    #
    # This replaces timeout-based offline detection (#check_health): liveness
    # comes from the provider, not the local last_seen_at clock, so a healthy
    # idle runner is never falsely marked offline. If a credential's sync returns
    # no runners (transient provider error, or a genuinely empty fleet) its
    # runners are left untouched, so a provider outage can't offline everything.
    def reconcile_runner_statuses
      synced = 0
      marked_offline = 0

      credentials_scope.active.each do |credential|
        sync_started = Time.current
        lifecycle = RunnerLifecycleService.new(account: credential.account)
        count = lifecycle.sync_runners(credential_id: credential.id)
        synced += count

        # Only reconcile-to-offline when the provider actually returned runners,
        # so a failed/empty sync never marks the whole fleet offline. Any still
        # "online" runner whose last_seen_at was not refreshed by this sync was
        # not returned by the provider -> it is genuinely gone.
        next unless count.positive?

        Devops::GitRunner.for_credential(credential.id).online
          .where("last_seen_at IS NULL OR last_seen_at < ?", sync_started)
          .find_each do |runner|
            runner.mark_offline!
            marked_offline += 1
          end
      rescue StandardError => e
        Rails.logger.error "[RunnerHealth] Failed to reconcile runners for credential #{credential.id}: #{e.message}"
      end

      { synced: synced, marked_offline: marked_offline }
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
