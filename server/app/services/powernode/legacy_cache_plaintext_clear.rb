# frozen_string_literal: true

module Powernode
  # One-time boot step for the deploy that turns on solid_cache encryption
  # (config/cache.yml `encrypt: true` in production). Entries written before it
  # are plain text: installer hosts that already ran solid_cache hold Vault
  # values and other secrets there, and they would stay at rest, and keep being
  # served, until evicted. This empties solid_cache_entries ONCE.
  #
  # Emptying a cache is a cold start, not data loss: every entry is
  # recomputable, and the next reads repopulate it, encrypted.
  #
  # Marker-guarded (SiteSetting DONE_MARKER), bounded (statement_timeout and
  # lock_timeout inside one transaction, so a busy table fails fast rather than
  # holding the boot), and it NEVER raises: a failure leaves the marker unset
  # and the next boot retries. Callers: the hub's boot runner
  # (extensions/system role-grants-reconcile.rb, before puma) and the installer
  # start script (scripts/systemd/powernode-backend.sh, via the
  # powernode:cache:clear_legacy_plaintext task).
  module LegacyCachePlaintextClear
    DONE_MARKER = "solid_cache_legacy_plaintext_cleared"
    LOCK_TIMEOUT_MS = 2_000

    Outcome = Struct.new(:status, :error_class, keyword_init: true)

    module_function

    # @return [Outcome] status :done (marker already set), :ran (emptied, marker
    #   set), :skipped (no solid_cache table here; marker set), :failed (marker unset)
    def run_once!(time_budget: 30, force: false)
      return Outcome.new(status: :done) if !force && ::SiteSetting.get(DONE_MARKER).to_s == "true"

      status = table_present? ? clear!(time_budget) : :skipped
      ::SiteSetting.set(DONE_MARKER, "true", setting_type: "string")
      Rails.logger.info("[Powernode::LegacyCachePlaintextClear] #{status}")
      Outcome.new(status: status)
    rescue StandardError => e
      Rails.logger.error("[Powernode::LegacyCachePlaintextClear] failed (#{e.class}); the next boot retries")
      Outcome.new(status: :failed, error_class: e.class.name)
    end

    def table_present?
      defined?(::SolidCache::Entry) && ::SolidCache::Entry.table_exists?
    end

    def clear!(time_budget)
      connection = ::SolidCache::Entry.connection
      ::SolidCache::Entry.transaction do
        connection.execute("SET LOCAL statement_timeout = #{(time_budget * 1000).to_i}")
        connection.execute("SET LOCAL lock_timeout = #{LOCK_TIMEOUT_MS}")
        ::SolidCache::Entry.clear_truncate
      end
      :ran
    end
  end
end
