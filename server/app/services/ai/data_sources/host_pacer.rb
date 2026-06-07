# frozen_string_literal: true

require "uri"

module Ai
  module DataSources
    # Per-host request pacing for the BACKGROUND monitor loop (Phase 5).
    #
    # Tracks the wall-clock timestamp of the last request issued to each host in
    # Redis (DB 0, shared client) and answers "has at least min_interval elapsed
    # since the last hit?". MonitorService consults this BEFORE polling a due
    # subscription: when the host was hit too recently it DEFERS (reschedules) the
    # poll to a later tick instead of issuing the request.
    #
    # CRITICAL: this class NEVER sleeps or blocks. It is a stateless timestamp
    # check (.ready?) + a stamp (.touch). Pacing is achieved by the monitor
    # deferring work across ticks, NOT by the request thread waiting — so the
    # synchronous, interactive QueryService path is never slowed by pacing.
    #
    # Fail-open: any Redis fault makes .ready? return true (allow the poll) and
    # .touch a no-op, so a Redis outage degrades to "no pacing" rather than
    # wedging the monitor.
    class HostPacer
      # Redis namespace for the per-host last-request timestamps (Redis DB 0).
      REDIS_NAMESPACE = "data_source_pacer"

      # Default minimum interval (seconds) between requests to a single host when
      # the caller supplies none. Conservative politeness floor for a background
      # crawler.
      DEFAULT_MIN_INTERVAL_SECONDS = 1

      # How long a host's last-request stamp lingers in Redis. Comfortably longer
      # than any realistic min_interval so the stamp is still present on the next
      # tick; expires on its own so dormant hosts don't accumulate keys.
      STAMP_TTL_SECONDS = 86_400

      class << self
        # True when no prior request is recorded for +host+, or at least
        # +min_interval+ seconds have elapsed since the last one. NEVER sleeps —
        # a caller that gets false should defer its work, not wait.
        #
        # @param host [String] bare host (or anything URI-ish; the host is extracted)
        # @param min_interval [Numeric] minimum seconds between hits (coerced; a
        #   non-positive interval means "no pacing" => always ready)
        # @return [Boolean]
        def ready?(host, min_interval: DEFAULT_MIN_INTERVAL_SECONDS)
          key_host = normalize_host(host)
          return true if key_host.blank?

          interval = coerce_interval(min_interval)
          return true if interval <= 0

          last = last_request_at(key_host)
          return true if last.nil?

          (now_epoch - last) >= interval
        rescue StandardError => e
          Rails.logger.warn("[DataSources::HostPacer] ready? failed (fail-open allow): #{e.message}")
          true
        end

        # Stamp +host+'s last-request time as "now". Call AFTER a successful
        # request so the next tick paces against it. No-op (best-effort) on a
        # Redis fault.
        #
        # @param host [String]
        # @return [void]
        def touch(host)
          key_host = normalize_host(host)
          return if key_host.blank?

          client = redis
          return unless client

          client.setex(key_for(key_host), STAMP_TTL_SECONDS, now_epoch.to_s)
          nil
        rescue StandardError => e
          Rails.logger.warn("[DataSources::HostPacer] touch failed (no-op): #{e.message}")
          nil
        end

        # Seconds remaining before +host+ becomes ready again (0 when ready now).
        # Advisory only — used by the monitor to log/space a deferred reschedule.
        def seconds_until_ready(host, min_interval: DEFAULT_MIN_INTERVAL_SECONDS)
          key_host = normalize_host(host)
          return 0 if key_host.blank?

          interval = coerce_interval(min_interval)
          return 0 if interval <= 0

          last = last_request_at(key_host)
          return 0 if last.nil?

          remaining = interval - (now_epoch - last)
          remaining.positive? ? remaining.ceil : 0
        rescue StandardError
          0
        end

        private

        def last_request_at(host)
          client = redis
          return nil unless client

          raw = client.get(key_for(host))
          return nil if raw.nil?

          value = Float(raw, exception: false)
          value&.positive? ? value : nil
        rescue StandardError => e
          Rails.logger.warn("[DataSources::HostPacer] last-request read failed: #{e.message}")
          nil
        end

        # Accept a bare host or any URI-ish string; extract + downcase the host so
        # "https://API.Example.com/x" and "api.example.com" pace as one host.
        def normalize_host(host)
          return nil if host.blank?

          str = host.to_s.strip
          extracted =
            if str.include?("://")
              begin
                URI.parse(str).host
              rescue URI::InvalidURIError
                nil
              end
            else
              str
            end

          (extracted || str).to_s.downcase.presence
        end

        def coerce_interval(min_interval)
          num = Float(min_interval, exception: false)
          num.nil? ? 0.0 : num
        end

        def key_for(host)
          "#{REDIS_NAMESPACE}:#{host}"
        end

        def now_epoch
          Time.now.to_f
        end

        def redis
          Powernode::Redis.client
        rescue StandardError
          nil
        end
      end
    end
  end
end
