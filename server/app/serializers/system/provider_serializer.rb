# frozen_string_literal: true

module System
  class ProviderSerializer
    def initialize(provider)
      @provider = provider
    end

    def as_json
      {
        id: @provider.id,
        name: @provider.name,
        description: @provider.description,
        provider_type: @provider.provider_type,
        enabled: @provider.enabled,
        public: @provider.public,
        config: @provider.config,
        capabilities: @provider.capabilities,
        regions_count: @provider.provider_regions.count,
        connections_count: @provider.provider_connections.count,
        instance_types_count: @provider.provider_instance_types.count,
        created_at: @provider.created_at,
        updated_at: @provider.updated_at
      }
    end
  end
end
