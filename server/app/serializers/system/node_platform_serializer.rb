# frozen_string_literal: true

module System
  class NodePlatformSerializer
    def initialize(platform)
      @platform = platform
    end

    def as_json
      {
        id: @platform.id,
        name: @platform.name,
        description: @platform.description,
        enabled: @platform.enabled,
        public: @platform.public,
        node_architecture_id: @platform.node_architecture_id,
        architecture_name: @platform.node_architecture&.name,
        build_script: @platform.build_script,
        init_script: @platform.init_script,
        sync_script: @platform.sync_script,
        templates_count: @platform.node_templates.count,
        created_at: @platform.created_at,
        updated_at: @platform.updated_at
      }
    end
  end
end
