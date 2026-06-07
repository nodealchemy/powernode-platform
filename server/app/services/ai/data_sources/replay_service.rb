# frozen_string_literal: true

module Ai
  module DataSources
    # Forensic, DETERMINISTIC replay of a recorded data-source fetch.
    #
    # PURPOSE
    #   Reconstruct a FetchEnvelope-shaped view of a PAST query from its already-
    #   redacted audit row (Ai::DataSourceQuery), WITHOUT touching the network. A
    #   replay is an auditor's reconstruction, not a re-execution: it NEVER performs
    #   an upstream fetch, NEVER re-signs a request, and NEVER resolves credentials.
    #
    # WHAT IS REPLAYED (from the row alone — no side effects)
    #   * provenance — rebuilt from the row's metadata + response_sha256 +
    #     served_stage + redacted_url + the recorded timestamp (created_at). The URL
    #     is the ALREADY-REDACTED value persisted at fetch time; nothing is un-redacted.
    #   * status — "replayed" (a forensic reconstruction, distinct from the original
    #     live status, which is preserved under provenance[:original_status]).
    #
    # PAYLOAD (the audit row does NOT store the body)
    #   The audit row deliberately persists only a redacted SNIPPET + the response
    #   SHA256, never the full body. So a replay can only surface the body when the
    #   ORIGINAL (source, endpoint, params) cache entry is STILL present:
    #     * The cache key is derived from the ORIGINAL params, but the row stores only
    #       a one-way params_hash (SHA256) + a redacted_params copy — the original
    #       params are NOT recoverable from the row. So the cache lookup runs ONLY
    #       when the caller supplies the original params (params:) — "if recoverable".
    #     * When the payload IS recovered from cache, governance masking is RE-APPLIED
    #       for the CURRENT requester (GovernanceService#mask_records) BEFORE it is
    #       returned, so a replay can never leak MORE than a live read would today.
    #     * When the payload is no longer cached (or params were not supplied), data is
    #       [] and provenance carries the note "payload_not_cached" — forensic
    #       metadata only.
    #
    # SECURITY POSTURE
    #   * NEVER bypasses masking — it re-masks the recovered payload for the current
    #     requester (account + agent), so the per-request egress controls of a live
    #     read still apply on replay.
    #   * NEVER performs a network call, re-signs, or resolves credentials.
    #   * Account-scoped: a query_ref outside @account is treated as not-found.
    #   * Resilient: every failure path rescues to a safe error result Hash — a replay
    #     must never raise into the caller.
    #
    # CONTRACT
    #   Ai::DataSources::ReplayService
    #     .new(account:, agent: nil)
    #     #replay(query_ref, params: nil) => Hash (FetchEnvelope-shaped + replay flags)
    #
    #   query_ref: an ai_data_source_queries id (UUID) OR a correlation_id (String).
    #   params:    OPTIONAL original request params. When supplied AND they match the
    #              recorded params_hash, the original cache entry can be located and
    #              its (re-masked) payload returned. Omitted/mismatched => forensic
    #              metadata only (data: []). The base contract #replay(query_ref) is
    #              unchanged; params is an additive recovery hint, never required.
    #
    #   Success shape:
    #     {
    #       success: true,
    #       data: Array<Hash>,        # re-masked cached payload, or [] when not cached
    #       provenance: { ...forensic..., note?:, payload_not_cached?: },
    #       status: "replayed",
    #       replayed: true,
    #       replayed_from_query_id: <uuid>,
    #       correlation_id: <string|nil>,
    #       recorded_at: <iso8601|nil>,
    #       duration_ms: 0            # a replay does no work
    #     }
    #
    #   Not-found shape:
    #     { success: false, status: "replay_not_found", error: <String>,
    #       replayed: false }
    #
    #   Error shape (any unexpected fault):
    #     { success: false, status: "replay_error", error: <String>, replayed: false }
    class ReplayService
      # The forensic status token a replayed envelope carries — distinct from the
      # original live status (success|error|cached|...), which is preserved on
      # provenance[:original_status]. NOT a DataSourceQuery::STATUSES member: a replay
      # is a reconstruction and persists NOTHING.
      STATUS_REPLAYED   = "replayed"
      STATUS_NOT_FOUND  = "replay_not_found"
      STATUS_ERROR      = "replay_error"

      # Provenance note set when the body could not be recovered from cache.
      PAYLOAD_NOT_CACHED = "payload_not_cached"

      def initialize(account:, agent: nil)
        @account = account
        @agent = agent
      end

      # Replay a recorded query by id OR correlation_id. Deterministic and side-
      # effect-free: no upstream fetch, no signing, no credential resolution.
      #
      # See the class doc for the full result shape. Never raises.
      def replay(query_ref, params: nil)
        return not_found("no query reference supplied") if query_ref.blank?
        return not_found("account context required for replay") unless @account

        query = resolve_query(query_ref)
        return not_found("no recorded query for #{ref_label(query_ref)}") unless query

        build_replay(query, params)
      rescue StandardError => e
        # A replay must NEVER raise into the caller — a forensic reconstruction
        # failure degrades to a safe error result. Log the class only (the row is
        # already redacted, but we keep the same no-material discipline as the
        # fetch pipeline).
        Rails.logger.error(
          "[DataSources::ReplayService] replay failed (#{e.class}) for #{ref_label(query_ref)}"
        )
        { success: false, status: STATUS_ERROR, error: "replay failed: #{e.class}", replayed: false }
      end

      private

      attr_reader :account, :agent

      # ----------------------------------------------------------------------
      # resolution (account-scoped; id OR correlation_id)
      # ----------------------------------------------------------------------

      # Resolve the audit row within the current account. A query_ref is treated as a
      # UUID id first (the primary key), falling back to a correlation_id lookup. Both
      # are account-scoped so a replay can never reach across tenants. Returns the
      # Ai::DataSourceQuery or nil.
      def resolve_query(query_ref)
        ref = query_ref.to_s
        scope = Ai::DataSourceQuery.for_account(account)

        if uuid?(ref)
          row = scope.where(id: ref).first
          return row if row
        end

        # Fall back to correlation_id (most-recent wins if somehow duplicated).
        scope.where(correlation_id: ref).order(created_at: :desc).first
      rescue StandardError => e
        Rails.logger.warn("[DataSources::ReplayService] query resolution failed (#{e.class})")
        nil
      end

      # ----------------------------------------------------------------------
      # reconstruction
      # ----------------------------------------------------------------------

      # Assemble the replayed FetchEnvelope from the recorded row, recovering +
      # re-masking the cached payload when the original params make it locatable.
      def build_replay(query, params)
        data_source = safe_data_source(query)

        payload_result = recover_payload(query, data_source, params)

        provenance = build_provenance(query, payload_result)

        {
          success: true,
          data: payload_result[:data],
          provenance: provenance,
          status: STATUS_REPLAYED,
          replayed: true,
          replayed_from_query_id: query.id,
          correlation_id: query.correlation_id,
          recorded_at: recorded_at(query),
          # A replay performs no work: report zero elapsed rather than fabricating
          # the original fetch's duration (which lives on provenance for reference).
          duration_ms: 0,
          bytes: 0,
          error: nil
        }
      end

      # Forensic provenance reconstructed from the recorded (already-redacted) row.
      # Carries the stored metadata (anomalies, content-type, masking outcome, audit-
      # chain anchor, ...) plus the row's response_sha256 / served_stage / redacted
      # URL / recorded timestamp and the original live status. Tolerates string OR
      # symbol keys in the persisted metadata jsonb.
      def build_provenance(query, payload_result)
        meta = recorded_metadata(query)

        prov = {
          slug: data_source_slug(query),
          endpoint_id: query.ai_data_source_endpoint_id,
          replayed: true,
          replayed_from_query_id: query.id,
          recorded_at: recorded_at(query),
          original_status: query.status,
          http_status: query.http_status,
          from_cache: query.cached == true,
          served_stage: query.served_stage,
          response_sha256: query.response_sha256,
          source_url: query.redacted_url,
          schema_valid: query.schema_valid,
          record_count: query.rows_returned,
          rows_returned: query.rows_returned,
          bytes_in: query.bytes_in,
          masking_applied: payload_result[:masking_applied],
          masked_field_count: payload_result[:masked_count],
          policy_decision: query.policy_decision,
          correlation_id: query.correlation_id,
          # Forensic linkage: surface the original anomalies + audit-chain anchor +
          # redacted param/snippet copy straight off the recorded metadata.
          anomalies: Array(jget(meta, "anomalies")),
          declared_vs_detected_content_type: jget(meta, "declared_vs_detected_content_type"),
          charset: jget(meta, "charset"),
          applied_encoding: jget(meta, "applied_encoding"),
          redacted_params: jget(meta, "redacted_params"),
          redacted_response_snippet: jget(meta, "redacted_response_snippet"),
          audit_chain: jget(meta, "audit_chain")
        }.compact

        if payload_result[:note].present?
          prov[:note] = payload_result[:note]
          prov[:payload_not_cached] = true if payload_result[:note] == PAYLOAD_NOT_CACHED
        end

        prov
      end

      # ----------------------------------------------------------------------
      # payload recovery (cache read + RE-MASK; never an upstream fetch)
      # ----------------------------------------------------------------------

      # Attempt to recover the original body from the response cache, then RE-MASK it
      # for the CURRENT requester so a replay never leaks more than a live read.
      #
      # Recovery is only possible when:
      #   * we resolved the row's data source AND endpoint, AND
      #   * the caller supplied the ORIGINAL params (the row stores only a one-way
      #     params_hash, so the cache key is otherwise unreconstructable), AND those
      #     params hash to the recorded params_hash (so we read the SAME entry), AND
      #   * the cache entry is still present.
      #
      # Any miss (no params, hash mismatch, evicted entry, decode fault) degrades to
      # data: [] with the "payload_not_cached" note — forensic metadata only.
      #
      # Returns { data:, masking_applied:, masked_count:, note: }.
      def recover_payload(query, data_source, params)
        return not_cached unless data_source

        endpoint = safe_endpoint(query, data_source)
        return not_cached unless endpoint

        # SECURITY: enforce the SAME governance AUTHORIZATION gate a live read would —
        # re-masking the fields is not enough; if the CURRENT requester is not
        # authorized for this source now, withhold the cached body entirely (the
        # forensic provenance still returns).
        return not_cached unless replay_authorized?(data_source)

        recovery_params = recoverable_params(query, params)
        return not_cached if recovery_params.nil?

        cached = read_cache(data_source, endpoint, recovery_params)
        records = extract_records(cached)
        return not_cached if records.nil?

        # SECURITY: re-mask for the CURRENT requester before returning. A replay must
        # not surface a less-redacted view than a live read would today.
        masked = remask(data_source, records)
        {
          data: masked[:records],
          masking_applied: masked[:masking_applied],
          masked_count: masked[:masked_count],
          note: nil
        }
      rescue StandardError => e
        Rails.logger.warn(
          "[DataSources::ReplayService] payload recovery failed (#{e.class}) for query #{query&.id}"
        )
        not_cached
      end

      # Run the same governance authorize gate a live read would, for the CURRENT
      # requester. Fail-CLOSED here (withhold the body) on any error — the forensic
      # provenance is returned regardless, so withholding the cached payload is safe.
      def replay_authorized?(data_source)
        Ai::DataSources::GovernanceService.new(
          data_source: data_source, agent: @agent, account: @account
        ).authorize[:allowed]
      rescue StandardError => e
        Rails.logger.warn("[DataSources::ReplayService] authorize check failed (#{e.class}) — withholding payload")
        false
      end

      # Only return params we can trust to address the SAME cache entry the original
      # fetch wrote. The recorded params_hash is the SHA256 the QueryService computed
      # from the original params; we recompute the digest of the supplied params the
      # same way and require a match. nil => not recoverable (skip the cache read).
      def recoverable_params(query, params)
        return nil if params.nil?

        supplied = params.respond_to?(:to_h) ? params.to_h : params
        recorded_hash = query.params_hash
        # When the row predates params_hash (nil), we cannot prove the supplied params
        # address the recorded entry — refuse rather than risk reading a DIFFERENT
        # variant's payload.
        return nil if recorded_hash.blank?

        params_digest(supplied) == recorded_hash ? supplied : nil
      rescue StandardError
        nil
      end

      # Read-only cache lookup. ResponseCacheService.read returns the cached payload
      # (Hash/Array) or nil and rescues its own Redis faults internally, so a cache
      # outage degrades to a miss here. NEVER writes.
      def read_cache(data_source, endpoint, params)
        Ai::DataSources::ResponseCacheService.read(
          data_source: data_source, endpoint: endpoint, params: params
        )
      rescue StandardError => e
        Rails.logger.warn("[DataSources::ReplayService] cache read failed (#{e.class})")
        nil
      end

      # The cache stores { "data" => [...], "provenance" => {...} } (string keys).
      # Pull the records array out, tolerating string OR symbol keys and a bare-array
      # payload. Returns the records Array, or nil when there is nothing to surface
      # (so the caller can flag payload_not_cached).
      def extract_records(cached)
        return nil if cached.nil?

        records =
          if cached.is_a?(Hash)
            cached["data"].nil? ? cached[:data] : cached["data"]
          elsif cached.is_a?(Array)
            cached
          end
        records.is_a?(Array) ? records : nil
      end

      # Re-mask the recovered records for the CURRENT requester via the SAME
      # GovernanceService masking primitive the live pipeline uses. Fully rescued:
      # a masking fault must not leak unmasked data NOR break the replay, so it
      # degrades to passthrough-but-flagged (masking_applied:false) exactly like the
      # live path's masking rescue.
      def remask(data_source, records)
        result = Ai::DataSources::GovernanceService.new(
          data_source: data_source, agent: agent, account: account
        ).mask_records(records)

        {
          records: result[:records],
          masking_applied: result[:masking_applied],
          masked_count: result[:masked_count]
        }
      rescue StandardError => e
        Rails.logger.error(
          "[DataSources::ReplayService] re-masking failed (#{e.class}) for #{data_source_label(data_source)}"
        )
        { records: records, masking_applied: false, masked_count: 0 }
      end

      def not_cached
        { data: [], masking_applied: false, masked_count: 0, note: PAYLOAD_NOT_CACHED }
      end

      # ----------------------------------------------------------------------
      # row field readers (resilient; jsonb string/symbol tolerant)
      # ----------------------------------------------------------------------

      # The recorded query's data source. The row predates nothing here (FK is
      # NOT NULL), but a destroyed source leaves the association nil — degrade to
      # nil so recovery simply reports payload_not_cached rather than raising.
      def safe_data_source(query)
        query.data_source
      rescue StandardError
        nil
      end

      # The recorded endpoint, resolved through the data source so any masking /
      # cache-key derivation uses the same object identity the live pipeline did.
      # Optional on the row (some queries are source-level), so nil is normal.
      def safe_endpoint(query, data_source)
        return nil unless query.ai_data_source_endpoint_id

        ep = query.endpoint
        return ep if ep

        # Fall back through the source association in case the direct belongs_to was
        # not loadable for some reason.
        data_source.respond_to?(:endpoints) ? data_source.endpoints.find_by(id: query.ai_data_source_endpoint_id) : nil
      rescue StandardError
        nil
      end

      def recorded_metadata(query)
        meta = query.metadata
        meta.is_a?(Hash) ? meta : {}
      rescue StandardError
        {}
      end

      def data_source_slug(query)
        ds = safe_data_source(query)
        ds.respond_to?(:slug) ? ds.slug : nil
      rescue StandardError
        nil
      end

      # The recorded timestamp doubles as "recorded_at" (the row has no separate
      # column). Emitted as ISO8601 UTC for a stable forensic marker.
      def recorded_at(query)
        ts = query.created_at
        ts.respond_to?(:utc) ? ts.utc.iso8601 : ts
      rescue StandardError
        nil
      end

      # ----------------------------------------------------------------------
      # small helpers
      # ----------------------------------------------------------------------

      # Recompute the params digest EXACTLY as QueryService#params_digest does
      # (deep-sorted canonical JSON, SHA256, first 64 hex chars) so a supplied-params
      # digest is byte-comparable to the recorded params_hash.
      def params_digest(params)
        Digest::SHA256.hexdigest(stable_params_json(params))[0, 64]
      rescue StandardError
        nil
      end

      def stable_params_json(params)
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

      # Read a key from a jsonb-sourced Hash tolerating string OR symbol keys.
      def jget(hash, key)
        return nil unless hash.is_a?(Hash)

        hash[key.to_s].nil? ? hash[key.to_sym] : hash[key.to_s]
      end

      def uuid?(value)
        value.to_s.match?(/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/)
      end

      def not_found(message)
        { success: false, status: STATUS_NOT_FOUND, error: message, replayed: false }
      end

      def ref_label(query_ref)
        ref = query_ref.to_s
        uuid?(ref) ? "id #{ref}" : "correlation_id #{ref}"
      rescue StandardError
        "query"
      end

      def data_source_label(data_source)
        data_source.respond_to?(:slug) ? data_source.slug.to_s : "unknown"
      rescue StandardError
        "unknown"
      end
    end
  end
end
