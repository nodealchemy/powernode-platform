# frozen_string_literal: true

module Ai
  module DataSourceSerialization
    extend ActiveSupport::Concern

    private

    def serialize_data_source(ds)
      {
        id: ds.id,
        account_id: ds.account_id,
        name: ds.name,
        slug: ds.slug,
        source_type: ds.source_type,
        category: ds.category,
        protocol: ds.protocol,
        is_active: ds.is_active,
        requires_auth: ds.requires_auth,
        respect_robots: ds.respect_robots,
        crawl_delay_seconds: ds.crawl_delay_seconds,
        api_base_url: ds.api_base_url,
        priority_order: ds.priority_order,
        capabilities: ds.capabilities,
        health_status: ds.health_status,
        last_health_check_at: ds.last_health_check_at&.iso8601,
        effectiveness_score: ds.effectiveness_score&.to_f,
        usage_count: ds.usage_count,
        positive_usage_count: ds.positive_usage_count,
        negative_usage_count: ds.negative_usage_count,
        usage_success_rate: ds.usage_success_rate,
        last_used_at: ds.last_used_at&.iso8601,
        created_at: ds.created_at.iso8601,
        updated_at: ds.updated_at.iso8601,
        credential_count: ds.credentials.size,
        stats: {
          credentials_count: ds.credentials.size
        }
      }
    end

    def serialize_data_source_detail(ds)
      serialize_data_source(ds).merge(
        description: ds.description,
        documentation_url: ds.documentation_url,
        configuration: ds.configuration,
        default_parameters: ds.default_parameters,
        rate_limits: ds.rate_limits,
        metadata: ds.metadata,
        # x-com-provider campaign (I5): read-only in this view. auth_config carries
        # only provider endpoint URLs/scopes (authorize_url/token_url/scopes), never
        # secrets — the frontend uses authorize_url's presence to decide whether to
        # show the OAuth2 connect panel for this source. Editing it is out of scope
        # here; sources get it from a template (e.g. x_com_template) or an admin tool.
        auth_config: ds.auth_config,
        credentials: ds.credentials.map { |c| serialize_data_source_credential(c) },
        quota: ds.quota_summary
      )
    end

    def serialize_data_source_credential(cred)
      {
        id: cred.id,
        name: cred.name,
        is_active: cred.is_active,
        is_default: cred.is_default,
        expires_at: cred.expires_at&.iso8601,
        last_used_at: cred.last_used_at&.iso8601,
        last_test_at: cred.last_test_at&.iso8601,
        last_test_status: cred.last_test_status,
        last_error: cred.last_error,
        created_at: cred.created_at.iso8601,
        updated_at: cred.updated_at.iso8601,
        # x-com-provider campaign (I5): OAuth2 connect state for the frontend connect
        # panel. Only presence/derived booleans travel here — client_id, tokens, and
        # client_secret themselves are NEVER serialized (mirrors api_key/api_secret,
        # which have never been exposed by this method either).
        oauth_configured: cred.client_id.present?,
        oauth_connected: cred.decrypted_access_token.present?,
        oauth_scopes: cred.oauth_scopes,
        oauth_token_expires_at: cred.access_token_expires_at&.iso8601,
        oauth_token_expired: cred.token_expired?,
        data_source: {
          id: cred.data_source.id,
          name: cred.data_source.name,
          source_type: cred.data_source.source_type
        },
        stats: {
          success_count: cred.success_count,
          failure_count: cred.failure_count,
          consecutive_failures: cred.consecutive_failures,
          success_rate: calculate_data_source_credential_success_rate(cred)
        }
      }
    end

    def calculate_data_source_credential_success_rate(cred)
      total = cred.success_count + cred.failure_count
      return 0 if total.zero?

      ((cred.success_count.to_f / total) * 100).round(2)
    end

    def serialize_data_source_endpoint(ep)
      {
        id: ep.id,
        ai_data_source_id: ep.ai_data_source_id,
        name: ep.name,
        slug: ep.slug,
        http_method: ep.http_method,
        path_template: ep.path_template,
        response_format: ep.response_format,
        expected_content_type: ep.expected_content_type,
        cache_ttl_seconds: ep.cache_ttl_seconds,
        monitorable: ep.monitorable,
        change_detection: ep.change_detection,
        query_template: ep.query_template,
        body_template: ep.body_template,
        response_mapping: ep.response_mapping,
        response_schema: ep.response_schema,
        metadata: ep.metadata,
        pagination: ep.pagination,
        incremental: ep.incremental,
        created_at: ep.created_at&.iso8601,
        updated_at: ep.updated_at&.iso8601
      }
    end
  end
end
