# frozen_string_literal: true

module Ai
  # Nested data-source endpoint CRUD + governed query, extracted from
  # Api::V1::Ai::DataSourcesController to keep that controller under the size
  # budget. Assumes the host controller sets @data_source (and @endpoint for
  # member actions) via before_actions and includes Ai::DataSourceSerialization
  # + AuditLogging.
  module DataSourceEndpoints
    extend ActiveSupport::Concern

    # GET /api/v1/ai/data_sources/:data_source_id/endpoints
    def endpoints_index
      endpoints = @data_source.endpoints.order(:name)
      render_success({
        items: endpoints.map { |ep| serialize_data_source_endpoint(ep) },
        count: endpoints.size
      })
    end

    # POST /api/v1/ai/data_sources/:data_source_id/endpoints
    def endpoints_create
      endpoint = @data_source.endpoints.new(endpoint_params)

      if endpoint.save
        render_success({ endpoint: serialize_data_source_endpoint(endpoint) }, status: :created)
        log_audit_event("ai.data_sources.endpoint.create", endpoint, data_source_id: @data_source.id)
      else
        render_validation_error(endpoint.errors)
      end
    end

    # PATCH/PUT /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
    def endpoints_update
      if @endpoint.update(endpoint_params)
        render_success({ endpoint: serialize_data_source_endpoint(@endpoint) })
        log_audit_event("ai.data_sources.endpoint.update", @endpoint, changes: @endpoint.previous_changes.keys)
      else
        render_validation_error(@endpoint.errors)
      end
    end

    # DELETE /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
    def endpoints_destroy
      endpoint_name = @endpoint.name

      if @endpoint.destroy
        render_success({ message: "Endpoint deleted successfully" })
        log_audit_event("ai.data_sources.endpoint.delete", @data_source, endpoint_name: endpoint_name)
      else
        render_error("Failed to delete endpoint", status: :unprocessable_content)
      end
    end

    # POST /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/query
    # Runs the governed external fetch (kill flag, quota, cache, breaker, SSRF
    # guard, decode/normalize/schema-validate, redact, audit) via QueryService.
    def endpoints_query
      envelope = ::Ai::DataSources::EndpointQueryRunner.new(
        data_source: @data_source,
        endpoint: @endpoint,
        params: query_request_params,
        user: current_user
      ).call

      if envelope[:success]
        render_success(envelope)
      else
        render_error(
          envelope[:error] || "Data source query failed",
          status: query_error_status(envelope[:status]),
          details: { provenance: envelope[:provenance], status: envelope[:status] }
        )
      end
    end

    # GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/schema_history
    # Read-only: the endpoint's recorded schema-version history, newest-first, with
    # a convenience pointer to the latest version. Versions are appended by
    # Ai::DataSources::SchemaDriftService#record_version! on tracked fetches.
    def schema_history
      versions = @endpoint.schema_versions.latest_first
      serialized = versions.map { |v| serialize_data_source_schema_version(v) }

      render_success({
        endpoint_id: @endpoint.id,
        count: serialized.size,
        versions: serialized,
        latest: serialized.first
      })
    end

    # GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/quality
    # Read-only: the latest quality outcome distilled from the endpoint's most
    # recent query-log row, plus its configured Ai::DataSourceExpectation rules.
    def quality
      latest = ::Ai::DataSourceQuery.where(ai_data_source_endpoint_id: @endpoint.id).recent.first

      render_success({
        endpoint_id: @endpoint.id,
        quality_checks_enabled: @endpoint.quality_checks_enabled,
        quarantine_on_failure: @endpoint.quarantine_on_failure,
        latest: serialize_data_source_latest_quality(latest),
        expectations: @endpoint.expectations.order(:name).map { |e| serialize_data_source_expectation(e) }
      })
    end

    # GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/contract
    # Read-only aggregate contract verdict (schema + quality + freshness). A GET
    # must NOT trigger an outbound fetch, so the verdict is built from the latest
    # recorded query-log row rather than a live QueryService call: schema_valid /
    # quality_passed come straight off the row, and freshness is asserted from the
    # row's age (its cache_age_seconds) against the endpoint's SLA. With no prior
    # query the verdict is vacuously met (all signals "not asserted").
    def contract
      latest = ::Ai::DataSourceQuery.where(ai_data_source_endpoint_id: @endpoint.id).recent.first
      verdict = ::Ai::DataSources::ContractService.new.validate(
        data_source: @data_source,
        endpoint: @endpoint,
        envelope: contract_envelope_from_query(latest)
      )

      render_success(verdict)
    end

    # POST /api/v1/ai/data_sources/:data_source_id/introspect
    # Import an OpenAPI 3 document into endpoints via OpenApiImportService. Accepts
    # a parsed `spec` hash directly, or a `url`/`spec_url` for the server to fetch
    # through the SSRF-guarded HttpConnectionFactory. dry_run previews without
    # persisting. Gated by ai.data_sources.manage (it is a write surface).
    def introspect
      spec, fetch_error = resolve_openapi_spec
      return render_error(fetch_error, status: :unprocessable_content) if fetch_error
      return render_error("spec or url is required", status: :unprocessable_content) if spec.blank?

      dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run]) || false
      result = ::Ai::DataSources::OpenApiImportService.new(@data_source).import(spec, dry_run: dry_run)

      render_success(result.merge(dry_run: dry_run))

      log_audit_event("ai.data_sources.introspect", @data_source,
        dry_run: dry_run, created_count: result[:created].size)
    end

    # GET /api/v1/ai/data_sources/:data_source_id/subscriptions
    # List the pull-based monitoring subscriptions for this data source. Mirrors
    # the nested endpoints#index envelope ({ items, count }) and reuses the same
    # subscription summary shape the MCP DataSourceTool returns.
    def subscriptions_index
      subscriptions = @data_source.subscriptions.includes(:endpoint).order(created_at: :desc)
      render_success({
        items: subscriptions.map { |sub| serialize_subscription(sub) },
        count: subscriptions.size
      })
    end

    # POST /api/v1/ai/data_sources/:data_source_id/subscriptions
    # Create or update (idempotent on the source+endpoint pair) a pull-based
    # subscription. The endpoint is resolved from the body param endpoint_id, the
    # cadence from poll_frequency, and any per-poll params from params. Shares the
    # find_or_initialize-on-endpoint logic with DataSourceTool#subscribe_source.
    def subscriptions_create
      endpoint = @data_source.endpoints.find_by(id: subscription_params[:endpoint_id])
      return render_error("Endpoint not found", status: :not_found) if endpoint.nil?

      frequency = subscription_params[:poll_frequency].presence || "hourly"
      unless ::Ai::DataSourceSubscription::POLL_FREQUENCIES.include?(frequency)
        return render_error(
          "Invalid poll_frequency '#{frequency}' " \
          "(allowed: #{::Ai::DataSourceSubscription::POLL_FREQUENCIES.join(', ')})",
          status: :unprocessable_content
        )
      end

      subscription = @data_source.subscriptions.find_or_initialize_by(
        ai_data_source_endpoint_id: endpoint.id
      )
      new_record = subscription.new_record?
      subscription.poll_frequency = frequency
      subscription.params = subscription_poll_params
      subscription.status = "active"
      # Re-arm the cadence so a changed frequency takes effect on the next tick.
      subscription.next_poll_at = nil if new_record || subscription.poll_frequency_changed?

      if subscription.save
        subscription.schedule_next_poll! if subscription.next_poll_at.nil?
        render_success({ subscription: serialize_subscription(subscription) },
          status: new_record ? :created : :ok)
        log_audit_event("ai.data_sources.subscription.create", @data_source,
          endpoint_id: endpoint.id, poll_frequency: frequency, new_record: new_record)
      else
        render_validation_error(subscription.errors)
      end
    end

    # DELETE /api/v1/ai/data_sources/:data_source_id/subscriptions/:subscription_id
    # Cancel (delete) a subscription scoped to this data source.
    def subscriptions_destroy
      subscription = @data_source.subscriptions.find_by(id: params[:subscription_id])
      return render_error("Subscription not found", status: :not_found) if subscription.nil?

      if subscription.destroy
        render_success({ message: "Subscription cancelled successfully" })
        log_audit_event("ai.data_sources.subscription.delete", @data_source,
          subscription_id: params[:subscription_id])
      else
        render_error("Failed to cancel subscription", status: :unprocessable_content)
      end
    end

    private

    # Subscription summary shape — kept in lockstep with the AiDataSourceSubscription
    # frontend TS type and Ai::Tools::DataSourceTool#subscription_summary so the REST
    # and MCP surfaces serialize a subscription identically.
    def serialize_subscription(subscription)
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
        last_etag: subscription.last_etag,
        consecutive_failures: subscription.consecutive_failures,
        agent_id: subscription.ai_agent_id
      }
    end

    # Strong params for the subscription create body. The frontend posts
    # { subscription: { endpoint_id, poll_frequency } }; endpoint_id + poll_frequency
    # are scalars, params is a free-form per-poll variable hash handled separately.
    def subscription_params
      params.fetch(:subscription, {}).permit(:endpoint_id, :poll_frequency)
    end

    # Free-form per-poll variables for the governed fetch. Permitted as an open hash
    # because endpoint query/path/body variables are source-specific (the
    # MonitorService runs them through the same redacting QueryService).
    def subscription_poll_params
      raw = params.dig(:subscription, :params) || {}
      raw = raw.permit! if raw.respond_to?(:permit!)
      raw.to_h
    end

    def set_endpoint
      return unless @data_source

      @endpoint = @data_source.endpoints.find(params[:endpoint_id])
    rescue ActiveRecord::RecordNotFound
      render_error("Endpoint not found", status: :not_found)
    end

    # Full AiDataSourceSchemaVersion shape (mirrors the model + the frontend TS
    # type): includes the persisted schema snapshot and structural diff, not just
    # the compact summary.
    def serialize_data_source_schema_version(version)
      {
        id: version.id,
        ai_data_source_endpoint_id: version.ai_data_source_endpoint_id,
        version: version.version,
        schema: version.schema,
        checksum: version.checksum,
        classification: version.classification,
        diff: version.diff,
        created_at: version.created_at&.iso8601,
        updated_at: version.updated_at&.iso8601
      }
    end

    # AiDataSourceExpectation shape (mirrors the model + the frontend TS type).
    def serialize_data_source_expectation(expectation)
      {
        id: expectation.id,
        ai_data_source_endpoint_id: expectation.ai_data_source_endpoint_id,
        name: expectation.name,
        rule_type: expectation.rule_type,
        config: expectation.config,
        severity: expectation.severity,
        is_active: expectation.is_active,
        created_at: expectation.created_at&.iso8601,
        updated_at: expectation.updated_at&.iso8601
      }
    end

    # DataSourceLatestQuality shape distilled from the most recent query-log row.
    # results/anomalies ride on the row's metadata when the quality stage recorded
    # them; nil when the endpoint has never run a quality-checked fetch.
    def serialize_data_source_latest_quality(query)
      return nil unless query

      meta = query.metadata.is_a?(Hash) ? query.metadata : {}
      {
        quality_score: query.quality_score&.to_f,
        quality_passed: query.quality_passed,
        quarantined: query.quarantined,
        schema_drift: query.schema_drift,
        evaluated_at: query.created_at&.iso8601,
        results: meta["quality_results"] || meta["results"] || [],
        anomalies: meta["anomalies"] || []
      }
    end

    # Build a synthetic FetchEnvelope for ContractService from a recorded query
    # row, WITHOUT performing an outbound fetch (a GET must stay side-effect-free).
    # The three contract signals are read from the row: schema_valid /
    # quality_passed straight off the columns, and freshness via cache_age_seconds
    # (seconds since the row was recorded) measured against the endpoint SLA. An
    # empty envelope (no prior query) yields an all-nil, vacuously-met verdict.
    def contract_envelope_from_query(query)
      return {} unless query

      {
        success: query.status == "success",
        status: query.status,
        quality_passed: query.quality_passed,
        data: [],
        provenance: {
          schema_valid: query.schema_valid,
          quality_passed: query.quality_passed,
          cache_age_seconds: [(Time.current - query.created_at).round, 0].max
        }
      }
    end

    # Resolve the OpenAPI document for #introspect. Precedence: an inline parsed
    # `spec` hash, else a `url`/`spec_url` fetched through the SSRF-guarded
    # HttpConnectionFactory (resolve-and-pin) and parsed as JSON. Returns
    # [spec_hash_or_nil, error_string_or_nil].
    def resolve_openapi_spec
      raw = params[:spec]
      if raw.present?
        raw = raw.permit!.to_h if raw.respond_to?(:permit!)
        return [raw.to_h, nil] if raw.respond_to?(:to_h)
      end

      url = params[:spec_url].presence || params[:url].presence
      return [nil, nil] if url.blank?

      fetch_openapi_spec(url)
    end

    # Fetch + parse a remote OpenAPI JSON document with SSRF protection. The URL is
    # resolved-and-pinned before the request leaves the process, and again on every
    # redirect hop, by HttpConnectionFactory.
    def fetch_openapi_spec(url)
      ::Ai::DataSources::HttpConnectionFactory.validate_url!(url)

      conn = Faraday.new do |f|
        f.use ::Ai::DataSources::HttpConnectionFactory::SsrfGuardMiddleware
        f.response :follow_redirects,
                   limit: 5,
                   callback: ::Ai::DataSources::HttpConnectionFactory.method(:validate_redirect!)
        f.options.open_timeout = 5
        f.options.timeout = 20
        f.adapter Faraday.default_adapter
      end

      response = conn.get(url) { |req| req.headers["Accept"] = "application/json" }
      unless response.success?
        return [nil, "Failed to fetch spec (HTTP #{response.status})"]
      end

      [JSON.parse(response.body.to_s), nil]
    rescue ::Ai::DataSources::HttpConnectionFactory::SsrfError => e
      [nil, "Spec URL blocked by egress policy: #{e.message}"]
    rescue JSON::ParserError => e
      [nil, "Spec URL did not return valid JSON: #{e.message}"]
    rescue StandardError => e
      Rails.logger.warn("[DataSourceEndpoints] OpenAPI spec fetch failed: #{e.class}: #{e.message}")
      [nil, "Could not fetch spec from URL"]
    end

    def endpoint_params
      params.require(:endpoint).permit(
        :name, :slug, :http_method, :path_template, :response_format,
        :expected_content_type, :cache_ttl_seconds, :monitorable, :change_detection,
        query_template: {},
        body_template: {},
        response_mapping: {},
        response_schema: {},
        metadata: {},
        pagination: {}
      )
    end

    # Free-form caller params for the governed fetch. Permitted as an open hash
    # because endpoint query/path/body variables are source-specific; the
    # QueryService redacts everything before persistence.
    def query_request_params
      raw = params[:params] || params[:query_params] || {}
      raw = raw.permit! if raw.respond_to?(:permit!)
      raw.to_h
    end

    # Map a FetchEnvelope status token to an HTTP status for render_error.
    def query_error_status(status)
      case status
      when "rate_limited" then :too_many_requests
      when "blocked" then :forbidden
      when "timeout" then :gateway_timeout
      else :bad_gateway
      end
    end
  end
end
