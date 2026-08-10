# frozen_string_literal: true

module Devops
  # Prunes stale Devops::GitRunner rows — records for ephemeral fleet CI
  # builders whose upstream runner is long gone (the scope sync is
  # upsert-only, so every builder a sync caught mid-life leaves a permanent
  # "offline" row). Service form of scripts/prune-stale-git-runners.rb,
  # exposed over MCP by Ai::Tools::GitRunnerInventoryTool (IMP-5df6d59aaa5c).
  #
  # DELIBERATELY derives staleness from LOCAL signals only. The
  # reconcile-against-upstream prune was reverted (be18ecebc): provider
  # runner listings are unpaginated and can be PARTIAL on transient failures,
  # and no care in the delete makes an incomplete listing safe to reconcile
  # against. This service never lists upstream.
  #
  # Protections, all independent:
  #   1. Only rows whose name starts with "fleet-" are candidates — the
  #      permanent shared runners can never match.
  #   2. Any runner NAMED by a non-terminal CiRunnerLease is excluded (a
  #      builder serving a job right now; module_build leases carry no
  #      git_runner_id, so the name is the join).
  #   3. Any runner REFERENCED by a non-terminal Ai::RunnerDispatch is
  #      excluded (live dispatch FKs are refused, never nulled).
  #   4. Any runner referenced BY ID from any CiRunnerLease row is retained —
  #      deleting it would violate the lease FK, and the lease history is
  #      worth keeping intact.
  # Terminal Ai::RunnerDispatch rows (history) get git_runner_id nulled at
  # apply time — the column is optional and the runner no longer exists
  # anywhere to point at; without this, delete_all raises InvalidForeignKey
  # and deletes nothing.
  class RunnerPruneService
    FLEET_PREFIX = "fleet-"
    ACTIVE_DISPATCH_STATUSES = %w[pending dispatched running].freeze
    TERMINAL_LEASE_STATUSES = %w[released errored].freeze

    Result = Struct.new(:total, :fleet_total, :candidates, :retained,
                        :deleted_count, :cleared_dispatch_pointers, :applied,
                        keyword_init: true)

    def initialize(account:)
      @account = account
    end

    def preview
      build_result(applied: false)
    end

    def apply!
      result = build_result(applied: true)
      ids = result.candidates.map(&:id)
      return result if ids.empty? # counts already initialized to 0

      Devops::GitRunner.transaction do
        # Only terminal dispatches can still point here — active ones were
        # excluded from the candidate set above.
        result.cleared_dispatch_pointers =
          Ai::RunnerDispatch.where(git_runner_id: ids).update_all(git_runner_id: nil)
        result.deleted_count = Devops::GitRunner.where(id: ids).delete_all
      end
      result
    end

    private

    def build_result(applied:)
      base = Devops::GitRunner.where(account: @account)
      fleet = base.where("name LIKE ?", "#{FLEET_PREFIX}%")

      live_lease_names = protected_lease_names
      active_dispatch_ids = Ai::RunnerDispatch.where(account: @account, status: ACTIVE_DISPATCH_STATUSES)
                                              .where.not(git_runner_id: nil)
                                              .distinct.pluck(:git_runner_id)
      lease_referenced_ids = lease_referenced_runner_ids

      candidates = fleet
      candidates = candidates.where.not(name: live_lease_names) if live_lease_names.any?
      excluded_ids = (active_dispatch_ids + lease_referenced_ids).uniq
      candidates = candidates.where.not(id: excluded_ids) if excluded_ids.any?

      Result.new(
        total: base.count,
        fleet_total: fleet.count,
        candidates: candidates.order(:last_seen_at).to_a,
        retained: {
          live_lease_names: live_lease_names,
          active_dispatch_runner_ids: active_dispatch_ids,
          lease_referenced_runner_ids: lease_referenced_ids
        },
        deleted_count: 0, cleared_dispatch_pointers: 0, applied: applied
      )
    end

    # Extension seam: CiRunnerLease lives in extensions/system. In a core-only
    # assembly there are no fleet builders (the extension creates them), so an
    # absent class safely means nothing to protect. Same defined? guard
    # pattern as ai/provisioning's System:: probes.
    def protected_lease_names
      return [] unless defined?(::System::CiRunnerLease)

      ::System::CiRunnerLease.where(account: @account)
                             .where.not(status: TERMINAL_LEASE_STATUSES)
                             .pluck(:runner_name).compact.uniq
    end

    def lease_referenced_runner_ids
      return [] unless defined?(::System::CiRunnerLease)

      ::System::CiRunnerLease.where(account: @account)
                             .where.not(git_runner_id: nil)
                             .distinct.pluck(:git_runner_id)
    end
  end
end
