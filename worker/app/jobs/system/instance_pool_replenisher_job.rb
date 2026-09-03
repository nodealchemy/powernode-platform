# frozen_string_literal: true

module System
  # Slice 7 — periodic instance pool replenisher.
  #
  # Runs every 60s (cron in worker/config/sidekiq.yml). For each
  # active or draining pool, the reaper performs a 2-phase tick:
  #   1. recycle_stale → mark stuck-warming members as errored (past
  #      DEFAULT_WARMING_TIMEOUT_SECONDS), recycle stale ready members
  #   2. replenish    → provision new warming members up to target_size,
  #      ACTIVE POOLS ONLY (IMP-cb2da06a384b)
  #
  # The two phases have different pool sets on purpose. Draining pools are
  # listed because recycling is what EMPTIES them — stale-warming, the
  # ready TTL and the errored terminate ladder all run from phase 1. They
  # are never topped up: drain! terminates the ready members and leaves
  # target_size standing (so re-activating the pool warms it again), so a
  # replenish tick against a draining pool provisioned back everything the
  # drain had just terminated, once a minute, for real money. The platform's
  # InstancePoolService#replenish! refuses a non-active pool outright; the
  # skip below is so the reaper does not spend a call per pool per tick
  # asking for a top-up it knows will be refused.
  #
  # Phase ordering matters: without the recycle phase first, stuck
  # warming members keep counting toward `target_size` so `deficit`
  # stays at 0 and replenish becomes a no-op forever — the symptom
  # was a pool stuck at warming_count=N indefinitely with no
  # underlying provisioning tasks. The platform's
  # InstancePoolService.recycle_stale_members! transitions
  # past-timeout warming members → errored, which jumps the deficit
  # and unblocks the next replenish call.
  #
  # The reaper is API-only — it talks to the platform via HTTP, not
  # direct DB. The platform's InstancePoolService does the actual work
  # (provisioning, state transitions); this job just triggers it.
  #
  # Idempotent: recycle is no-op when no stale members exist;
  # replenish is no-op when pool is at capacity.
  class InstancePoolReplenisherJob < BaseJob
    sidekiq_options queue: :default, retry: 3

    def execute
      pools = list_active_pools
      results = pools.map do |pool|
        # Phase 1: recycle stale members (errors-out stuck-warming so
        # the next phase sees an honest deficit). Failure here doesn't
        # block replenish — log + proceed.
        recycle_pool(pool)
        # Phase 2: replenish to target_size — active pools only.
        replenishable?(pool) ? replenish_pool(pool) : { pool_id: pool_id_of(pool), skipped: "not_active" }
      end

      total_provisioned = results.sum { |r| r[:provisioned] || 0 }
      logger.info(
        "[InstancePoolReplenisherJob] processed #{pools.size} pools, " \
        "provisioned=#{total_provisioned}"
      )

      { processed: pools.size, total_provisioned: total_provisioned }
    end

    private

    def pool_id_of(pool)
      pool[:id] || pool["id"]
    end

    # Phase-2 eligibility. Keyed on the status the platform reports for the
    # pool, which #to_summary includes.
    #
    # A pool whose summary carries NO status is still handed to replenish:
    # the platform is the authority on whether a pool may be topped up, and
    # defaulting a missing field to "skip" would let a serializer change halt
    # replenishment fleet-wide in silence. Only an explicitly non-active
    # status skips.
    def replenishable?(pool)
      status = (pool[:status] || pool["status"]).to_s
      status.empty? || status == "active"
    end

    def list_active_pools
      # BackendApiClient returns STRING-keyed JSON, and get(path, params) takes
      # the query hash POSITIONALLY — passing `params: {...}` double-nests it to
      # ?params[status]=... which the server ignores. Both bugs silently
      # discarded this reaper's results (it logged "processed 0 pools" every
      # tick and never recycled/replenished any pool).
      # Both statuses on purpose — draining pools need phase 1 (recycle).
      # Phase 2 filters them out again via #replenishable?.
      response = api_client.get("/api/v1/system/instance_pools",
                                { status: "active,draining" })
      return [] unless response["success"]
      response.dig("data", "pools") || []
    rescue StandardError => e
      logger.error("[InstancePoolReplenisherJob] list pools failed: #{e.message}")
      []
    end

    def replenish_pool(pool)
      pool_id = pool_id_of(pool)
      response = api_client.post("/api/v1/system/instance_pools/#{pool_id}/replenish")

      if response["success"]
        provisioned = response.dig("data", "replenish_result", "provisioned") || 0
        logger.info(
          "[InstancePoolReplenisherJob] replenished pool #{pool_id}: " \
          "provisioned=#{provisioned}"
        )
        { pool_id: pool_id, provisioned: provisioned }
      else
        logger.warn(
          "[InstancePoolReplenisherJob] replenish failed for pool #{pool_id}: " \
          "#{response["error"]}"
        )
        { pool_id: pool_id, error: response["error"] }
      end
    rescue StandardError => e
      logger.error(
        "[InstancePoolReplenisherJob] replenish exception for pool #{pool_id}: #{e.message}"
      )
      { pool_id: pool_id, error: e.message }
    end

    def recycle_pool(pool)
      pool_id = pool_id_of(pool)
      response = api_client.post("/api/v1/system/instance_pools/#{pool_id}/recycle_stale")

      if response["success"]
        counts = response.dig("data", "recycle_result") || {}
        if counts.values.any? { |v| v.is_a?(Integer) && v.positive? }
          logger.info(
            "[InstancePoolReplenisherJob] recycled stale members in pool " \
            "#{pool_id}: #{counts}"
          )
        end
      else
        logger.warn(
          "[InstancePoolReplenisherJob] recycle failed for pool #{pool_id}: " \
          "#{response["error"]}"
        )
      end
    rescue StandardError => e
      logger.error(
        "[InstancePoolReplenisherJob] recycle exception for pool #{pool_id}: #{e.message}"
      )
      # Don't re-raise — we still want replenish to run on the next
      # phase even if recycle hit an unexpected error.
    end

    # BaseJob#api_client already returns a BackendApiClient instance —
    # no need for a job-local override. The previous override pointed
    # at `::PlatformApiClient` which doesn't exist in the worker
    # tree, causing every periodic run to fail with NameError.
  end
end
