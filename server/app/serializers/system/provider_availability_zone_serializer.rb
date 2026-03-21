# frozen_string_literal: true

module System
  class ProviderAvailabilityZoneSerializer
    attr_reader :zone

    def initialize(zone)
      @zone = zone
    end

    def as_json
      {
        id: zone.id,
        name: zone.name,
        zone_code: zone.zone_code,
        status: zone.status,
        enabled: zone.enabled,
        capabilities: zone.capabilities,
        provider_region_id: zone.provider_region_id,
        region_name: zone.provider_region&.name,
        provider_name: zone.provider&.name,
        operational: zone.operational?,
        created_at: zone.created_at&.iso8601,
        updated_at: zone.updated_at&.iso8601
      }
    end
  end
end
