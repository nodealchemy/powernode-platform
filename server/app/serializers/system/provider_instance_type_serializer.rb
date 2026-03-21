# frozen_string_literal: true

module System
  class ProviderInstanceTypeSerializer
    attr_reader :instance_type

    def initialize(instance_type)
      @instance_type = instance_type
    end

    def as_json
      {
        id: instance_type.id,
        name: instance_type.name,
        description: instance_type.description,
        instance_type_code: instance_type.instance_type_code,
        vcpus: instance_type.vcpus,
        memory_mb: instance_type.memory_mb,
        memory_gb: instance_type.memory_gb,
        storage_gb: instance_type.storage_gb,
        hourly_price: instance_type.hourly_price,
        enabled: instance_type.enabled,
        specs: instance_type.specs,
        display_name: instance_type.display_name,
        provider_id: instance_type.provider_id,
        provider_name: instance_type.provider&.name,
        region_count: instance_type.provider_regions.count,
        created_at: instance_type.created_at&.iso8601,
        updated_at: instance_type.updated_at&.iso8601
      }
    end
  end
end
