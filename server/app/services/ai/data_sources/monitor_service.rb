# frozen_string_literal: true

require "digest"

module Ai
  module DataSources
    # Phase 3 server-side monitor loop for pull-based data-source subscriptions.
    #
    # The worker fires a thin cron tick (POST /api/v1/internal/data_sources/
    # monitor_tick); ALL poll/fetch/change-detect/signal logic lives here. For
    # each Ai::DataSourceSubscription that is #due_for_poll (respecting the parent
    # source's quota), the monitor:
    #
    #   1. runs the governed Ai::DataSources::QueryService fetch (the same
    #      kill-flag / quota / cache / circuit-breaker / SSRF / decode / normalize
    #      / redact / audit pipeline as an interactive query), passing the stored
    #      last_etag as a conditional hint;
    #   2. computes a canonical SHA256 checksum of the fetched payload (and, when
    #      present, compares the provenance response_sha256) to decide changed vs
    #      unchanged versus the subscription's last_checksum;
    #   3. on CHANGE: invalidates + warms the response cache with the fresh
    #      payload and emits a "data_source_changed" stigmergic signal
    #      (signal_type "discovery") so autonomous agents perceive the update;
    #   4. records the poll outcome on the subscription (last_checksum / last_etag
    #      / next_poll_at / consecutive_failures).
    #
    # Per-subscription failures are collected and NEVER abort the batch.
    class MonitorService
      # Reserved param key carrying the conditional ETag hint into the adapter /
      # QueryService. Adapters that support conditional requests can translate it
      # into an If-None-Match header; others ignore it (checksum detection still
      # works). Namespaced with a double underscore so it never collides with a
      # real endpoint query parameter.
      CONDITIONAL_ETAG_PARAM = "__conditional_etag"

      # Stigmergic signal coordinates for a detected upstream change.
      CHANGE_SIGNAL_TYPE = "discovery"
      CHANGE_SIGNAL_KEY = "data_source_changed"

      def initialize(account = nil)
        @account = account
      end

      # Walk due subscriptions and poll each. Returns a batch summary:
      #   { polled:, changed:, errors: }
      # `errors` is an array of { subscription_id:, error: } so the caller (the
      # internal controller) can surface partial failures without failing the tick.
      def tick(limit: 100)
        polled = 0
        changed = 0
        errors = []

        due_subscriptions(limit).each do |subscription|
          polled += 1
          begin
            did_change = poll_subscription(subscription)
            changed += 1 if did_change
          rescue StandardError => e
            Rails.logger.warn("[DataSources::MonitorService] poll failed for subscription #{subscription.id}: #{e.class}: #{e.message}")
            safe_record_failure(subscription, e.message)
            errors << { subscription_id: subscription.id, error: e.message }
          end
        end

        { polled: polled, changed: changed, errors: errors }
      end

      # Refresh the health status of every active source in scope. Used by the
      # health cron tick. Returns { refreshed:, errors: }.
      def health_tick
        refreshed = 0
        errors = []

        active_sources.find_each do |source|
          begin
            source.update_health_status!
            refreshed += 1
          rescue StandardError => e
            Rails.logger.warn("[DataSources::MonitorService] health refresh failed for source #{source.id}: #{e.message}")
            errors << { data_source_id: source.id, error: e.message }
          end
        end

        { refreshed: refreshed, errors: errors }
      end

      # Background stale-while-revalidate refresh entry point (called by
      # ResponseCacheService when it serves a stale entry within the SWR window).
      # Runs the governed fetch and re-warms the cache on success. Best-effort:
      # any failure is logged, never raised (the stale value was already served).
      def refresh!(data_source:, endpoint:, params: {})
        envelope = run_query(data_source, endpoint, (params || {}).to_h)
        return false unless envelope[:success]

        warm_cache(data_source, endpoint, params, envelope)
        true
      rescue StandardError => e
        Rails.logger.warn("[DataSources::MonitorService] refresh! failed: #{e.message}")
        false
      end

      private

      attr_reader :account

      # Due, active subscriptions, account-scoped when an account was supplied.
      # Eager-loads the source + endpoint so the poll loop never N+1s.
      def due_subscriptions(limit)
        scope = Ai::DataSourceSubscription.due_for_poll
                                          .includes(:data_source, :endpoint, :agent)
        scope = scope.joins(:data_source).where(ai_data_sources: { account_id: account.id }) if account
        scope.limit(limit)
      end

      def active_sources
        scope = Ai::DataSource.active
        scope = scope.where(account_id: account.id) if account
        scope
      end

      # Poll a single subscription end to end. Returns true on a detected change.
      def poll_subscription(subscription)
        source = subscription.data_source
        endpoint = subscription.endpoint
        return record_skipped(subscription, "missing source or endpoint") if source.nil? || endpoint.nil?

        # Respect the parent source quota — a throttled source defers this poll to
        # the next tick rather than burning its budget on background monitoring.
        quota = source.check_quota!
        unless quota[:allowed]
          Rails.logger.info("[DataSources::MonitorService] subscription #{subscription.id} deferred: quota (#{quota[:limit]})")
          # Re-schedule without counting a failure; the source is simply busy.
          subscription.schedule_next_poll!
          return false
        end

        params = poll_params(subscription)
        envelope = run_query(source, endpoint, params)

        unless envelope[:success]
          subscription.record_failure!(envelope[:error])
          return false
        end

        checksum = canonical_checksum(envelope)
        etag = response_etag(envelope)
        changed = change_detected?(subscription, checksum, etag)

        if changed
          warm_cache(source, endpoint, params, envelope)
          emit_change_signal(subscription, source, endpoint, checksum)
        end

        subscription.record_poll!(changed: changed, checksum: checksum, etag: etag)
        changed
      end

      # Build the fetch params for a subscription: its stored params plus a
      # conditional ETag hint when we have a prior etag to revalidate against.
      def poll_params(subscription)
        params = (subscription.params || {}).to_h
        params = params.merge(CONDITIONAL_ETAG_PARAM => subscription.last_etag) if subscription.last_etag.present?
        params
      end

      def run_query(source, endpoint, params)
        Ai::DataSources::QueryService.new(
          data_source: source,
          endpoint: endpoint,
          params: params,
          agent: nil,
          user: nil
        ).call
      end

      # Canonical SHA256 of the normalized payload data. Stable across hash key
      # ordering via deep_sort so an unchanged upstream payload yields a stable
      # checksum. Prefers the provenance response_sha256 (raw-body hash) when the
      # service surfaced one, falling back to hashing the canonical records.
      def canonical_checksum(envelope)
        prov = envelope[:provenance] || {}
        body_sha = prov[:response_sha256] || prov["response_sha256"]
        return body_sha if body_sha.present?

        Digest::SHA256.hexdigest(stable_json(envelope[:data]))
      rescue StandardError
        Digest::SHA256.hexdigest(envelope[:data].to_s)
      end

      def response_etag(envelope)
        prov = envelope[:provenance] || {}
        prov[:etag] || prov["etag"]
      end

      # A change is detected when the new checksum differs from the stored one
      # (or there is no stored checksum yet — the first successful poll always
      # registers as changed so the initial payload is cached + signalled). When
      # both sides expose an etag and they match, treat as unchanged regardless of
      # checksum (handles 304-style revalidation).
      def change_detected?(subscription, checksum, etag)
        if etag.present? && subscription.last_etag.present? && etag == subscription.last_etag
          return false
        end

        subscription.last_checksum.blank? || subscription.last_checksum != checksum
      end

      def warm_cache(source, endpoint, params, envelope)
        # Strip the conditional hint from the cache-key params so monitored and
        # interactive reads share one cache entry.
        cache_params = (params || {}).to_h.except(CONDITIONAL_ETAG_PARAM)
        # Overwrite ONLY this param-variant's entry (the write below is an idempotent
        # setex). Do NOT blanket-invalidate the whole endpoint — that would cold-miss
        # sibling subscriptions / interactive reads cached under different params.
        Ai::DataSources::ResponseCacheService.write(
          data_source: source,
          endpoint: endpoint,
          params: cache_params,
          payload: {
            "data" => envelope[:data],
            "provenance" => (envelope[:provenance] || {}).transform_keys(&:to_s)
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[DataSources::MonitorService] cache warm failed: #{e.message}")
      end

      # Emit a "data_source_changed" discovery signal so autonomous agents can
      # react to fresh upstream data. Mirrors the QueryService schema-drift signal
      # call site (system context: agent nil). Account-scoped — skipped when the
      # source has no resolvable account.
      def emit_change_signal(subscription, source, endpoint, checksum)
        signal_account = source.account || account
        return unless signal_account

        Ai::Coordination::StigmergicSignalService.new(account: signal_account).emit!(
          signal_type: CHANGE_SIGNAL_TYPE,
          signal_key: CHANGE_SIGNAL_KEY,
          # System-emitted change signal — no agent attribution (consistent with the
          # QueryService schema-drift signal). Avoids cross-account agent/signal mismatch
          # when a subscription's owning agent differs from the source's account.
          agent: nil,
          strength: 1.0,
          payload: {
            "slug" => source.slug,
            "data_source_id" => source.id,
            "endpoint" => endpoint.slug,
            "endpoint_id" => endpoint.id,
            "subscription_id" => subscription.id,
            "checksum" => checksum
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[DataSources::MonitorService] change signal emit failed: #{e.message}")
      end

      def record_skipped(subscription, reason)
        Rails.logger.info("[DataSources::MonitorService] subscription #{subscription.id} skipped: #{reason}")
        subscription.schedule_next_poll!
        false
      end

      def safe_record_failure(subscription, message)
        subscription.record_failure!(message)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::MonitorService] could not record failure for #{subscription.id}: #{e.message}")
      end

      def stable_json(obj)
        deep_sort(obj).to_json
      rescue StandardError
        obj.to_s
      end

      def deep_sort(obj)
        case obj
        when Hash then obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_sort(v) }.sort.to_h
        when Array then obj.map { |v| deep_sort(v) }
        else obj
        end
      end
    end
  end
end
