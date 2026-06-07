# frozen_string_literal: true

require "digest"

module Ai
  module DataSources
    # The QueryService is the Phase 1 integrator: it composes every data-source
    # module (adapters, signers, decoders, format detection, normalization, the
    # SSRF-guarded connection factory, the response cache) and every shared reuse
    # service (per-source kill flag, quotas, circuit breaker, credential vault,
    # schema validation, PII redaction, audit hash chain, cost attribution) into a
    # single governed external-fetch pipeline.
    #
    # CONTRACT:
    #   Ai::DataSources::QueryService
    #     .new(data_source:, endpoint:, params:, agent: nil, user: nil)
    #     .call => FetchEnvelope (Hash)
    #
    #   FetchEnvelope:
    #     {
    #       success: Boolean,
    #       data: Array<Hash>,            # canonical, normalized records
    #       provenance: {
    #         slug:, endpoint_id:, fetched_at:, from_cache:, cache_age_seconds:,
    #         response_sha256:, source_url: (REDACTED), declared_vs_detected_content_type:,
    #         charset:, applied_encoding:, schema_valid:, record_count:, anomalies: []
    #       },
    #       status:,                      # success|error|timeout|rate_limited|blocked|cached
    #       duration_ms:,
    #       bytes:,
    #       error:                        # nil on success; redacted message otherwise
    #     }
    #
    # Pipeline order (every stage composes with the next):
    #   1. per-source kill flag (Shared::FeatureFlagService) -> short-circuit
    #   2. data_source.check_quota! + per-AGENT quota namespacing -> rate_limited
    #   3. ResponseCacheService.fetch (singleflight) -> from_cache hit
    #   4. resolve credential (Vault when vault_path present, else decrypted_*)
    #   5. circuit-breaker-wrapped: build_request -> sign -> validate_url! -> send
    #      (idempotent-verb retry guard; never auto-retry POST without idem key)
    #   6. detect format + decode via adapter.parse -> canonical records
    #   7. validate vs endpoint.response_schema (JsonSchemaValidator) -> schema_valid
    #      then coerce/normalize via NormalizationService
    #   8. record_request!(bytes:) + credential success/failure; map breaker state
    #   9. REDACT url+params+response-snippet, persist ai_data_source_queries row
    #      routed through the Audit::LogIntegrityService hash chain, emit one
    #      Ai::CostAttribution row
    #  10. write cache; return the FetchEnvelope (provenance populated; url REDACTED)
    class QueryService
      # Canonical FetchEnvelope status tokens (subset of DataSourceQuery::STATUSES).
      STATUS_SUCCESS       = "success"
      STATUS_ERROR         = "error"
      STATUS_TIMEOUT       = "timeout"
      STATUS_RATE_LIMITED  = "rate_limited"
      STATUS_BLOCKED       = "blocked"
      STATUS_CACHED        = "cached"

      # HTTP verbs that are safe to auto-retry per RFC 7231 (idempotent). POST is
      # deliberately excluded — it is retried only when the caller supplies an
      # idempotency key (config["idempotency_key"] / params[:idempotency_key]).
      IDEMPOTENT_METHODS = %w[GET HEAD PUT DELETE OPTIONS TRACE].freeze

      # One automatic retry on a transient transport failure for idempotent verbs.
      MAX_RETRIES = 1

      # AuditLog action tokens (must be members of AuditActions::ALL_ACTIONS so the
      # companion audit entry — which carries the SHA256 hash-chain linkage —
      # validates). An outbound data-source fetch maps to api_request /
      # api_request_failed.
      AUDIT_ACTION_SUCCESS = "api_request"
      AUDIT_ACTION_FAILURE = "api_request_failed"

      # How much of the decoded body we keep (redacted) as a snippet for forensics.
      RESPONSE_SNIPPET_LIMIT = 2_000

      # Audit-trailed cost attribution category for external data egress.
      COST_CATEGORY = "api_calls"

      def initialize(data_source:, endpoint:, params: {}, agent: nil, user: nil)
        @data_source = data_source
        @endpoint = endpoint
        @params = (params || {}).to_h
        @agent = agent
        @user = user
        @account = data_source&.account
        @started_at = monotonic_now
        @anomalies = []
        # Phase 2b opt-in observability outcomes (nil = stage not run / not asserted).
        @quality_score = nil
        @quality_passed = nil
        @quarantined = false
        @schema_drift = nil
        # Aggregate transferred bytes across paginated pages (single-request path
        # leaves this nil and uses the per-response bytesize unchanged).
        @paginated_bytes_in = nil
      end

      # Run the full pipeline. Never raises: every failure path is mapped to a
      # FetchEnvelope with success:false and a redacted error message.
      def call
        # (1) per-source kill flag — short-circuit when disabled for this source.
        return disabled_envelope unless source_enabled?

        # (2) quota: shared per-source check + per-agent Redis namespacing.
        if (quota = quota_exceeded?)
          return rate_limited_envelope(quota)
        end

        # (3) cache (singleflight) wraps (4)-(8). The block performs the live
        # fetch+decode only on a miss; on a hit the cached payload is returned. We
        # determine hit vs miss with a recompute flag so persistence (9) runs
        # exactly once here in call, never inside the cache block.
        result = fetch_via_cache

        # (8.5) stale-if-error: when the live fetch failed with a transient
        # upstream fault (timeout / 5xx / transport / breaker-OPEN) and the
        # endpoint opts into stale_if_error_seconds, serve the last-known-good
        # cached payload (flagged) within that window instead of failing. Policy
        # rejections (blocked / rate_limited) and successes are passed through
        # untouched, so the default FetchEnvelope path is unaffected.
        result = maybe_serve_stale_if_error(result)

        # (9) persist (redacted) + audit-chain + cost; (10) cache + return.
        finalize(result)
      rescue StandardError => e
        Rails.logger.error("[DataSources::QueryService] unhandled error for #{safe_slug}: #{e.class}: #{e.message}")
        error_envelope(status: STATUS_ERROR, error: redact_message(e.message))
      end

      private

      attr_reader :data_source, :endpoint, :params, :agent, :user, :account

      # ----------------------------------------------------------------------
      # (1) per-source kill flag
      # ----------------------------------------------------------------------

      # Enabled unless an operator explicitly disables this source's flag
      # (data_source.<slug>.enabled). Defaults to enabled so sources work out of
      # the box; the flag is a kill switch, not an opt-in.
      def source_enabled?
        flag = "data_source.#{data_source.slug}.enabled".to_sym
        # Treat an unset flag as enabled: only a present-and-false flag disables.
        return true unless flag_present?(flag)

        Shared::FeatureFlagService.enabled?(flag, data_source) ||
          Shared::FeatureFlagService.enabled?(flag)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] kill-flag check failed (fail-open): #{e.message}")
        true
      end

      def flag_present?(flag)
        Flipper.exist?(flag)
      rescue StandardError
        false
      end

      # ----------------------------------------------------------------------
      # (2) quota — shared per-source + per-agent namespacing
      # ----------------------------------------------------------------------

      # Returns a quota descriptor Hash when blocked, or nil when allowed.
      def quota_exceeded?
        source_quota = data_source.check_quota!
        return source_quota unless source_quota[:allowed]

        agent_quota = agent_quota_check
        return agent_quota unless agent_quota[:allowed]

        nil
      end

      # Per-agent quota namespaced under data_source:<id>:quota:<agent_id>:*.
      # Mirrors the model's Redis window/limit scheme but scoped to the agent so a
      # single noisy agent cannot exhaust the whole source's budget. Limits come
      # from data_source.rate_limits["per_agent"] (falls back to no per-agent cap).
      def agent_quota_check
        return { allowed: true } unless agent&.id

        per_agent = data_source.rate_limits["per_agent"]
        return { allowed: true } if per_agent.blank?

        usage = agent_quota_usage
        now = Time.current

        if per_agent["requests_per_minute"] && usage[:minute] >= per_agent["requests_per_minute"].to_i
          return { allowed: false, retry_after: 60 - now.sec, limit: "per_agent.requests_per_minute" }
        end
        if per_agent["requests_per_hour"] && usage[:hour] >= per_agent["requests_per_hour"].to_i
          return { allowed: false, retry_after: 3600 - (now.min * 60 + now.sec), limit: "per_agent.requests_per_hour" }
        end
        if per_agent["requests_per_day"] && usage[:day] >= per_agent["requests_per_day"].to_i
          return { allowed: false, retry_after: 86_400 - (now.hour * 3600 + now.min * 60 + now.sec), limit: "per_agent.requests_per_day" }
        end

        { allowed: true }
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] agent quota check failed (fail-open): #{e.message}")
        { allowed: true }
      end

      def agent_quota_usage
        prefix = agent_quota_prefix
        redis = redis_client
        return { minute: 0, hour: 0, day: 0 } unless redis

        now = Time.current
        values = redis.mget(
          "#{prefix}:min:#{now.strftime('%Y%m%d%H%M')}",
          "#{prefix}:hr:#{now.strftime('%Y%m%d%H')}",
          "#{prefix}:day:#{now.strftime('%Y%m%d')}"
        )
        { minute: values[0].to_i, hour: values[1].to_i, day: values[2].to_i }
      end

      # Atomically bump the per-agent counters after a real (non-cached) request.
      def record_agent_request!
        return unless agent&.id

        prefix = agent_quota_prefix
        redis = redis_client
        return unless redis

        now = Time.current
        minute_key = "#{prefix}:min:#{now.strftime('%Y%m%d%H%M')}"
        hour_key = "#{prefix}:hr:#{now.strftime('%Y%m%d%H')}"
        day_key = "#{prefix}:day:#{now.strftime('%Y%m%d')}"

        redis.multi do |tx|
          tx.incr(minute_key)
          tx.expire(minute_key, 120)
          tx.incr(hour_key)
          tx.expire(hour_key, 7200)
          tx.incr(day_key)
          tx.expire(day_key, 172_800)
        end
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] agent quota record failed: #{e.message}")
      end

      def agent_quota_prefix
        "data_source:#{data_source.id}:quota:#{agent.id}"
      end

      # ----------------------------------------------------------------------
      # (3) cache
      # ----------------------------------------------------------------------

      # Wraps the live fetch (4)-(8) in ResponseCacheService.fetch (singleflight +
      # XFetch). The cache stores only the payload portion ({ data:, provenance: }).
      # On a MISS the block runs the real network fetch and returns the cacheable
      # payload; on a HIT the block is not invoked and Redis returns the prior
      # payload. We detect which happened via a recompute flag and return a single
      # internal result Hash that finalize() persists exactly once in call.
      #
      # The cache-layer rescue falls through to a direct (uncached) fetch so a
      # Redis fault never breaks a query.
      def fetch_via_cache
        recomputed = false
        fresh_result = nil

        payload = ResponseCacheService.fetch(
          data_source: data_source, endpoint: endpoint, params: cache_params
        ) do
          recomputed = true
          fresh_result = perform_fetch
          cacheable_payload(fresh_result)
        end

        if recomputed
          # MISS: perform_fetch ran inside the block; return its result verbatim.
          fresh_result
        else
          # HIT: reconstruct an internal result from the cached payload.
          result_from_cached_payload(payload)
        end
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] cache layer error, bypassing cache: #{e.message}")
        # Fall back to a direct fetch; finalize() still persists it once.
        perform_fetch
      end

      # Transient upstream fault statuses eligible for a stale-if-error serve.
      # Policy rejections (blocked / rate_limited) are deliberately excluded — a
      # blocked or throttled request is a decision, not an upstream outage.
      STALE_IF_ERROR_STATUSES = [STATUS_ERROR, STATUS_TIMEOUT].freeze

      # When the live fetch failed transiently and the endpoint opts into
      # stale_if_error_seconds, swap the failure for the last-known-good cached
      # payload within that window. The substituted result is flagged
      # (served_stage: "stale_if_error", stale_if_error: true, success: true) so
      # downstream persistence/provenance record an honest "served stale on
      # error" outcome rather than a fresh success. OFF (no-op) when the column is
      # nil, when no qualifying failure occurred, or when no stale entry exists.
      def maybe_serve_stale_if_error(result)
        return result unless result.is_a?(Hash)
        return result if result[:success]
        return result if result[:from_cache]
        return result unless STALE_IF_ERROR_STATUSES.include?(result[:status])

        window = stale_if_error_window
        return result unless window.positive?

        stale = ResponseCacheService.read_stale(
          data_source: data_source, endpoint: endpoint, params: cache_params
        )
        return result unless stale.is_a?(Hash)
        return result if stale[:payload].blank?
        # A still-fresh entry would have satisfied the cache layer; if we are here
        # with a non-expired entry, the failure is unrelated to staleness — pass
        # the failure through rather than masking it with a fresh value.
        return result unless stale[:hard_expired]
        # Only serve within the configured stale-if-error window, measured from
        # the moment the entry went stale (past the hard expiry).
        return result if stale[:stale_age_seconds].to_i > window

        build_stale_if_error_result(stale, result)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] stale-if-error serve failed for #{safe_slug}: #{e.message}")
        result
      end

      def stale_if_error_window
        return 0 unless endpoint.respond_to?(:stale_if_error_seconds)

        value = endpoint.stale_if_error_seconds
        value.to_i.positive? ? value.to_i : 0
      rescue StandardError
        0
      end

      # Reconstruct a served result from a stale cached payload after a transient
      # upstream error. Flagged stale_if_error so it never re-writes the cache
      # (finalize gates write_cache on a FRESH success) and is auditable as a
      # degraded serve.
      def build_stale_if_error_result(stale, failed_result)
        payload = stale[:payload]
        data = payload.is_a?(Hash) ? (payload["data"] || payload[:data] || []) : []
        prov = if payload.is_a?(Hash)
                 (payload["provenance"] || payload[:provenance] || {}).deep_symbolize_keys
               else
                 {}
               end
        prov = prov.merge(
          from_cache: true,
          stale_if_error: true,
          cache_age_seconds: stale[:age_seconds].to_i,
          stale_age_seconds: stale[:stale_age_seconds].to_i,
          served_on_error: failed_result[:status],
          anomalies: (Array(prov[:anomalies]) + ["stale_if_error"]).uniq
        )
        @anomalies = Array(prov[:anomalies]).map(&:to_s)

        {
          success: true,
          status: STATUS_CACHED,
          http_status: nil,
          data: data,
          provenance: prov,
          raw_body: nil,
          bytes_in: 0,
          error: nil,
          redacted_snippet: nil,
          from_cache: true,
          served_stage: "stale_if_error"
        }
      end

      # Rebuild an internal result Hash from a cached payload, flagged from_cache so
      # finalize() persists a cached row and skips re-writing the cache.
      def result_from_cached_payload(payload)
        unless payload.is_a?(Hash)
          # Unusable cached value — treat as a miss and fetch live.
          return perform_fetch
        end

        data = payload["data"] || payload[:data] || []
        prov = (payload["provenance"] || payload[:provenance] || {}).deep_symbolize_keys
        prov = prov.merge(
          from_cache: true,
          cache_age_seconds: cache_age_seconds(prov[:fetched_at])
        )
        @anomalies = Array(prov[:anomalies]).map(&:to_s)

        {
          success: true,
          status: STATUS_CACHED,
          http_status: nil,
          data: data,
          provenance: prov,
          raw_body: nil,
          bytes_in: 0,
          error: nil,
          redacted_snippet: nil,
          from_cache: true
        }
      end

      def cache_age_seconds(fetched_at)
        return 0 if fetched_at.blank?

        ts = fetched_at.is_a?(Time) ? fetched_at : Time.parse(fetched_at.to_s)
        [(Time.current - ts).round, 0].max
      rescue ArgumentError, TypeError
        0
      end

      # Only the data + provenance are cacheable (status/duration/bytes are
      # per-call). Stored with string keys so JSON round-trips cleanly.
      def cacheable_payload(result)
        {
          "data" => result[:data],
          "provenance" => stringify_provenance(result[:provenance])
        }
      end

      def stringify_provenance(prov)
        prov.transform_keys(&:to_s)
      end

      # Cache key params: the caller params plus the endpoint identity is already
      # folded into the cache key by ResponseCacheService.
      def cache_params
        params
      end

      # ----------------------------------------------------------------------
      # (4)-(8) credential resolution + protected fetch + decode + normalize
      # ----------------------------------------------------------------------

      # Performs the live fetch and returns an internal result Hash:
      #   { success:, status:, http_status:, data:, provenance:, raw_body:,
      #     bytes_in:, error:, redacted_snippet: }
      #
      # Outbound pagination is OFF unless endpoint.pagination is configured: the
      # default single-request path below is byte-for-byte unchanged. When a
      # pagination config is present, perform_paginated_fetch drives the page walk
      # and feeds the concatenated canonical records into the same decode/normalize
      # path so the FetchEnvelope shape is identical (just more records).
      def perform_fetch
        credential = resolve_credential

        return perform_paginated_fetch(credential) if pagination_enabled?

        request = adapter.build_request(endpoint: endpoint, params: params)
        absolute_url = resolved_request_url(request)

        # (5) sign the outbound request env in place.
        sign_request!(request, credential)

        # (5) breaker-wrapped dispatch with SSRF validation + idempotent retry.
        response = with_circuit_breaker do
          dispatch_with_retry(request, absolute_url)
        end

        decode_and_normalize(response, absolute_url, credential)
      rescue Ai::DataSources::HttpConnectionFactory::SsrfError => e
        record_failure(@last_credential, "SSRF blocked: #{e.message}")
        fetch_failure(STATUS_BLOCKED, "request blocked by egress policy", absolute_url: nil)
      rescue Ai::DataSources::HttpConnectionFactory::ResponseTooLargeError => e
        record_failure(@last_credential, e.message)
        fetch_failure(STATUS_ERROR, "response exceeded size cap", absolute_url: nil)
      rescue CircuitBreakerCore::CircuitOpenError => e
        # Breaker is open: do not touch credential failure counters (the breaker
        # already reflects upstream health) — surface as a transient error.
        Rails.logger.warn("[DataSources::QueryService] circuit open for #{breaker_service_name}: #{e.message}")
        fetch_failure(STATUS_ERROR, "data source temporarily unavailable (circuit open)", absolute_url: nil)
      rescue Faraday::TimeoutError, Net::OpenTimeout, Net::ReadTimeout => e
        record_failure(@last_credential, "timeout: #{e.message}")
        fetch_failure(STATUS_TIMEOUT, "request timed out", absolute_url: nil)
      rescue Faraday::Error => e
        record_failure(@last_credential, "transport error: #{e.message}")
        fetch_failure(STATUS_ERROR, redact_message(e.message), absolute_url: nil)
      rescue StandardError => e
        # Catch-all so perform_fetch ALWAYS returns a result Hash (never raises),
        # keeping the cache singleflight block and call() deterministic. Covers
        # adapter/build_request/decode faults not otherwise classified.
        Rails.logger.error("[DataSources::QueryService] fetch error for #{safe_slug}: #{e.class}: #{e.message}")
        record_failure(@last_credential, e.message)
        fetch_failure(STATUS_ERROR, redact_message(e.message), absolute_url: nil)
      end

      # ----------------------------------------------------------------------
      # (5b) OUTBOUND PAGINATION — opt-in page walk (OFF when endpoint.pagination
      # is blank). Drives Ai::DataSources::Paginator, which concatenates the
      # decoded canonical records across pages; we then run the SAME
      # decode/normalize/provenance path over the combined set so the
      # FetchEnvelope shape is unchanged.
      # ----------------------------------------------------------------------

      # Pagination is enabled only when the endpoint carries a non-blank config
      # with a supported "type". Any other state (blank / garbage) is OFF, so the
      # default single-request path runs and FetchEnvelope is identical.
      def pagination_enabled?
        cfg = endpoint.respond_to?(:pagination) ? endpoint.pagination : nil
        return false unless cfg.is_a?(Hash) && cfg.present?

        type = (cfg["type"] || cfg[:type]).to_s.strip.downcase
        Ai::DataSources::Paginator::SUPPORTED_TYPES.include?(type)
      rescue StandardError
        false
      end

      # Walk pages, concatenate canonical records, and finalize through the shared
      # decode/normalize path. Each page is dispatched via the same governed
      # build->sign->validate->dispatch sequence (inside the circuit breaker) the
      # single-request path uses; check_quota! is honored before each subsequent
      # page so a long walk cannot blow past the source's budget.
      def perform_paginated_fetch(credential)
        paginator = Ai::DataSources::Paginator.new(
          endpoint: endpoint,
          base_params: stringify_query(params),
          fetch_page: ->(page_params) { dispatch_page(page_params, credential) },
          decode_page: ->(response) { decode_records(response.body.to_s) },
          check_quota: -> { paginate_quota_veto }
        )

        # Defensive: if the paginator decides it is not actually enabled (empty
        # config slipped past the gate), fall back to a single request.
        return perform_single_after_pagination_guard(credential) unless paginator.enabled?

        walk = paginator.each_page
        last = walk[:last_response]
        return fetch_failure(STATUS_ERROR, "pagination produced no response", absolute_url: @last_absolute_url) if last.nil?

        @anomalies << "paginated_#{walk[:pages_fetched]}_pages"
        @anomalies << "pagination_truncated" if walk[:truncated]

        pagination_provenance = {
          type: paginator_type,
          pages_fetched: walk[:pages_fetched],
          stopped_reason: walk[:stopped_reason],
          truncated: walk[:truncated]
        }

        decode_and_normalize(
          last, @last_absolute_url, credential,
          records_override: walk[:records],
          bytes_override: @paginated_bytes_in.to_i,
          pagination_provenance: pagination_provenance
        )
      end

      # When the paginator self-disables after the enable gate (race on an empty
      # config), run exactly one ordinary request — identical to the default path.
      def perform_single_after_pagination_guard(credential)
        request = adapter.build_request(endpoint: endpoint, params: params)
        absolute_url = resolved_request_url(request)
        sign_request!(request, credential)
        response = with_circuit_breaker { dispatch_with_retry(request, absolute_url) }
        decode_and_normalize(response, absolute_url, credential)
      end

      # Dispatch one page. Accepts either page-augmented params or, in link-follow
      # mode, a reserved absolute-URL override that bypasses path/param building.
      # Runs inside the circuit breaker with SSRF validation + idempotent retry,
      # exactly like the single-request path, and tallies transferred bytes for the
      # aggregate provenance.
      def dispatch_page(page_params, credential)
        absolute_override = page_params[Ai::DataSources::Paginator::ABSOLUTE_URL_PARAM]

        if absolute_override.present?
          request = adapter.build_request(endpoint: endpoint, params: {})
          request[:query] = {}
          absolute_url = absolute_override.to_s
          @last_absolute_url = absolute_url
        else
          request = adapter.build_request(endpoint: endpoint, params: page_params)
          absolute_url = resolved_request_url(request)
        end

        sign_request!(request, credential)
        response = with_circuit_breaker { dispatch_with_retry(request, absolute_url) }
        @paginated_bytes_in = @paginated_bytes_in.to_i + response.body.to_s.bytesize
        response
      end

      # Per-page quota gate: re-check the shared per-source + per-agent quota before
      # the NEXT page. Returns the quota descriptor (truthy) to veto, or nil to
      # allow. Mirrors the call()-level quota check so a paginated walk obeys the
      # same budget as discrete queries.
      def paginate_quota_veto
        quota_exceeded?
      end

      def paginator_type
        cfg = endpoint.respond_to?(:pagination) ? endpoint.pagination : {}
        (cfg.is_a?(Hash) ? (cfg["type"] || cfg[:type]) : nil).to_s
      end

      # (4) Prefer Vault when the active credential carries a vault_path; otherwise
      # fall back to the Rails-encrypted decrypted_* accessors. The signer layer
      # reads decrypted_api_key / decrypted_api_secret, so when Vault returns the
      # secret material we wrap it in a lightweight struct exposing those readers.
      def resolve_credential
        cred = data_source.active_credential
        @last_credential = cred
        return nil unless cred

        if cred.respond_to?(:vault_path) && cred.vault_path.present?
          vaulted = read_vault_credential(cred)
          return vaulted if vaulted
        end

        cred
      end

      def read_vault_credential(cred)
        return nil unless account

        provider = ::Security::VaultCredentialProvider.new(account_id: account.id)
        secret = provider.get_credential(
          credential_type: :data_source,
          credential_id: cred.id,
          record: cred
        )
        return nil unless secret.is_a?(Hash)

        VaultCredentialView.new(secret)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] Vault credential read failed, using DB fallback: #{e.message}")
        nil
      end

      # Adapts a plain Vault secret Hash to the signer credential contract
      # (decrypted_api_key / decrypted_api_secret). Accepts common key spellings.
      class VaultCredentialView
        def initialize(secret)
          @secret = secret.respond_to?(:with_indifferent_access) ? secret.with_indifferent_access : secret
        end

        def decrypted_api_key
          @secret[:api_key] || @secret[:access_key_id] || @secret[:key] || @secret[:token] || @secret[:key_id]
        end

        def decrypted_api_secret
          @secret[:api_secret] || @secret[:secret_access_key] || @secret[:secret] || @secret[:hmac_secret]
        end

        # Pass through any other field a signer might read off a plain Hash.
        def [](name)
          @secret[name]
        end
      end

      def sign_request!(request, credential)
        signer = Ai::DataSources::Auth::SignerRegistry.for(data_source.auth_scheme)
        signer.sign!(request, credential: credential, config: data_source.auth_config || {})
      rescue StandardError => e
        # A signing failure must not leak credential material into logs/exceptions.
        Rails.logger.error("[DataSources::QueryService] request signing failed for #{safe_slug}: #{e.class}")
        raise
      end

      # (5) Circuit breaker keyed per data source so one flaky upstream trips its
      # own breaker without affecting other sources.
      def with_circuit_breaker(&block)
        Ai::CircuitBreakerRegistry.protect(service_name: breaker_service_name, &block)
      end

      def breaker_service_name
        "data_source:#{data_source.id}"
      end

      # (5) Dispatch the request through the SSRF-guarded Faraday connection.
      # validate_url! runs first (resolve-and-pin); the connection middleware
      # re-validates the initial URL and every redirect hop. Idempotent verbs get
      # ONE transient-failure retry; POST is retried only with an idempotency key.
      def dispatch_with_retry(request, absolute_url)
        Ai::DataSources::HttpConnectionFactory.validate_url!(absolute_url)

        attempts = 0
        begin
          attempts += 1
          dispatch(request, absolute_url)
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          raise unless retryable?(request, attempts)

          Rails.logger.info("[DataSources::QueryService] retrying idempotent request (attempt #{attempts + 1}) after #{e.class}")
          retry
        end
      end

      def retryable?(request, attempts)
        return false if attempts > MAX_RETRIES

        method = request[:method].to_s.upcase
        return true if IDEMPOTENT_METHODS.include?(method)

        # NEVER auto-retry a POST without an explicit idempotency key.
        method == "POST" && idempotency_key.present?
      end

      def idempotency_key
        (data_source.auth_config || {})["idempotency_key"] ||
          params["idempotency_key"] || params[:idempotency_key]
      end

      def dispatch(request, absolute_url)
        conn = Ai::DataSources::HttpConnectionFactory.build(data_source: data_source, agent: agent)
        method = request[:method].to_s.downcase.to_sym
        headers = request[:headers] || {}
        query = request[:query] || {}
        body = encode_body(request[:body], headers)

        conn.run_request(method, absolute_url, body, headers) do |req|
          req.params.update(stringify_query(query)) if query.present?
        end
      end

      # Encode a structured body to JSON when no explicit content-type is set;
      # pass strings/raw bodies through untouched.
      def encode_body(body, headers)
        return nil if body.nil?
        return body if body.is_a?(String)

        unless content_type_set?(headers)
          headers["Content-Type"] ||= "application/json"
        end
        body.is_a?(Hash) || body.is_a?(Array) ? JSON.generate(body) : body.to_s
      end

      def content_type_set?(headers)
        headers.keys.any? { |k| k.to_s.casecmp("content-type").zero? }
      end

      def stringify_query(query)
        query.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
      end

      # (6)+(7) Detect format, decode to canonical records, validate the decoded
      # payload against the endpoint response_schema, then normalize.
      #
      # records_override / bytes_override / pagination_provenance are supplied ONLY
      # by the paginated path: the records are the concatenation already decoded
      # per page, bytes is the summed transfer, and pagination_provenance is folded
      # into the envelope provenance. On the default single-request path all three
      # are nil and behavior is unchanged.
      def decode_and_normalize(response, absolute_url, _credential,
                               records_override: nil, bytes_override: nil,
                               pagination_provenance: nil)
        raw_body = response.body.to_s
        bytes_in = bytes_override || raw_body.bytesize
        http_status = response.status
        declared_ct = response_content_type(response)

        detection = Ai::DataSources::Decoders::FormatDetector.detect(
          raw_body, declared_content_type: declared_ct, endpoint: endpoint
        )
        @anomalies << "content_type_mismatch" if detection[:mismatch]

        records = records_override || decode_records(raw_body)
        schema_valid = validate_schema(records)
        @anomalies << "schema_invalid" if schema_valid == false

        normalized, normalization_provenance = normalize_records(records)

        success = http_status.to_i.between?(200, 299)
        @anomalies << "http_#{http_status}" unless success

        # (7b) Phase 2b OPT-IN observability stages (schema-drift tracking, quality
        # evaluation, quarantine). All are no-ops unless the endpoint opts in, so
        # the default path carries zero overhead. Returns the (possibly
        # quarantine-substituted) records to embed in the envelope.
        normalized = apply_observability_stages(normalized, success)

        sha = Digest::SHA256.hexdigest(raw_body)
        provenance = build_provenance(
          absolute_url: absolute_url,
          detection: detection,
          schema_valid: schema_valid,
          record_count: normalized.size,
          response_sha256: sha,
          normalization_provenance: normalization_provenance,
          from_cache: false
        )
        # Surface the quality verdict on provenance so ContractService and callers
        # can read it off the FetchEnvelope (nil when quality was not evaluated).
        provenance[:quality_passed] = @quality_passed unless @quality_passed.nil?
        provenance[:quality_score] = @quality_score unless @quality_score.nil?
        provenance[:schema_drift] = @schema_drift if @schema_drift.present?
        provenance[:quarantined] = true if @quarantined
        provenance[:pagination] = pagination_provenance if pagination_provenance.present?

        # (8) credential health accounting.
        if success
          record_success(@last_credential)
        else
          record_failure(@last_credential, "HTTP #{http_status}")
        end

        {
          success: success,
          status: success ? STATUS_SUCCESS : STATUS_ERROR,
          http_status: http_status,
          data: normalized,
          provenance: provenance,
          raw_body: raw_body,
          bytes_in: bytes_in,
          error: success ? nil : "upstream returned HTTP #{http_status}",
          redacted_snippet: redacted_snippet(raw_body)
        }
      end

      # ----------------------------------------------------------------------
      # (7b) Phase 2b OPT-IN observability: schema drift, quality, quarantine
      # ----------------------------------------------------------------------

      # Run the opt-in stages over the canonical records and return the records to
      # embed in the envelope. On quarantine, the bad batch is swapped for the
      # last-known-good cached payload (and @quarantined is set). Every stage is
      # individually nil-safe and OFF by default; a stage failure is logged and
      # skipped rather than allowed to break the fetch.
      def apply_observability_stages(records, success)
        return records unless endpoint

        track_schema_drift(records) if opt_in?(:track_schema)

        if opt_in?(:quality_checks_enabled)
          evaluate_quality(records)
          # Quarantine only a quality FAILURE on an otherwise-successful fetch when
          # the endpoint opts in: serve the last-known-good payload instead of the
          # bad batch, and DO NOT cache the bad payload (handled in finalize via
          # @quarantined). An upstream error path already serves no data.
          if success && @quality_passed == false && opt_in?(:quarantine_on_failure)
            return quarantine_records(records)
          end
        end

        records
      end

      def opt_in?(flag)
        endpoint.respond_to?(flag) && endpoint.public_send(flag) == true
      rescue StandardError
        false
      end

      # Infer a JSON-Schema-shaped snapshot from the records and append a version
      # via SchemaDriftService. On a BREAKING classification, emit a stigmergic
      # signal so autonomous agents perceive the drift. Records @schema_drift
      # (the classification token) for persistence on the query-log row.
      def track_schema_drift(records)
        inferred = infer_schema(records)
        version = Ai::DataSources::SchemaDriftService.new(account).record_version!(endpoint, inferred)
        @schema_drift = version&.classification
        @anomalies << "schema_drift_#{@schema_drift}" if @schema_drift.present? && @schema_drift != "none"

        emit_schema_drift_signal(version) if @schema_drift == "breaking"
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] schema drift tracking failed for #{safe_slug}: #{e.message}")
      end

      # Infer a minimal JSON Schema (object with typed properties) from the first
      # record's keys — enough for additive/breaking comparison without a gem.
      def infer_schema(records)
        sample = Array(records).find { |r| r.is_a?(Hash) }
        return { "type" => "array", "items" => { "type" => "object", "properties" => {} } } unless sample

        properties = sample.each_with_object({}) do |(key, value), acc|
          acc[key.to_s] = { "type" => json_type_of(value) }
        end
        { "type" => "array", "items" => { "type" => "object", "properties" => properties } }
      end

      def json_type_of(value)
        case value
        when Hash then "object"
        when Array then "array"
        when Integer then "integer"
        when Numeric then "number"
        when TrueClass, FalseClass then "boolean"
        when NilClass then "null"
        else "string"
        end
      end

      def emit_schema_drift_signal(version)
        return unless account

        Ai::Coordination::StigmergicSignalService.new(account: account).emit!(
          signal_type: "warning",
          signal_key: "data_source_schema_drift",
          agent: agent,
          strength: 1.0,
          payload: {
            "data_source_id" => data_source&.id,
            "data_source_slug" => data_source&.slug,
            "endpoint_id" => endpoint&.id,
            "endpoint_slug" => endpoint&.slug,
            "schema_version" => version&.version,
            "classification" => version&.classification,
            "diff" => version&.diff
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] schema drift signal emit failed: #{e.message}")
      end

      # Evaluate the endpoint's quality expectations over the records and record
      # @quality_score / @quality_passed for persistence + provenance.
      def evaluate_quality(records)
        result = Ai::DataSources::QualityService.new(endpoint).evaluate(records)
        @quality_score = result[:quality_score]
        @quality_passed = result[:passed]
        Array(result[:anomalies]).each { |a| @anomalies << "quality_#{a}" }
        @anomalies << "quality_failed" if @quality_passed == false
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] quality evaluation failed for #{safe_slug}: #{e.message}")
      end

      # Serve the last-known-good cached payload in place of a quarantined batch.
      # Reads (does not write) the response cache; flags @quarantined so finalize
      # skips caching the bad payload. Falls back to an empty batch when no prior
      # good payload exists.
      def quarantine_records(_bad_records)
        @quarantined = true
        @anomalies << "quarantined"

        cached = Ai::DataSources::ResponseCacheService.read(
          data_source: data_source, endpoint: endpoint, params: cache_params
        )
        good = cached.is_a?(Hash) ? (cached["data"] || cached[:data]) : nil
        Array(good)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] quarantine last-known-good read failed: #{e.message}")
        []
      end

      def decode_records(raw_body)
        records = adapter.parse(raw_body, endpoint: endpoint)
        records.is_a?(Array) ? records : []
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] decode failed for #{safe_slug}: #{e.message}")
        @anomalies << "decode_error"
        []
      end

      # Returns true/false when a schema is configured, or nil when no schema is
      # set (schema_valid is therefore "unknown", not "valid").
      def validate_schema(records)
        schema = endpoint.respond_to?(:response_schema) ? endpoint.response_schema : nil
        return nil if schema.blank?

        validator = JsonSchemaValidator.new(schema)
        validator.valid?(records)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] schema validation error for #{safe_slug}: #{e.message}")
        @anomalies << "schema_validation_error"
        nil
      end

      def normalize_records(records)
        rules = endpoint.respond_to?(:response_mapping) ? (endpoint.response_mapping || {}) : {}
        Ai::DataSources::NormalizationService.new(rules).apply(records)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] normalization error for #{safe_slug}: #{e.message}")
        @anomalies << "normalization_error"
        [records, []]
      end

      # ----------------------------------------------------------------------
      # (9)+(10) persist (redacted) + audit chain + cost + cache + envelope
      # ----------------------------------------------------------------------

      # Turns an internal fetch result into the final FetchEnvelope, recording
      # quota usage, persisting the (redacted) query row through the audit hash
      # chain, emitting a cost row, and writing the cache on a fresh success.
      def finalize(result)
        from_cache = result[:from_cache] == true

        # (8) shared per-source + per-agent request accounting. A cache HIT is still
        # a governed read (it counts against quota windows) but carries no response
        # bytes; a fresh fetch records the real byte count.
        record_request_usage(result)

        # (8b) effectiveness/trust accounting. Count only LIVE fetches toward the
        # source's rolled-up scoring counters — a cache HIT did not exercise the
        # upstream, so it must not move the success/failure ratio or freshness. The
        # short-circuit envelopes (kill flag / quota) never reach finalize, so they
        # are likewise excluded.
        record_effectiveness(result) unless from_cache

        prov = result[:provenance] || {}

        # (9) persist the query row with everything REDACTED before it touches the
        # database, linked into the Audit::LogIntegrityService SHA256 hash chain.
        # Served stage: an explicit override (e.g. "stale_if_error" /
        # "stale_while_revalidate") wins; otherwise a cache hit is "cache" and a
        # live fetch is "fresh".
        served_stage = result[:served_stage] || (from_cache ? "cache" : "fresh")

        query_row = persist_query(
          status: result[:status],
          http_status: result[:http_status],
          data: result[:data],
          provenance: prov,
          bytes_in: result[:bytes_in].to_i,
          error: result[:error],
          cached: from_cache,
          served_stage: served_stage,
          redacted_snippet: result[:redacted_snippet]
        )

        # (9) one cost-attribution row per fetch (including cache hits — egress is
        # zero-byte but the access is still attributed for auditability).
        emit_cost_attribution(result, query_row)

        # (10) write the cache only on a FRESH success (never re-write a hit, never
        # cache an error). A quarantined fetch is HTTP-successful but failed quality:
        # NEVER cache the bad payload — the served data is last-known-good, which is
        # already cached, so re-writing would either be a no-op or poison the cache.
        write_cache(result) if result[:success] && !from_cache && !@quarantined

        build_envelope(result, prov)
      end

      def build_envelope(result, prov)
        {
          success: result[:success],
          data: result[:data] || [],
          provenance: prov,
          status: result[:status],
          duration_ms: elapsed_ms,
          bytes: result[:bytes_in].to_i,
          error: result[:error]
        }
      end

      # (8) Shared per-source quota counter + per-agent counter. Only real network
      # fetches reach here (cache hits record separately).
      def record_request_usage(result)
        data_source.record_request!(bytes: result[:bytes_in].to_i)
        record_agent_request!
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] request usage record failed: #{e.message}")
      end

      # (8b) Roll a LIVE fetch outcome into the source's effectiveness scoring
      # counters (usage_count + positive/negative + last_used_at, periodic
      # recalculate_effectiveness!). Freshness for this query is derived from the
      # served cache age: a fresh fetch (age 0) is maximally fresh (1.0) and decays
      # linearly over a 7-day window, mirroring Ai::DataSource#freshness_score so a
      # stale_while_revalidate / stale_if_error live serve is scored honestly.
      # Nil-safe and isolated: any failure here must never disturb the
      # FetchEnvelope, so it is fully rescued.
      def record_effectiveness(result)
        return unless data_source.respond_to?(:record_query!)

        outcome = result[:success] ? STATUS_SUCCESS : "failure"
        data_source.record_query!(
          outcome: outcome,
          freshness: derived_freshness(result),
          agent: agent
        )
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] effectiveness record failed: #{e.message}")
      end

      # Map the served cache age (seconds) to a 0..1 freshness signal. A live
      # fetch is age 0 -> 1.0; a stale serve decays linearly to 0.0 at the 7-day
      # freshness window. Returns nil when the age is unknown so record_query!
      # falls back to its recency-derived default rather than a fabricated value.
      def derived_freshness(result)
        prov = result[:provenance] || {}
        age = prov[:cache_age_seconds] || prov["cache_age_seconds"]
        return nil if age.nil?

        days = age.to_f / 86_400.0
        (1.0 - (days / 7.0)).clamp(0.0, 1.0).round(4)
      rescue StandardError
        nil
      end

      # (9) Persist ai_data_source_queries. Every operator/caller-visible string is
      # routed through Ai::Security::PiiRedactionService BEFORE it is written. The
      # row is then tied into the audit hash chain via a companion AuditLog whose
      # before_create integrity hook (Audit::LogIntegrityService) seals it; the
      # resulting integrity_hash + sequence_number are mirrored into the query
      # metadata so the linkage is queryable from the query row itself.
      def persist_query(status:, http_status:, data:, provenance:, bytes_in:, error:,
                        cached:, served_stage:, redacted_snippet: nil)
        redacted_url = provenance[:source_url] || provenance["source_url"] || redact_url(@last_absolute_url)
        redacted_error = error.present? ? redact_message(error) : nil

        metadata = {
          "anomalies" => Array(provenance[:anomalies] || provenance["anomalies"]),
          "declared_vs_detected_content_type" => provenance[:declared_vs_detected_content_type] ||
            provenance["declared_vs_detected_content_type"],
          "charset" => provenance[:charset] || provenance["charset"],
          "applied_encoding" => provenance[:applied_encoding] || provenance["applied_encoding"],
          "redacted_params" => redact_params(params),
          "redacted_response_snippet" => redacted_snippet
        }.compact

        query = Ai::DataSourceQuery.new(
          data_source: data_source,
          endpoint: endpoint,
          account_id: account&.id,
          requesting_agent_id: agent&.id,
          principal: principal_label,
          purpose: endpoint&.slug,
          params_hash: params_digest,
          redacted_url: redacted_url,
          redaction_applied: true,
          status: status,
          http_status: http_status,
          duration_ms: elapsed_ms,
          bytes_in: bytes_in,
          rows_returned: Array(data).size,
          cached: cached,
          served_stage: served_stage,
          response_sha256: provenance[:response_sha256] || provenance["response_sha256"],
          schema_valid: schema_valid_value(provenance),
          masking_applied: true,
          correlation_id: correlation_id,
          error: redacted_error,
          # Phase 2b opt-in outcomes (nil when the stage did not run).
          quality_score: @quality_score,
          quality_passed: @quality_passed,
          quarantined: @quarantined,
          schema_drift: @schema_drift,
          metadata: metadata
        )
        query.save!

        chain_into_audit_log(query, status)
        query
      rescue StandardError => e
        Rails.logger.error("[DataSources::QueryService] failed to persist query row for #{safe_slug}: #{e.message}")
        nil
      end

      # Tie the persisted query into the SHA256 audit hash chain. AuditLog's
      # before_create :apply_integrity_hash invokes Audit::LogIntegrityService,
      # which assigns sequence_number + previous_hash + integrity_hash; we mirror
      # those back onto the query metadata so the chain anchor is discoverable from
      # the query without a join.
      def chain_into_audit_log(query, status)
        return unless account

        audit = AuditLog.log_action(
          action: audit_action_for(status),
          resource: query,
          user: user,
          account: account,
          source: "integration",
          new_values: {
            "status" => status,
            "response_sha256" => query.response_sha256,
            "rows_returned" => query.rows_returned,
            "data_source_slug" => data_source.slug,
            "endpoint_slug" => endpoint&.slug
          },
          metadata: { correlation_id: correlation_id }
        )

        mirror_chain_anchor(query, audit)
      rescue StandardError => e
        # Audit-chain failures must never break the fetch; the query row persists.
        Rails.logger.error("[DataSources::QueryService] audit-chain linkage failed for query #{query&.id}: #{e.message}")
      end

      def mirror_chain_anchor(query, audit)
        return unless query && audit&.persisted?

        anchor = {
          "audit_log_id" => audit.id,
          "integrity_hash" => audit.integrity_hash,
          "previous_hash" => audit.previous_hash,
          "sequence_number" => audit.sequence_number
        }.compact
        query.update_columns(metadata: query.metadata.merge("audit_chain" => anchor))
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] could not mirror chain anchor: #{e.message}")
      end

      # A successful or cache-served read maps to api_request; everything else
      # (error/timeout/rate_limited/blocked) maps to api_request_failed.
      def audit_action_for(status)
        [STATUS_SUCCESS, STATUS_CACHED].include?(status) ? AUDIT_ACTION_SUCCESS : AUDIT_ACTION_FAILURE
      end

      # (9) Emit exactly one Ai::CostAttribution row per fetch via the additive
      # builder added to the model.
      def emit_cost_attribution(result, query_row)
        return unless account

        Ai::CostAttribution.from_data_source_query(
          account: account,
          data_source: data_source,
          query: query_row,
          bytes: result[:bytes_in].to_i,
          agent: agent
        )
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] cost attribution failed for #{safe_slug}: #{e.message}")
      end

      # (10) Persist the cacheable payload for the next caller. Mirrors the
      # singleflight write but is safe to call outside the recompute block too
      # (idempotent setex).
      def write_cache(result)
        ResponseCacheService.write(
          data_source: data_source,
          endpoint: endpoint,
          params: cache_params,
          payload: cacheable_payload(result)
        )
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] cache write failed: #{e.message}")
      end

      # ----------------------------------------------------------------------
      # provenance + envelopes
      # ----------------------------------------------------------------------

      def build_provenance(absolute_url:, detection:, schema_valid:, record_count:,
                           response_sha256:, normalization_provenance:, from_cache:)
        {
          slug: data_source.slug,
          endpoint_id: endpoint&.id,
          fetched_at: Time.current.utc.iso8601,
          from_cache: from_cache,
          cache_age_seconds: 0,
          response_sha256: response_sha256,
          source_url: redact_url(absolute_url),
          declared_vs_detected_content_type: {
            declared: detection[:declared_format],
            detected: detection[:detected_format],
            content_type: detection[:content_type],
            mismatch: detection[:mismatch]
          },
          charset: detection[:charset],
          applied_encoding: detection[:charset],
          schema_valid: schema_valid,
          record_count: record_count,
          anomalies: @anomalies.uniq,
          normalization: normalization_provenance
        }
      end

      def disabled_envelope
        prov = base_provenance.merge(anomalies: ["source_disabled"])
        persist_query(
          status: STATUS_BLOCKED, http_status: nil, data: [], provenance: prov,
          bytes_in: 0, error: "data source disabled by kill flag", cached: false,
          served_stage: "fresh"
        )
        {
          success: false, data: [], provenance: prov, status: STATUS_BLOCKED,
          duration_ms: elapsed_ms, bytes: 0,
          error: "data source disabled by kill flag"
        }
      end

      def rate_limited_envelope(quota)
        prov = base_provenance.merge(
          anomalies: ["rate_limited"],
          retry_after: quota[:retry_after],
          limit: quota[:limit]
        )
        persist_query(
          status: STATUS_RATE_LIMITED, http_status: 429, data: [], provenance: prov,
          bytes_in: 0, error: "quota exceeded (#{quota[:limit]})", cached: false,
          served_stage: "fresh"
        )
        {
          success: false, data: [], provenance: prov, status: STATUS_RATE_LIMITED,
          duration_ms: elapsed_ms, bytes: 0,
          error: "quota exceeded (#{quota[:limit]})",
          retry_after: quota[:retry_after]
        }
      end

      def error_envelope(status:, error:)
        prov = base_provenance.merge(anomalies: @anomalies.uniq.presence || ["error"])
        {
          success: false, data: [], provenance: prov, status: status,
          duration_ms: elapsed_ms, bytes: 0, error: error
        }
      end

      # Build the internal failure result that finalize() can persist + return.
      def fetch_failure(status, message, absolute_url:)
        @anomalies << "fetch_failed"
        {
          success: false,
          status: status,
          http_status: nil,
          data: [],
          provenance: build_provenance(
            absolute_url: absolute_url,
            detection: empty_detection,
            schema_valid: nil,
            record_count: 0,
            response_sha256: nil,
            normalization_provenance: [],
            from_cache: false
          ),
          raw_body: nil,
          bytes_in: 0,
          error: redact_message(message),
          redacted_snippet: nil
        }
      end

      def empty_detection
        { declared_format: nil, detected_format: nil, content_type: nil, mismatch: false, charset: nil }
      end

      # Minimal provenance for short-circuit envelopes (kill flag / quota) where no
      # request is dispatched.
      def base_provenance
        {
          slug: data_source.slug,
          endpoint_id: endpoint&.id,
          fetched_at: Time.current.utc.iso8601,
          from_cache: false,
          cache_age_seconds: 0,
          response_sha256: nil,
          source_url: nil,
          declared_vs_detected_content_type: nil,
          charset: nil,
          applied_encoding: nil,
          schema_valid: nil,
          record_count: 0,
          anomalies: []
        }
      end

      # ----------------------------------------------------------------------
      # credential health accounting (8)
      # ----------------------------------------------------------------------

      # Only DB-backed credentials record success/failure; the Vault view is a
      # read-only adapter with no counters.
      def record_success(credential)
        return unless credential.respond_to?(:record_success!)

        credential.record_success!
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] credential success record failed: #{e.message}")
      end

      def record_failure(credential, message)
        return unless credential.respond_to?(:record_failure!)

        credential.record_failure!(redact_message(message))
      rescue StandardError => e
        Rails.logger.warn("[DataSources::QueryService] credential failure record failed: #{e.message}")
      end

      # ----------------------------------------------------------------------
      # redaction helpers (9) — PII/secret scrubbing before persistence
      # ----------------------------------------------------------------------

      def redactor
        @redactor ||= Ai::Security::PiiRedactionService.new(account: account)
      end

      # Query-param keys whose VALUES are masked unconditionally — defense in
      # depth so non-standard secret params (?token=, ?sig=, ?secret=, ?key= ...)
      # never persist verbatim into the query log or cached provenance even when
      # PiiRedactionService's heuristics do not recognize them.
      SENSITIVE_QUERY_KEY = /\A(?:.*[_-])?(?:api[_-]?key|key|tokens?|access[_-]?token|refresh[_-]?token|id[_-]?token|secret|client[_-]?secret|auth|authorization|password|passwd|pwd|sig|signature|sign|credential|session|cookie)\z/i

      # Mask values of sensitive query params by key, regardless of PII match.
      def mask_sensitive_query_params(url)
        uri = URI.parse(url.to_s)
        return url.to_s if uri.query.blank?

        masked = URI.decode_www_form(uri.query).map do |(k, v)|
          SENSITIVE_QUERY_KEY.match?(k.to_s) ? [k, "[REDACTED]"] : [k, v]
        end
        uri.query = URI.encode_www_form(masked)
        uri.to_s
      rescue StandardError
        strip_query_string(url)
      end

      # Redact a URL (query string may carry api keys / tokens / PII). Logging is
      # disabled on these calls to avoid recursive audit writes during a fetch.
      def redact_url(url)
        return nil if url.blank?

        masked = mask_sensitive_query_params(url)
        return masked unless account

        redactor.redact(text: masked, context: { source_type: "DataSourceQuery", field_path: "source_url" }, log: false)[:redacted_text]
      rescue StandardError
        # On redaction failure, strip the query string entirely rather than risk
        # leaking secrets that live there.
        strip_query_string(url)
      end

      def strip_query_string(url)
        uri = URI.parse(url.to_s)
        uri.query = nil
        uri.to_s
      rescue StandardError
        "[REDACTED:URL]"
      end

      def redact_params(raw_params)
        return {} if raw_params.blank?
        return raw_params unless account

        raw_params.each_with_object({}) do |(k, v), memo|
          memo[k.to_s] = SENSITIVE_QUERY_KEY.match?(k.to_s) ? "[REDACTED]" : redact_scalar(v)
        end
      rescue StandardError
        {}
      end

      def redact_scalar(value)
        case value
        when Hash then value.transform_values { |v| redact_scalar(v) }
        when Array then value.map { |v| redact_scalar(v) }
        when String then redactor.redact(text: value, context: { source_type: "DataSourceQuery", field_path: "param" }, log: false)[:redacted_text]
        else value
        end
      end

      def redacted_snippet(raw_body)
        return nil if raw_body.blank?

        snippet = raw_body.to_s.byteslice(0, RESPONSE_SNIPPET_LIMIT).to_s
        snippet = snippet.scrub("") unless snippet.valid_encoding?
        return snippet unless account

        redactor.redact(text: snippet, context: { source_type: "DataSourceQuery", field_path: "response_snippet" }, log: false)[:redacted_text]
      rescue StandardError
        nil
      end

      def redact_message(message)
        return nil if message.blank?
        return message.to_s unless account

        redactor.redact(text: message.to_s, context: { source_type: "DataSourceQuery", field_path: "error" }, log: false)[:redacted_text]
      rescue StandardError
        message.to_s
      end

      # ----------------------------------------------------------------------
      # small helpers
      # ----------------------------------------------------------------------

      def adapter
        @adapter ||= Ai::DataSources::Adapters::Registry.for(data_source)
      end

      # Resolve the request URL against the source base URL and remember it for
      # provenance/persistence (always stored REDACTED).
      def resolved_request_url(request)
        url = request[:url].to_s
        base = data_source.respond_to?(:api_base_url) ? data_source.api_base_url.to_s : ""

        absolute =
          if url.empty?
            base
          elsif url =~ %r{\Ahttps?://}i
            url
          else
            join_url(base, url)
          end

        @last_absolute_url = absolute
        absolute
      end

      def join_url(base, path)
        return path if base.empty?

        URI.join(base.end_with?("/") ? base : "#{base}/", path.delete_prefix("/")).to_s
      rescue URI::InvalidURIError
        "#{base.chomp('/')}/#{path.delete_prefix('/')}"
      end

      def response_content_type(response)
        headers = response.respond_to?(:headers) ? response.headers : {}
        headers["content-type"] || headers["Content-Type"]
      end

      def schema_valid_value(provenance)
        provenance.key?(:schema_valid) ? provenance[:schema_valid] : provenance["schema_valid"]
      end

      def params_digest
        Digest::SHA256.hexdigest(stable_params_json)[0, 64]
      rescue StandardError
        nil
      end

      def stable_params_json
        deep_sort(params).to_json
      rescue StandardError
        params.to_s
      end

      def deep_sort(obj)
        case obj
        when Hash then obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_sort(v) }.sort.to_h
        when Array then obj.map { |v| deep_sort(v) }
        else obj
        end
      end

      def principal_label
        if agent&.id
          "agent:#{agent.id}"
        elsif user&.id
          "user:#{user.id}"
        else
          "system"
        end
      end

      def correlation_id
        @correlation_id ||= SecureRandom.uuid
      end

      def safe_slug
        "#{data_source&.slug}/#{endpoint&.slug}"
      rescue StandardError
        "unknown"
      end

      def redis_client
        Powernode::Redis.client
      rescue StandardError
        nil
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms
        ((monotonic_now - @started_at) * 1000).round
      end
    end
  end
end
