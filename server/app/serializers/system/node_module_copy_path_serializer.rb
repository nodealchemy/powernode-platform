# frozen_string_literal: true

module System
  class NodeModuleCopyPathSerializer
    def initialize(copy_path)
      @copy_path = copy_path
    end

    def as_json
      {
        id: @copy_path.id,
        name: @copy_path.name,
        description: @copy_path.description,
        source_path: @copy_path.source_path,
        destination_path: @copy_path.destination_path,
        enabled: @copy_path.enabled,
        recursive: @copy_path.recursive,
        preserve_permissions: @copy_path.preserve_permissions,
        modules_count: @copy_path.node_modules.count,
        created_at: @copy_path.created_at,
        updated_at: @copy_path.updated_at
      }
    end
  end
end
