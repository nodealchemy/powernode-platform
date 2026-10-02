# frozen_string_literal: true

module Mcp
  # IMP-f074ef554781 — the facts the worker's sandbox cache pruner
  # (McpSandboxCachePruner) cannot get for itself, because the worker has no
  # database: which accounts still exist, and how long a per-account stdio
  # sandbox cache may sit idle before it is reclaimed.
  #
  # The account list is every account that has not been terminated
  # (`cancelled`). A suspended tenant keeps its cache; a cache is cheap to
  # rebuild, so erring toward keeping one costs disk, never correctness.
  #
  # The idle age is the operator's, from the SiteSetting below; anything that is
  # not a positive whole number falls back to the default rather than being
  # honoured, and no value goes below a day.
  class SandboxCachePolicy
    MAX_IDLE_SETTING = "mcp.stdio.sandbox_cache_max_idle_seconds"
    DEFAULT_MAX_IDLE_SECONDS = 30 * 86_400
    MIN_MAX_IDLE_SECONDS = 86_400

    def self.call
      new.call
    end

    def call
      {
        account_ids: ::Account.where.not(status: "cancelled").pluck(:id),
        max_idle_seconds: max_idle_seconds
      }
    end

    private

    def max_idle_seconds
      value = Integer(::SiteSetting.get(MAX_IDLE_SETTING).to_s, 10, exception: false)
      return DEFAULT_MAX_IDLE_SECONDS unless value&.positive?

      [ value, MIN_MAX_IDLE_SECONDS ].max
    end
  end
end
