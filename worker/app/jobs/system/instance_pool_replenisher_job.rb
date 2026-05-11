# frozen_string_literal: true

module System
  # Slice 7 — periodic instance pool replenisher.
  #
  # Runs every 60s (cron in worker/config/sidekiq.yml). For each
  # active or draining pool, the reaper performs a 2-phase tick:
  #   1. recycle_stale → mark stuck-warming members as errored (past
  #      DEFAULT_WARMING_TIMEOUT_SECONDS), recycle stale ready members
  #   2. replenish    → provision new warming members up to target_size
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
        # Phase 2: replenish to target_size.
        replenish_pool(pool)
      end

      total_provisioned = results.sum { |r| r[:provisioned] || 0 }
      logger.info(
        "[InstancePoolReplenisherJob] processed #{pools.size} pools, " \
        "provisioned=#{total_provisioned}"
      )

      { processed: pools.size, total_provisioned: total_provisioned }
    end

    private

    def list_active_pools
      response = api_client.get("/api/v1/system/instance_pools",
                                params: { status: "active,draining" })
      return [] unless response[:success]
      response.dig(:data, :pools) || []
    rescue StandardError => e
      logger.error("[InstancePoolReplenisherJob] list pools failed: #{e.message}")
      []
    end

    def replenish_pool(pool)
      pool_id = pool[:id] || pool["id"]
      response = api_client.post("/api/v1/system/instance_pools/#{pool_id}/replenish")

      if response[:success]
        provisioned = response.dig(:data, :replenish_result, :provisioned) || 0
        logger.info(
          "[InstancePoolReplenisherJob] replenished pool #{pool_id}: " \
          "provisioned=#{provisioned}"
        )
        { pool_id: pool_id, provisioned: provisioned }
      else
        logger.warn(
          "[InstancePoolReplenisherJob] replenish failed for pool #{pool_id}: " \
          "#{response[:error]}"
        )
        { pool_id: pool_id, error: response[:error] }
      end
    rescue StandardError => e
      logger.error(
        "[InstancePoolReplenisherJob] replenish exception for pool #{pool_id}: #{e.message}"
      )
      { pool_id: pool_id, error: e.message }
    end

    def recycle_pool(pool)
      pool_id = pool[:id] || pool["id"]
      response = api_client.post("/api/v1/system/instance_pools/#{pool_id}/recycle_stale")

      if response[:success]
        counts = response.dig(:data, :recycle_result) || {}
        if counts.values.any? { |v| v.is_a?(Integer) && v.positive? }
          logger.info(
            "[InstancePoolReplenisherJob] recycled stale members in pool " \
            "#{pool_id}: #{counts}"
          )
        end
      else
        logger.warn(
          "[InstancePoolReplenisherJob] recycle failed for pool #{pool_id}: " \
          "#{response[:error]}"
        )
      end
    rescue StandardError => e
      logger.error(
        "[InstancePoolReplenisherJob] recycle exception for pool #{pool_id}: #{e.message}"
      )
      # Don't re-raise — we still want replenish to run on the next
      # phase even if recycle hit an unexpected error.
    end

    def api_client
      @api_client ||= ::PlatformApiClient.new
    end
  end
end
