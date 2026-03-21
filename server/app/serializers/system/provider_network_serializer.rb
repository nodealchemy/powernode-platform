# frozen_string_literal: true

module System
  class ProviderNetworkSerializer
    def initialize(network)
      @network = network
    end

    def as_json
      {
        id: @network.id,
        name: @network.name,
        description: @network.description,
        external_id: @network.external_id,
        cidr_block: @network.cidr_block,
        status: @network.status,
        is_default: @network.is_default,
        enable_dns_support: @network.enable_dns_support,
        enable_dns_hostnames: @network.enable_dns_hostnames,
        config: @network.config,
        provider_id: @network.provider_id,
        provider_name: @network.provider&.name,
        provider_region_id: @network.provider_region_id,
        region_name: @network.provider_region&.name,
        subnet_count: @network.subnet_count,
        public_subnets_count: @network.public_subnets.count,
        private_subnets_count: @network.private_subnets.count,
        available_ip_count: @network.available_ip_count,
        can_delete: @network.can_delete?,
        created_at: @network.created_at,
        updated_at: @network.updated_at
      }
    end
  end
end
