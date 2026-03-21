# frozen_string_literal: true

module System
  class NodeTemplateSerializer
    def initialize(template)
      @template = template
    end

    def as_json
      {
        id: @template.id,
        name: @template.name,
        description: @template.description,
        enabled: @template.enabled,
        public: @template.public,
        admin_user: @template.admin_user,
        config: @template.config,
        node_platform_id: @template.node_platform_id,
        platform_name: @template.node_platform&.name,
        nodes_count: @template.nodes.count,
        created_at: @template.created_at,
        updated_at: @template.updated_at
      }
    end
  end
end
