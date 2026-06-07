# frozen_string_literal: true

module Ai
  module DataSources
    # Periodic schema synchronisation for data-source endpoints.
    #
    # Where Ai::DataSources::SchemaDriftService records a single version when given
    # a schema, and the QueryService records drift inline on every fetch that opts
    # into track_schema, the SchemaSyncService is the BATCH counterpart: a cron tick
    # (worker -> internal controller) that walks endpoints needing a schema refresh,
    # samples each one, infers a JSON-Schema-shaped snapshot, and appends a version
    # via SchemaDriftService#record_version!. When an endpoint has no stored
    # response_schema yet, the inferred schema is also persisted onto the endpoint
    # so subsequent fetches have a baseline to validate against.
    #
    # CONTRACT:
    #   Ai::DataSources::SchemaSyncService.new(account = nil)
    #     #sync(limit:) => { synced: Integer, errors: Array<{endpoint_id:, error:}> }
    #
    # Endpoint selection (an endpoint is "due" when):
    #   * track_schema is true (operator opted into drift tracking), OR
    #   * response_schema is blank ({} / nil) — no baseline captured yet.
    # Only endpoints on ACTIVE sources are considered; account-scoped when an
    # account is supplied. Per-endpoint failures are collected and NEVER abort the
    # batch (mirrors MonitorService#tick semantics).
    #
    # Sampling strategy:
    #   1. Reuse the most recent SUCCESSFUL query's inferred shape when one is
    #      available cheaply — but since the query log does not persist the decoded
    #      payload, in practice we
    #   2. run a governed sample fetch via the QueryService (the same
    #      kill-flag/quota/cache/circuit-breaker/decode pipeline as any read) and
    #      infer the schema from its canonical records.
    # The sample fetch respects the source quota; a throttled/blocked/errored
    # sample is recorded as a skip (not a hard error) so a busy source does not
    # spam the error list.
    class SchemaSyncService
      # JSON type tokens used by the inferred schema (must line up with
      # QueryService#infer_schema so drift comparisons across the two entry points
      # are apples-to-apples).
      def initialize(account = nil)
        @account = account
      end

      # Walk due endpoints and refresh each one's schema version. Returns a batch
      # summary: { synced:, errors: }. `synced` counts endpoints for which a
      # version was (re)recorded; `errors` carries per-endpoint failures.
      def sync(limit: 100)
        synced = 0
        errors = []

        due_endpoints(limit).each do |endpoint|
          outcome = sync_endpoint(endpoint)
          synced += 1 if outcome == :synced
        rescue StandardError => e
          Rails.logger.warn("[DataSources::SchemaSyncService] sync failed for endpoint #{endpoint.id}: #{e.class}: #{e.message}")
          errors << { endpoint_id: endpoint.id, error: e.message }
        end

        { synced: synced, errors: errors }
      end

      private

      attr_reader :account

      # Endpoints on active sources that either opted into schema tracking or have
      # no baseline schema yet. Eager-loads the parent source so the sample fetch
      # never N+1s. Account-scoped when an account was supplied.
      def due_endpoints(limit)
        scope = Ai::DataSourceEndpoint
                .joins(:data_source)
                .where(ai_data_sources: { is_active: true })
                .where(due_clause)
                .includes(:data_source)
        scope = scope.where(ai_data_sources: { account_id: account.id }) if account
        scope.limit(limit)
      end

      # track_schema = true OR response_schema is empty/NULL. Expressed in SQL so
      # the candidate set is filtered in the database rather than in Ruby.
      def due_clause
        <<~SQL.squish
          ai_data_source_endpoints.track_schema = TRUE
          OR ai_data_source_endpoints.response_schema IS NULL
          OR ai_data_source_endpoints.response_schema = '{}'::jsonb
        SQL
      end

      # Sample one endpoint, infer its schema, record a version, and seed
      # response_schema when blank. Returns :synced on a recorded version,
      # :skipped when the sample produced no usable records (busy/blocked/empty).
      def sync_endpoint(endpoint)
        source = endpoint.data_source
        return :skipped if source.nil?

        records = sample_records(source, endpoint)
        return :skipped if records.nil?

        inferred = infer_schema(records)
        Ai::DataSources::SchemaDriftService.new(account_for(source)).record_version!(endpoint, inferred)

        seed_response_schema(endpoint, inferred)
        :synced
      end

      # Run a governed sample fetch and return its canonical records, or nil when
      # the sample did not succeed (quota/blocked/transport) so the caller can skip
      # without raising.
      def sample_records(source, endpoint)
        envelope = Ai::DataSources::QueryService.new(
          data_source: source,
          endpoint: endpoint,
          params: {},
          agent: nil,
          user: nil
        ).call

        return nil unless envelope.is_a?(Hash) && envelope[:success]

        data = envelope[:data]
        data.is_a?(Array) ? data : nil
      rescue StandardError => e
        Rails.logger.warn("[DataSources::SchemaSyncService] sample fetch failed for endpoint #{endpoint.id}: #{e.message}")
        nil
      end

      # Persist the inferred schema onto the endpoint ONLY when it has no baseline
      # yet. update_column bypasses callbacks/validation (a schema seed must not
      # trip the audit chain or re-run endpoint validations on the cron path).
      def seed_response_schema(endpoint, inferred)
        return unless endpoint.response_schema.blank?

        endpoint.update_column(:response_schema, inferred)
      rescue StandardError => e
        Rails.logger.warn("[DataSources::SchemaSyncService] response_schema seed failed for endpoint #{endpoint.id}: #{e.message}")
      end

      # Infer a minimal top-level-ARRAY JSON Schema from the first record's keys —
      # the SAME shape QueryService#infer_schema emits, so SchemaDriftService
      # flattens and compares both consistently.
      def infer_schema(records)
        sample = Array(records).find { |r| r.is_a?(Hash) }
        return empty_array_schema unless sample

        properties = sample.each_with_object({}) do |(key, value), acc|
          acc[key.to_s] = { "type" => json_type_of(value) }
        end
        { "type" => "array", "items" => { "type" => "object", "properties" => properties } }
      end

      def empty_array_schema
        { "type" => "array", "items" => { "type" => "object", "properties" => {} } }
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

      # SchemaDriftService takes the account for any account-scoped behavior; prefer
      # the explicit account, fall back to the source's account.
      def account_for(source)
        account || source.account
      end
    end
  end
end
