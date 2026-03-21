# frozen_string_literal: true

module System
  class NodeSerializer
    def initialize(node)
      @node = node
    end

    def as_json
      {
        id: @node.id,
        name: @node.name,
        description: @node.description,
        enabled: @node.enabled,
        config: @node.config,
        public_address: @node.public_address,
        allocate_public_ip: @node.allocate_public_ip,
        node_template_id: @node.node_template_id,
        node_template_name: @node.node_template&.name,
        worker_id: @node.worker_id,
        worker_name: @node.worker&.name,
        instance_count: @node.node_instances.count,
        running_instances_count: @node.node_instances.running.count,
        created_at: @node.created_at,
        updated_at: @node.updated_at
      }
    end
  end
end
