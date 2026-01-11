# frozen_string_literal: true

module Devops
  class ProviderSerializer
    def initialize(provider, options = {})
      @provider = provider
      @options = options
    end

    def as_json
      {
        id: @provider.id,
        name: @provider.name,
        provider_type: @provider.provider_type,
        base_url: @provider.base_url,
        api_version: @provider.api_version,
        configuration: @provider.configuration,
        capabilities: @provider.capabilities,
        is_active: @provider.is_active,
        is_default: @provider.is_default,
        last_health_check_at: @provider.last_health_check_at,
        health_status: @provider.health_status,
        api_endpoint: @provider.api_endpoint,
        repository_count: @provider.repositories.count,
        pipeline_count: @provider.pipelines.count,
        created_at: @provider.created_at,
        updated_at: @provider.updated_at
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(provider, options = {})
      new(provider, options).as_json
    end

    def self.serialize_collection(providers, options = {})
      providers.map { |provider| serialize(provider, options) }
    end
  end
end
