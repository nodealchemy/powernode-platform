# frozen_string_literal: true

module System
  class NodeInstanceSerializer
    def initialize(instance)
      @instance = instance
    end

    def as_json
      {
        id: @instance.id,
        name: @instance.name,
        description: @instance.description,
        variety: @instance.variety,
        status: @instance.status,
        config: @instance.config,
        private_ip_address: @instance.private_ip_address,
        public_ip_address: @instance.public_ip_address,
        vpn_ip_address: @instance.vpn_ip_address,
        node_id: @instance.node_id,
        node_name: @instance.node&.name,
        active: @instance.active?,
        created_at: @instance.created_at,
        updated_at: @instance.updated_at
      }
    end
  end
end
