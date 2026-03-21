# frozen_string_literal: true

module System
  class ProviderNetworkSubnetSerializer
    def initialize(subnet)
      @subnet = subnet
    end

    def as_json
      {
        id: @subnet.id,
        name: @subnet.name,
        description: @subnet.description,
        external_id: @subnet.external_id,
        cidr_block: @subnet.cidr_block,
        status: @subnet.status,
        is_public: @subnet.is_public,
        map_public_ip_on_launch: @subnet.map_public_ip_on_launch,
        available_ip_count: @subnet.available_ip_count,
        config: @subnet.config,
        network_id: @subnet.network_id,
        network_name: @subnet.network_name,
        availability_zone_id: @subnet.availability_zone_id,
        zone_name: @subnet.zone_name,
        can_delete: @subnet.can_delete?,
        created_at: @subnet.created_at,
        updated_at: @subnet.updated_at
      }
    end
  end
end
