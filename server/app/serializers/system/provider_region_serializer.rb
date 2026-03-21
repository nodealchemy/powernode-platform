# frozen_string_literal: true

module System
  class ProviderRegionSerializer
    def initialize(region)
      @region = region
    end

    def as_json
      {
        id: @region.id,
        name: @region.name,
        description: @region.description,
        region_code: @region.region_code,
        endpoint_url: @region.endpoint_url,
        enabled: @region.enabled,
        kernel_image: @region.kernel_image,
        machine_image: @region.machine_image,
        ramdisk_image: @region.ramdisk_image,
        capabilities: @region.capabilities,
        provider_id: @region.provider_id,
        provider_name: @region.provider&.name,
        availability_zones_count: @region.availability_zones.count,
        instance_types_count: @region.region_instance_types.count,
        created_at: @region.created_at,
        updated_at: @region.updated_at
      }
    end
  end
end
