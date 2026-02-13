# frozen_string_literal: true

module Ai
  module ProviderSerialization
    extend ActiveSupport::Concern

    private

    def serialize_provider(provider)
      {
        id: provider.id,
        account_id: provider.account_id,
        name: provider.name,
        slug: provider.slug,
        provider_type: provider.provider_type,
        is_active: provider.is_active,
        api_base_url: provider.api_base_url,
        priority_order: provider.priority_order,
        capabilities: provider.capabilities,
        created_at: provider.created_at.iso8601,
        updated_at: provider.updated_at.iso8601,
        health_status: calculate_provider_health_status(provider),
        stats: {
          credentials_count: provider.provider_credentials.count,
          supported_models_count: provider.supported_models&.length || 0
        },
        credential_count: provider.provider_credentials.count,
        model_count: provider.supported_models&.length || 0
      }
    end

    def serialize_provider_detail(provider)
      serialize_provider(provider).merge(
        description: provider.description,
        documentation_url: provider.documentation_url,
        status_url: provider.status_url,
        supported_models: provider.supported_models || [],
        default_parameters: provider.default_parameters,
        rate_limits: provider.rate_limits || {},
        pricing_info: provider.pricing_info || {},
        metadata: provider.metadata,
        credentials: provider.provider_credentials.map { |c| serialize_credential(c) }
      )
    end

    def serialize_credential(credential)
      {
        id: credential.id,
        name: credential.name,
        is_active: credential.is_active,
        is_default: credential.is_default,
        last_used_at: credential.last_used_at&.iso8601,
        last_test_at: credential.last_test_at&.iso8601,
        last_test_status: credential.last_test_status,
        created_at: credential.created_at.iso8601,
        updated_at: credential.updated_at.iso8601,
        provider: {
          id: credential.provider.id,
          name: credential.provider.name,
          provider_type: credential.provider.provider_type
        },
        stats: {
          success_count: credential.success_count,
          failure_count: credential.failure_count,
          success_rate: calculate_credential_success_rate(credential)
        }
      }
    end

    def calculate_provider_health_status(provider)
      return "degraded" unless provider.is_active

      active_credentials = provider.provider_credentials.where(is_active: true)
      return "degraded" if active_credentials.empty?

      tested_credentials = active_credentials.where.not(last_test_at: nil)
      return "healthy" if tested_credentials.empty?

      successful = tested_credentials.where(last_test_status: "success").count
      total = tested_credentials.count
      success_rate = (successful.to_f / total * 100).round

      if success_rate >= 80
        "healthy"
      elsif success_rate >= 50
        "degraded"
      else
        "critical"
      end
    end

    def calculate_credential_success_rate(credential)
      total = credential.success_count + credential.failure_count
      return 0 if total.zero?

      ((credential.success_count.to_f / total) * 100).round(2)
    end
  end
end
