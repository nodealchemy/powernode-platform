# frozen_string_literal: true

module Ai
  module Tools
    # Exposes the Ai::DataSources capability over MCP with 1:1 parity to the REST
    # surface (Api::V1::Ai::DataSourcesController). Read actions require
    # ai.data_sources.read, data_source_query requires ai.data_sources.query, and
    # the mutation actions (create/update/delete) require the matching
    # ai.data_sources.{create,update,delete} grant (ai.data_sources.manage also
    # satisfies any mutation).
    #
    # PROPOSAL FALLBACK: when the acting agent's account lacks the mutation
    # permission, the mutation actions DO NOT mutate. Instead they file an
    # Ai::AgentProposal (via Ai::ProposalService) describing the intended change
    # and return a proposal-style result so a human can review/approve. This
    # mirrors the established pattern used by AgentAutonomyTool/AgentManagementTool.
    #
    # The class-level REQUIRED_PERMISSION gates visibility (least-privilege read);
    # finer per-action checks happen inside #call so a single tool can carry read,
    # query, and mutation actions with distinct authorization.
    class DataSourceTool < BaseTool
      REQUIRED_PERMISSION = "ai.data_sources.read"

      READ_PERMISSION   = "ai.data_sources.read"
      QUERY_PERMISSION  = "ai.data_sources.query"
      MANAGE_PERMISSION = "ai.data_sources.manage"
      STREAM_PERMISSION = "ai.data_sources.stream"

      # Subscription (pull-based monitoring) actions, gated by STREAM_PERMISSION.
      STREAM_ACTIONS = %w[data_source_subscribe data_source_unsubscribe].freeze

      # Per-action mutation permission. ai.data_sources.manage satisfies any of
      # these (checked separately in #mutation_permitted?).
      MUTATION_PERMISSIONS = {
        "data_source_create" => "ai.data_sources.create",
        "data_source_update" => "ai.data_sources.update",
        "data_source_delete" => "ai.data_sources.delete"
      }.freeze

      READ_ACTIONS = %w[
        data_source_list data_source_get data_source_describe
        data_source_health data_source_validate_config
        data_source_discover data_source_provenance data_source_impact
        data_source_schema_history data_source_quality data_source_contract
      ].freeze

      # Phase 2b introspection creates endpoints from an OpenAPI spec, so it is a
      # mutation gated by ai.data_sources.manage (dry_run previews still require it —
      # the action is fundamentally a write surface).
      INTROSPECT_ACTION = "data_source_introspect"

      def self.definition
        {
          name: "data_source_management",
          description: "Manage AI data sources: list, inspect, describe endpoints/schemas, query (governed external fetch), " \
                       "health (quota + cache + circuit breaker + trust signals), validate config, semantic discover, " \
                       "provenance (audit a recorded fetch), impact (usage/effectiveness summary), plus create/update/delete",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            data_source_id: { type: "string", required: false, description: "Data source UUID or slug" },
            endpoint_id: { type: "string", required: false, description: "Endpoint UUID or slug (for query/describe/provenance)" },
            params: { type: "object", required: false, description: "Query parameters passed to QueryService" },
            query: { type: "string", required: false, description: "Natural-language need (data_source_discover)" },
            limit: { type: "integer", required: false, description: "Max results (data_source_discover)" },
            rerank: { type: "boolean", required: false, description: "Enable LLM reranking (data_source_discover)" },
            query_id: { type: "string", required: false, description: "ai_data_source_queries row UUID (data_source_provenance)" },
            correlation_id: { type: "string", required: false, description: "Fetch correlation id (data_source_provenance)" },
            spec: { type: "object", required: false, description: "Parsed OpenAPI 3 document (data_source_introspect)" },
            dry_run: { type: "boolean", required: false, description: "Preview without persisting (data_source_introspect)" },
            poll_frequency: { type: "string", required: false, description: "Poll cadence (data_source_subscribe)" },
            subscription_id: { type: "string", required: false, description: "Subscription UUID (data_source_unsubscribe)" },
            name: { type: "string", required: false, description: "Data source name (create/update)" },
            slug: { type: "string", required: false, description: "Data source slug (create)" },
            source_type: { type: "string", required: false, description: "Source type (create/update)" },
            api_base_url: { type: "string", required: false, description: "Base URL (create/update)" },
            description: { type: "string", required: false, description: "Description (create/update)" },
            is_active: { type: "boolean", required: false, description: "Active flag (create/update)" },
            requires_auth: { type: "boolean", required: false, description: "Requires auth flag (create/update)" },
            priority_order: { type: "integer", required: false, description: "Priority order (create/update)" },
            configuration: { type: "object", required: false, description: "Configuration hash (create/update)" },
            rate_limits: { type: "object", required: false, description: "Rate limits hash (create/update)" }
          }
        }
      end

      def self.action_definitions
        {
          "data_source_list" => {
            description: "List AI data sources for the current account with health + credential counts",
            parameters: {
              source_type: { type: "string", required: false, description: "Filter by source type" },
              is_active: { type: "boolean", required: false, description: "Filter by active state" }
            }
          },
          "data_source_get" => {
            description: "Get a single data source with configuration, rate limits, credentials, and quota summary",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" }
            }
          },
          "data_source_describe" => {
            description: "Describe a data source's endpoints, including HTTP method, path, response format, and response schemas",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" },
              endpoint_id: { type: "string", required: false, description: "Limit to a single endpoint UUID or slug" }
            }
          },
          "data_source_query" => {
            description: "Run a governed external fetch through Ai::DataSources::QueryService (kill flag, quota, cache, " \
                         "circuit breaker, SSRF guard, decode, normalize, schema-validate, redact, audit). Returns a FetchEnvelope.",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" },
              endpoint_id: { type: "string", required: true, description: "Endpoint UUID or slug to fetch" },
              params: { type: "object", required: false, description: "Query/path/body parameters for the endpoint" }
            }
          },
          "data_source_health" => {
            description: "Report a data source's quota summary, response-cache metrics, and circuit-breaker state",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" }
            }
          },
          "data_source_validate_config" => {
            description: "Validate a data source's configuration: SSRF-safe base URL, known auth scheme, supported protocol/formats",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" }
            }
          },
          "data_source_discover" => {
            description: "Semantically discover data sources for a natural-language need via Ai::DataSources::SemanticDiscoveryService " \
                         "(embedding + pgvector nearest-neighbor, blended with effectiveness/health/recency trust signals). " \
                         "Falls back to keyword name matching when no embedding backend is available.",
            parameters: {
              query: { type: "string", required: true, description: "Natural-language description of the data need" },
              limit: { type: "integer", required: false, description: "Max ranked results (default 10)" },
              rerank: { type: "boolean", required: false, description: "Refine top candidates with the RAG reranker (default false)" }
            }
          },
          "data_source_provenance" => {
            description: "Return the provenance of a recorded fetch from the ai_data_source_queries audit log: source, endpoint, " \
                         "fetched_at, response_sha256, redacted_url, schema_valid, cached/served_stage, cost, and audit-chain anchor. " \
                         "Looks up by query_id, then correlation_id, else the latest query for a data_source (optionally scoped to an endpoint).",
            parameters: {
              query_id: { type: "string", required: false, description: "ai_data_source_queries row UUID" },
              correlation_id: { type: "string", required: false, description: "Fetch correlation id" },
              data_source_id: { type: "string", required: false, description: "Data source UUID or slug (latest-query fallback)" },
              endpoint_id: { type: "string", required: false, description: "Endpoint UUID or slug to scope the latest-query fallback" }
            }
          },
          "data_source_impact" => {
            description: "Usage + trust summary for a data source: distinct requesting agents, total/successful/failed/cached query " \
                         "counts, last_used_at, effectiveness_score, usage success rate, and health status.",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" }
            }
          },
          "data_source_schema_history" => {
            description: "Return an endpoint's recorded schema-version history (version list with classification " \
                         "initial|none|additive|breaking) plus the latest version's structural diff. Populated when the " \
                         "endpoint opts into track_schema and a fetch runs through QueryService.",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" },
              endpoint_id: { type: "string", required: true, description: "Endpoint UUID or slug" }
            }
          },
          "data_source_quality" => {
            description: "Return an endpoint's latest data-quality outcome (quality_score / quality_passed / quarantined from " \
                         "the most recent query) and its configured Ai::DataSourceExpectation rules.",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" },
              endpoint_id: { type: "string", required: true, description: "Endpoint UUID or slug" }
            }
          },
          "data_source_introspect" => {
            description: "Import an OpenAPI 3 spec into endpoints via Ai::DataSources::OpenApiImportService (paths -> endpoints, " \
                         "200 response schema resolved against components/schemas). Requires ai.data_sources.manage. Supports " \
                         "dry_run to preview without persisting.",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" },
              spec: { type: "object", required: true, description: "Parsed OpenAPI 3 document (Hash)" },
              dry_run: { type: "boolean", required: false, description: "Preview without creating endpoints (default false)" }
            }
          },
          "data_source_contract" => {
            description: "Run Ai::DataSources::ContractService for a source+endpoint: performs a governed fetch then aggregates " \
                         "schema_valid + quality_passed + within_sla into a single contract verdict (met + violations).",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" },
              endpoint_id: { type: "string", required: true, description: "Endpoint UUID or slug" },
              params: { type: "object", required: false, description: "Query/path/body parameters for the fetch" }
            }
          },
          "data_source_subscribe" => {
            description: "Create or update a pull-based subscription to an endpoint (Ai::DataSourceSubscription). The server-side " \
                         "monitor polls due subscriptions on the given cadence, change-detects (etag/checksum), warms the cache " \
                         "and emits a data_source_changed signal on change. Requires ai.data_sources.stream.",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" },
              endpoint_id: { type: "string", required: true, description: "Endpoint UUID or slug to subscribe to" },
              params: { type: "object", required: false, description: "Query/path/body parameters passed to each poll" },
              poll_frequency: { type: "string", required: false,
                                description: "Cadence: manual|5min|hourly|daily|weekly|monthly|realtime (default hourly)" }
            }
          },
          "data_source_unsubscribe" => {
            description: "Remove a pull-based subscription. Provide subscription_id, or data_source_id + endpoint_id to remove " \
                         "the matching subscription(s). Requires ai.data_sources.stream.",
            parameters: {
              subscription_id: { type: "string", required: false, description: "Subscription UUID" },
              data_source_id: { type: "string", required: false, description: "Data source UUID or slug (with endpoint_id)" },
              endpoint_id: { type: "string", required: false, description: "Endpoint UUID or slug (with data_source_id)" }
            }
          },
          "data_source_create" => {
            description: "Create a new data source (requires ai.data_sources.create or .manage; agents lacking it file a proposal instead)",
            parameters: {
              name: { type: "string", required: true, description: "Data source name" },
              source_type: { type: "string", required: true, description: "Source type (e.g. open_meteo, fred, custom)" },
              api_base_url: { type: "string", required: false, description: "Base URL" },
              slug: { type: "string", required: false, description: "Optional slug (auto-generated when omitted)" },
              description: { type: "string", required: false, description: "Description" },
              is_active: { type: "boolean", required: false, description: "Active flag (default true)" },
              requires_auth: { type: "boolean", required: false, description: "Requires auth flag" },
              priority_order: { type: "integer", required: false, description: "Priority order" },
              configuration: { type: "object", required: false, description: "Configuration hash" },
              rate_limits: { type: "object", required: false, description: "Rate limits hash" }
            }
          },
          "data_source_update" => {
            description: "Update an existing data source (requires ai.data_sources.update or .manage; agents lacking it file a proposal instead)",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" },
              name: { type: "string", required: false, description: "New name" },
              source_type: { type: "string", required: false, description: "New source type" },
              api_base_url: { type: "string", required: false, description: "New base URL" },
              description: { type: "string", required: false, description: "New description" },
              is_active: { type: "boolean", required: false, description: "Active flag" },
              requires_auth: { type: "boolean", required: false, description: "Requires auth flag" },
              priority_order: { type: "integer", required: false, description: "Priority order" },
              configuration: { type: "object", required: false, description: "Configuration hash" },
              rate_limits: { type: "object", required: false, description: "Rate limits hash" }
            }
          },
          "data_source_delete" => {
            description: "Delete a data source (requires ai.data_sources.delete or .manage; agents lacking it file a proposal instead)",
            parameters: {
              data_source_id: { type: "string", required: true, description: "Data source UUID or slug" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        # Per-action authorization. Read + query require their own grants; the
        # mutation branch routes through the proposal fallback when unauthorized.
        if READ_ACTIONS.include?(action)
          return permission_denied(READ_PERMISSION) unless permission?(READ_PERMISSION)
        elsif action == "data_source_query"
          return permission_denied(QUERY_PERMISSION) unless permission?(QUERY_PERMISSION)
        elsif action == INTROSPECT_ACTION
          return permission_denied(MANAGE_PERMISSION) unless permission?(MANAGE_PERMISSION)
        elsif STREAM_ACTIONS.include?(action)
          return permission_denied(STREAM_PERMISSION) unless permission?(STREAM_PERMISSION)
        elsif MUTATION_PERMISSIONS.key?(action)
          return propose_mutation(action, params) unless mutation_permitted?(action)
        end

        case action
        when "data_source_list" then list_sources(params)
        when "data_source_get" then get_source(params)
        when "data_source_describe" then describe_source(params)
        when "data_source_query" then query_source(params)
        when "data_source_health" then source_health(params)
        when "data_source_validate_config" then validate_config(params)
        when "data_source_discover" then discover_sources(params)
        when "data_source_provenance" then source_provenance(params)
        when "data_source_impact" then source_impact(params)
        when "data_source_schema_history" then schema_history(params)
        when "data_source_quality" then quality_report(params)
        when "data_source_introspect" then introspect_source(params)
        when "data_source_contract" then contract_verdict(params)
        when "data_source_subscribe" then subscribe_source(params)
        when "data_source_unsubscribe" then unsubscribe_source(params)
        when "data_source_create" then create_source(params)
        when "data_source_update" then update_source(params)
        when "data_source_delete" then delete_source(params)
        else error_result("Unknown action: #{action}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      rescue ArgumentError => e
        error_result(e.message)
      end

      private

      # ----------------------------------------------------------------------
      # read actions
      # ----------------------------------------------------------------------

      def list_sources(params)
        scope = account_sources.includes(:credentials).ordered_by_priority
        scope = scope.by_type(params[:source_type]) if params[:source_type].present?
        scope = scope.where(is_active: to_bool(params[:is_active])) unless params[:is_active].nil?

        success_result(
          items: scope.map { |ds| summarize_source(ds) },
          count: scope.size
        )
      end

      def get_source(params)
        ds = resolve_source(params[:data_source_id])
        success_result(data_source: detail_source(ds))
      end

      def describe_source(params)
        ds = resolve_source(params[:data_source_id])
        endpoints = ds.endpoints.order(:name)
        if params[:endpoint_id].present?
          endpoints = [resolve_endpoint(ds, params[:endpoint_id])]
        end

        success_result(
          data_source: {
            id: ds.id, slug: ds.slug, name: ds.name,
            protocol: ds.protocol, auth_scheme: ds.auth_scheme,
            effectiveness_score: ds.effectiveness_score
          }.merge(trust_signals(ds)),
          endpoints: endpoints.map { |ep| describe_endpoint(ep) },
          count: endpoints.size
        )
      end

      def query_source(params)
        ds = resolve_source(params[:data_source_id])
        endpoint = resolve_endpoint(ds, params[:endpoint_id])

        envelope = Ai::DataSources::QueryService.new(
          data_source: ds,
          endpoint: endpoint,
          params: (params[:params] || {}).to_h,
          agent: agent,
          user: user
        ).call

        # The FetchEnvelope already carries success/data/provenance/status/error;
        # return it verbatim so callers get the full governed result.
        envelope
      end

      def source_health(params)
        ds = resolve_source(params[:data_source_id])

        success_result(
          data_source: { id: ds.id, slug: ds.slug, name: ds.name, health_status: ds.health_status },
          effectiveness_score: ds.effectiveness_score,
          trust_signals: trust_signals(ds),
          quota_summary: ds.quota_summary,
          cache_metrics: cache_metrics,
          circuit_breaker: breaker_state(ds)
        )
      end

      def validate_config(params)
        ds = resolve_source(params[:data_source_id])
        errors = []
        warnings = []

        validate_base_url(ds, errors)
        validate_auth_scheme(ds, errors)
        validate_protocol(ds, warnings)
        warnings << "No endpoints configured" if ds.endpoints.none?
        warnings << "Active but has no usable credential" if ds.is_active? && ds.requires_auth && ds.active_credential.nil?

        success_result(
          data_source: { id: ds.id, slug: ds.slug, name: ds.name },
          valid: errors.empty?,
          errors: errors,
          warnings: warnings
        )
      end

      # Semantic data-source discovery. Delegates to the Phase 1
      # SemanticDiscoveryService (embedding + pgvector nearest-neighbor, blended
      # with effectiveness/health/recency), serializing each ranked candidate to a
      # compact summary + its trust signals. Hermetic-safe: the service degrades to
      # keyword name matching when no embedding backend is available.
      def discover_sources(params)
        query = params[:query].to_s
        raise ArgumentError, "query is required" if query.blank?

        limit = params[:limit].present? ? params[:limit].to_i.clamp(1, 50) : 10
        ranked = Ai::DataSources::SemanticDiscoveryService.new(account).discover(
          query: query,
          agent: agent,
          limit: limit,
          rerank: to_bool(params[:rerank])
        )

        success_result(
          query: query,
          count: ranked.size,
          results: ranked.map { |r| discovery_result(r) }
        )
      end

      # Provenance of a recorded fetch. Resolution precedence: explicit query_id,
      # then correlation_id, then the latest query for a data_source (optionally
      # scoped to an endpoint). All lookups are account-scoped so an agent can only
      # audit its own account's fetches.
      def source_provenance(params)
        query = resolve_query(params)
        raise ActiveRecord::RecordNotFound, "No matching data source query found" if query.nil?

        success_result(provenance: query_provenance(query))
      end

      # Usage + trust impact summary for a single data source: distinct requesting
      # agents, query-count breakdown, recency, and rolled-up trust signals.
      def source_impact(params)
        ds = resolve_source(params[:data_source_id])
        scope = Ai::DataSourceQuery.for_data_source(ds)

        success_result(
          data_source: { id: ds.id, slug: ds.slug, name: ds.name },
          distinct_requesting_agents: scope.where.not(requesting_agent_id: nil).distinct.count(:requesting_agent_id),
          query_counts: {
            total: scope.count,
            successful: scope.successful.count,
            failed: scope.failed.count,
            cached: scope.cached.count
          },
          last_used_at: ds.last_used_at&.iso8601,
          effectiveness_score: ds.effectiveness_score,
          health_status: ds.health_status,
          trust_signals: trust_signals(ds)
        )
      end

      # ----------------------------------------------------------------------
      # Phase 2b — schema history, quality, introspect, contract
      # ----------------------------------------------------------------------

      # Endpoint schema-version history (ordered) + the latest version's diff.
      def schema_history(params)
        ds = resolve_source(params[:data_source_id])
        endpoint = resolve_endpoint(ds, params[:endpoint_id])
        versions = endpoint.schema_versions.order(version: :asc)
        latest = versions.last

        success_result(
          data_source: { id: ds.id, slug: ds.slug, name: ds.name },
          endpoint: { id: endpoint.id, slug: endpoint.slug, name: endpoint.name, track_schema: endpoint.track_schema },
          versions: versions.map { |v| schema_version_summary(v) },
          count: versions.size,
          latest_diff: latest&.diff || {}
        )
      end

      # Latest quality outcome for an endpoint (from its most recent query log row)
      # plus the configured expectations.
      def quality_report(params)
        ds = resolve_source(params[:data_source_id])
        endpoint = resolve_endpoint(ds, params[:endpoint_id])
        latest = Ai::DataSourceQuery.where(ai_data_source_endpoint_id: endpoint.id).recent.first

        success_result(
          data_source: { id: ds.id, slug: ds.slug, name: ds.name },
          endpoint: { id: endpoint.id, slug: endpoint.slug, name: endpoint.name,
                      quality_checks_enabled: endpoint.quality_checks_enabled,
                      quarantine_on_failure: endpoint.quarantine_on_failure },
          latest_quality: latest_quality_summary(latest),
          expectations: endpoint.expectations.order(:name).map { |e| expectation_summary(e) },
          expectation_count: endpoint.expectations.size
        )
      end

      # Import an OpenAPI 3 spec into endpoints (manage-gated). dry_run previews
      # without persisting.
      def introspect_source(params)
        ds = resolve_source(params[:data_source_id])
        spec = (params[:spec] || {}).to_h
        raise ArgumentError, "spec is required" if spec.blank?

        dry_run = to_bool(params[:dry_run]) || false
        result = Ai::DataSources::OpenApiImportService.new(ds).import(
          spec, dry_run: dry_run
        )

        success_result(
          data_source: { id: ds.id, slug: ds.slug, name: ds.name },
          dry_run: dry_run,
          created: result[:created],
          created_count: result[:created].size,
          preview: result[:preview],
          preview_count: result[:preview].size,
          errors: result[:errors]
        )
      end

      # Governed fetch + aggregate contract verdict (schema + quality + SLA).
      def contract_verdict(params)
        ds = resolve_source(params[:data_source_id])
        endpoint = resolve_endpoint(ds, params[:endpoint_id])

        envelope = Ai::DataSources::QueryService.new(
          data_source: ds,
          endpoint: endpoint,
          params: (params[:params] || {}).to_h,
          agent: agent,
          user: user
        ).call

        verdict = Ai::DataSources::ContractService.new.validate(
          data_source: ds, endpoint: endpoint, envelope: envelope
        )

        success_result(
          data_source: { id: ds.id, slug: ds.slug, name: ds.name },
          endpoint: { id: endpoint.id, slug: endpoint.slug, name: endpoint.name,
                      sla_max_age_seconds: endpoint.sla_max_age_seconds, owner: endpoint.owner },
          contract: verdict,
          fetch_status: envelope[:status],
          fetch_success: envelope[:success]
        )
      end

      def schema_version_summary(version)
        {
          version: version.version,
          classification: version.classification,
          checksum: version.checksum,
          created_at: version.created_at&.iso8601
        }
      end

      def latest_quality_summary(query)
        return nil unless query

        {
          query_id: query.id,
          quality_score: query.quality_score,
          quality_passed: query.quality_passed,
          quarantined: query.quarantined,
          schema_drift: query.schema_drift,
          fetched_at: query.created_at&.iso8601
        }
      end

      def expectation_summary(expectation)
        {
          id: expectation.id,
          name: expectation.name,
          rule_type: expectation.rule_type,
          severity: expectation.severity,
          is_active: expectation.is_active,
          config: expectation.config
        }
      end

      # ----------------------------------------------------------------------
      # Phase 3 — pull-based subscriptions (stream-gated)
      # ----------------------------------------------------------------------

      # Create or update a subscription for a (source, endpoint) pair. Idempotent
      # on the pair: a second subscribe with the same endpoint updates the
      # existing subscription's cadence/params rather than creating a duplicate.
      def subscribe_source(params)
        ds = resolve_source(params[:data_source_id])
        endpoint = resolve_endpoint(ds, params[:endpoint_id])
        frequency = params[:poll_frequency].presence || "hourly"

        unless Ai::DataSourceSubscription::POLL_FREQUENCIES.include?(frequency)
          return error_result(
            "Invalid poll_frequency '#{frequency}' (allowed: #{Ai::DataSourceSubscription::POLL_FREQUENCIES.join(', ')})"
          )
        end

        subscription = ds.subscriptions.find_or_initialize_by(ai_data_source_endpoint_id: endpoint.id)
        new_record = subscription.new_record?
        subscription.poll_frequency = frequency
        subscription.params = (params[:params] || {}).to_h
        subscription.agent = agent if agent
        subscription.status = "active"
        # Re-arm the cadence so an updated frequency takes effect immediately.
        subscription.next_poll_at = nil if new_record || subscription.poll_frequency_changed?

        if subscription.save
          subscription.schedule_next_poll! if subscription.next_poll_at.nil?
          success_result(
            subscription: subscription_summary(subscription),
            message: new_record ? "Subscription created" : "Subscription updated"
          )
        else
          error_result(subscription.errors.full_messages.join(", "))
        end
      end

      # Remove a subscription by id, or every subscription matching a
      # (data_source, endpoint) pair. Account-scoped via resolve_source.
      def unsubscribe_source(params)
        if params[:subscription_id].present?
          subscription = account_subscriptions.find_by(id: params[:subscription_id])
          raise ActiveRecord::RecordNotFound, "Subscription not found: #{params[:subscription_id]}" if subscription.nil?

          subscription.destroy
          return success_result(message: "Subscription deleted", subscription_id: params[:subscription_id])
        end

        raise ArgumentError, "Provide subscription_id, or data_source_id + endpoint_id" if params[:data_source_id].blank? || params[:endpoint_id].blank?

        ds = resolve_source(params[:data_source_id])
        endpoint = resolve_endpoint(ds, params[:endpoint_id])
        removed = ds.subscriptions.where(ai_data_source_endpoint_id: endpoint.id).destroy_all

        success_result(
          message: "Removed #{removed.size} subscription(s)",
          removed_count: removed.size,
          data_source_id: ds.id,
          endpoint_id: endpoint.id
        )
      end

      def subscription_summary(subscription)
        {
          id: subscription.id,
          data_source_id: subscription.ai_data_source_id,
          endpoint_id: subscription.ai_data_source_endpoint_id,
          poll_frequency: subscription.poll_frequency,
          status: subscription.status,
          params: subscription.params,
          next_poll_at: subscription.next_poll_at&.iso8601,
          last_polled_at: subscription.last_polled_at&.iso8601,
          last_checksum: subscription.last_checksum,
          consecutive_failures: subscription.consecutive_failures,
          agent_id: subscription.ai_agent_id
        }
      end

      # Account-scoped subscription lookup, joining through the parent source.
      def account_subscriptions
        raise ArgumentError, "No account context" unless account

        Ai::DataSourceSubscription.joins(:data_source)
                                  .where(ai_data_sources: { account_id: account.id })
      end

      # ----------------------------------------------------------------------
      # mutation actions (only reached when authorized; otherwise propose)
      # ----------------------------------------------------------------------

      def create_source(params)
        ds = Ai::DataSource.new(create_attributes(params))
        ds.account = account
        if ds.save
          success_result(data_source: detail_source(ds), message: "Data source created")
        else
          error_result(ds.errors.full_messages.join(", "))
        end
      end

      def update_source(params)
        ds = resolve_source(params[:data_source_id])
        if ds.update(update_attributes(params))
          success_result(data_source: detail_source(ds), message: "Data source updated")
        else
          error_result(ds.errors.full_messages.join(", "))
        end
      end

      def delete_source(params)
        ds = resolve_source(params[:data_source_id])
        name = ds.name
        if ds.destroy
          success_result(message: "Data source '#{name}' deleted")
        else
          error_result(ds.errors.full_messages.presence&.join(", ") || "Failed to delete data source")
        end
      end

      # ----------------------------------------------------------------------
      # proposal fallback
      # ----------------------------------------------------------------------

      # When the agent's account lacks the mutation grant, file a proposal instead
      # of mutating. Returns a proposal-style result (requires_approval: true).
      def propose_mutation(action, params)
        unless agent && account
          return permission_denied(MUTATION_PERMISSIONS[action])
        end

        verb = action.delete_prefix("data_source_")
        proposed_changes = mutation_changeset(action, params)

        service = Ai::ProposalService.new(account: account)
        proposal = service.create(
          agent: agent,
          params: {
            proposal_type: "configuration",
            title: "Data source #{verb}: #{proposal_subject(action, params)}",
            description: "Agent requested to #{verb} a data source but lacks " \
                         "#{MUTATION_PERMISSIONS[action]}. Review and apply if appropriate.",
            priority: "medium",
            proposed_changes: proposed_changes
          }
        )

        if proposal.persisted?
          {
            success: true,
            requires_approval: true,
            proposal_id: proposal.id,
            status: proposal.status,
            message: "Permission #{MUTATION_PERMISSIONS[action]} required — filed proposal #{proposal.id} for review",
            proposed_changes: proposed_changes
          }
        else
          error_result("Could not file proposal: #{proposal.errors.full_messages.join(', ')}")
        end
      rescue StandardError => e
        Rails.logger.error("[DataSourceTool] proposal fallback failed: #{e.class}: #{e.message}")
        error_result("Permission #{MUTATION_PERMISSIONS[action]} required and proposal could not be filed")
      end

      def mutation_changeset(action, params)
        case action
        when "data_source_create" then { action: "create", attributes: create_attributes(params) }
        when "data_source_update"
          { action: "update", data_source_id: params[:data_source_id], attributes: update_attributes(params) }
        when "data_source_delete"
          { action: "delete", data_source_id: params[:data_source_id] }
        else {}
        end
      end

      def proposal_subject(action, params)
        if action == "data_source_create"
          params[:name].presence || params[:slug].presence || "new source"
        else
          params[:data_source_id].to_s
        end
      end

      # ----------------------------------------------------------------------
      # authorization helpers (per-action, account-scoped)
      # ----------------------------------------------------------------------

      # ai.data_sources.manage satisfies any mutation; otherwise the specific
      # create/update/delete grant is required.
      def mutation_permitted?(action)
        permission?(MANAGE_PERMISSION) || permission?(MUTATION_PERMISSIONS[action])
      end

      # True when any user in the acting account holds the permission. Mirrors
      # BaseTool.permitted? account-wide model. When there is no agent context
      # (direct API/worker invocation) the API layer already authorized the call,
      # so allow.
      def permission?(permission_name)
        return true unless agent
        return true unless account

        Permission.joins(roles: :user_roles)
                  .where(user_roles: { user_id: account.users.select(:id) })
                  .where(name: permission_name)
                  .exists?
      rescue StandardError
        # Fail open like BaseTool.permitted? — execution is already gated upstream.
        true
      end

      def permission_denied(permission_name)
        error_result("Permission denied: #{permission_name} is required for this action")
      end

      # ----------------------------------------------------------------------
      # config validation helpers
      # ----------------------------------------------------------------------

      def validate_base_url(ds, errors)
        url = ds.api_base_url.to_s
        if url.blank?
          errors << "api_base_url is blank"
          return
        end
        Ai::DataSources::HttpConnectionFactory.validate_url!(url)
      rescue Ai::DataSources::HttpConnectionFactory::SsrfError => e
        errors << "api_base_url blocked by egress policy: #{e.message}"
      rescue StandardError => e
        errors << "api_base_url invalid: #{e.message}"
      end

      def validate_auth_scheme(ds, errors)
        scheme = ds.auth_scheme.to_s
        return if Ai::DataSources::Auth::SignerRegistry.schemes.include?(scheme)

        errors << "Unknown auth_scheme '#{scheme}' (known: #{Ai::DataSources::Auth::SignerRegistry.schemes.join(', ')})"
      end

      def validate_protocol(ds, warnings)
        protocol = ds.protocol.to_s
        return if %w[rest custom].include?(protocol)

        warnings << "Protocol '#{protocol}' falls back to the generic REST adapter"
      end

      # ----------------------------------------------------------------------
      # health helpers
      # ----------------------------------------------------------------------

      def cache_metrics
        Ai::DataSources::ResponseCacheService.metrics
      rescue StandardError => e
        Rails.logger.warn("[DataSourceTool] cache metrics unavailable: #{e.message}")
        { hits: 0, misses: 0, total: 0, hit_rate: 0, error: "unavailable" }
      end

      def breaker_state(ds)
        service_name = "data_source:#{ds.id}"
        breaker = Ai::CircuitBreakerRegistry.get_breaker(service_name)
        if breaker
          stats = breaker.circuit_stats
          {
            service_name: service_name,
            state: stats[:state],
            failure_count: stats[:failure_count],
            success_count: stats[:success_count],
            consecutive_failures: stats[:consecutive_failures],
            last_failure_at: stats[:last_failure_time],
            available: Ai::CircuitBreakerRegistry.service_available?(service_name)
          }
        else
          { service_name: service_name, state: "closed", available: true, note: "no breaker initialized yet" }
        end
      rescue StandardError => e
        Rails.logger.warn("[DataSourceTool] breaker state unavailable: #{e.message}")
        { service_name: "data_source:#{ds.id}", state: "unknown", error: "unavailable" }
      end

      # ----------------------------------------------------------------------
      # attribute builders + serialization
      # ----------------------------------------------------------------------

      def create_attributes(params)
        {
          name: params[:name],
          slug: params[:slug],
          source_type: params[:source_type],
          api_base_url: params[:api_base_url],
          description: params[:description],
          is_active: params[:is_active].nil? ? true : to_bool(params[:is_active]),
          requires_auth: to_bool(params[:requires_auth]),
          priority_order: params[:priority_order] || 100,
          configuration: (params[:configuration] || {}).to_h,
          rate_limits: (params[:rate_limits] || {}).to_h
        }.compact
      end

      def update_attributes(params)
        attrs = {}
        attrs[:name] = params[:name] if params.key?(:name)
        attrs[:source_type] = params[:source_type] if params.key?(:source_type)
        attrs[:api_base_url] = params[:api_base_url] if params.key?(:api_base_url)
        attrs[:description] = params[:description] if params.key?(:description)
        attrs[:is_active] = to_bool(params[:is_active]) unless params[:is_active].nil?
        attrs[:requires_auth] = to_bool(params[:requires_auth]) unless params[:requires_auth].nil?
        attrs[:priority_order] = params[:priority_order] if params.key?(:priority_order)
        attrs[:configuration] = params[:configuration].to_h if params[:configuration].present?
        attrs[:rate_limits] = params[:rate_limits].to_h if params[:rate_limits].present?
        attrs
      end

      def summarize_source(ds)
        {
          id: ds.id,
          name: ds.name,
          slug: ds.slug,
          source_type: ds.source_type,
          protocol: ds.protocol,
          auth_scheme: ds.auth_scheme,
          is_active: ds.is_active,
          requires_auth: ds.requires_auth,
          priority_order: ds.priority_order,
          health_status: ds.health_status,
          credential_count: ds.credentials.size
        }
      end

      def detail_source(ds)
        summarize_source(ds).merge(
          api_base_url: ds.api_base_url,
          description: ds.description,
          configuration: ds.configuration,
          rate_limits: ds.rate_limits,
          default_parameters: ds.default_parameters,
          capabilities: ds.capabilities,
          endpoint_count: ds.endpoints.size,
          quota: ds.quota_summary,
          created_at: ds.created_at&.iso8601,
          updated_at: ds.updated_at&.iso8601
        )
      end

      def describe_endpoint(ep)
        {
          id: ep.id,
          name: ep.name,
          slug: ep.slug,
          http_method: ep.http_method,
          path_template: ep.path_template,
          response_format: ep.response_format,
          expected_content_type: ep.expected_content_type,
          cache_ttl_seconds: ep.cache_ttl_seconds,
          monitorable: ep.monitorable,
          response_schema: ep.response_schema,
          response_mapping: ep.response_mapping
        }
      end

      # The rolled-up trust signals that feed (and are derived from) a source's
      # effectiveness_score: knowledge-graph node confidence (semantic standing),
      # observed query success rate, usage volume, recency, and health. Surfaced on
      # describe/health/impact so callers can reason about a source's reliability.
      def trust_signals(ds)
        {
          effectiveness_score: ds.effectiveness_score,
          usage_count: ds.usage_count,
          positive_usage_count: ds.positive_usage_count,
          negative_usage_count: ds.negative_usage_count,
          usage_success_rate: ds.usage_success_rate,
          kg_confidence: ds.knowledge_graph_node&.confidence,
          last_used_at: ds.last_used_at&.iso8601,
          health_status: ds.health_status,
          healthy: ds.healthy?
        }
      end

      # Serialize one SemanticDiscoveryService candidate
      # ({ data_source:, score:, signals: }) into a compact summary + its ranking
      # signals.
      def discovery_result(entry)
        ds = entry[:data_source]
        summarize_source(ds).merge(
          score: entry[:score],
          signals: entry[:signals],
          effectiveness_score: ds.effectiveness_score
        )
      end

      # Serialize an ai_data_source_queries row into a provenance record. Mirrors
      # the FetchEnvelope provenance contract plus the audit-chain anchor mirrored
      # onto the row's metadata by QueryService. Already-redacted at write time.
      def query_provenance(query)
        meta = query.metadata.is_a?(Hash) ? query.metadata : {}
        {
          query_id: query.id,
          correlation_id: query.correlation_id,
          source: { id: query.ai_data_source_id, slug: query.data_source&.slug, name: query.data_source&.name },
          endpoint: { id: query.ai_data_source_endpoint_id, slug: query.endpoint&.slug, name: query.endpoint&.name },
          fetched_at: query.created_at&.iso8601,
          status: query.status,
          http_status: query.http_status,
          duration_ms: query.duration_ms,
          bytes_in: query.bytes_in,
          rows_returned: query.rows_returned,
          response_sha256: query.response_sha256,
          redacted_url: query.redacted_url,
          schema_valid: query.schema_valid,
          cached: query.cached,
          served_stage: query.served_stage,
          redaction_applied: query.redaction_applied,
          estimated_cost_usd: query.estimated_cost_usd,
          actual_cost_usd: query.actual_cost_usd,
          anomalies: meta["anomalies"] || [],
          audit_chain: meta["audit_chain"]
        }
      end

      # ----------------------------------------------------------------------
      # lookups
      # ----------------------------------------------------------------------

      def account_sources
        raise ArgumentError, "No account context" unless account

        account.ai_data_sources
      end

      def resolve_source(identifier)
        raise ArgumentError, "data_source_id is required" if identifier.blank?

        scope = account_sources
        scope.find_by(slug: identifier) ||
          scope.find_by(id: identifier) ||
          raise(ActiveRecord::RecordNotFound, "Data source not found: #{identifier}")
      end

      def resolve_endpoint(data_source, identifier)
        raise ArgumentError, "endpoint_id is required" if identifier.blank?

        scope = data_source.endpoints
        scope.find_by(slug: identifier) ||
          scope.find_by(id: identifier) ||
          raise(ActiveRecord::RecordNotFound, "Endpoint not found: #{identifier}")
      end

      # Resolve an ai_data_source_queries row for provenance, account-scoped.
      # Precedence: query_id -> correlation_id -> latest query for a data_source
      # (optionally scoped to an endpoint). Returns nil when nothing matches so the
      # caller can raise a single not-found. Requires at least one selector.
      def resolve_query(params)
        scope = account_query_scope

        if params[:query_id].present?
          return scope.find_by(id: params[:query_id])
        end

        if params[:correlation_id].present?
          return scope.where(correlation_id: params[:correlation_id]).recent.first
        end

        if params[:data_source_id].present?
          ds = resolve_source(params[:data_source_id])
          ds_scope = scope.for_data_source(ds)
          ds_scope = ds_scope.where(ai_data_source_endpoint_id: resolve_endpoint(ds, params[:endpoint_id]).id) if params[:endpoint_id].present?
          return ds_scope.recent.first
        end

        raise ArgumentError, "Provide query_id, correlation_id, or data_source_id"
      end

      # Account-scoped query log. When there is no account context (direct API/
      # worker invocation, already authorized upstream) fall back to the full set.
      def account_query_scope
        account ? Ai::DataSourceQuery.for_account(account) : Ai::DataSourceQuery.all
      end

      def to_bool(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
