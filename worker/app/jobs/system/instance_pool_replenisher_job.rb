# frozen_string_literal: true

module System
  # Slice 7 — periodic instance pool replenisher.
  #
  # Runs every 60s (cron in worker/config/sidekiq.yml). For each
  # active or draining pool:
  #   - active pool: call platform's replenish endpoint to bring
  #     warming+ready up to target_size
  #   - draining pool: call platform's recycle endpoint to clean up
  #     stale ready members
  #
  # The reaper is API-only — it talks to the platform via HTTP, not
  # direct DB. The platform's InstancePoolService does the actual work
  # (provisioning, state transitions); this job just triggers it.
  #
  # Idempotent: replenish is no-op when pool is at capacity, drain is
  # no-op when no ready members remain.
  class InstancePoolReplenisherJob < BaseJob
    sidekiq_options queue: :default, retry: 3

    def execute
      pools = list_active_pools
      results = pools.map do |pool|
        replenish_pool(pool)
      end

      total_provisioned = results.sum { |r| r[:provisioned] || 0 }
      Rails.logger.info(
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
      Rails.logger.error("[InstancePoolReplenisherJob] list pools failed: #{e.message}")
      []
    end

    def replenish_pool(pool)
      pool_id = pool[:id] || pool["id"]
      response = api_client.post("/api/v1/system/instance_pools/#{pool_id}/replenish")

      if response[:success]
        provisioned = response.dig(:data, :replenish_result, :provisioned) || 0
        Rails.logger.info(
          "[InstancePoolReplenisherJob] replenished pool #{pool_id}: " \
          "provisioned=#{provisioned}"
        )
        { pool_id: pool_id, provisioned: provisioned }
      else
        Rails.logger.warn(
          "[InstancePoolReplenisherJob] replenish failed for pool #{pool_id}: " \
          "#{response[:error]}"
        )
        { pool_id: pool_id, error: response[:error] }
      end
    rescue StandardError => e
      Rails.logger.error(
        "[InstancePoolReplenisherJob] replenish exception for pool #{pool_id}: #{e.message}"
      )
      { pool_id: pool_id, error: e.message }
    end

    def api_client
      @api_client ||= ::PlatformApiClient.new
    end
  end
end
