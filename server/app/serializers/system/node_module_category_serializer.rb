# frozen_string_literal: true

module System
  class NodeModuleCategorySerializer
    def initialize(category)
      @category = category
    end

    def as_json
      {
        id: @category.id,
        name: @category.name,
        description: @category.description,
        enabled: @category.enabled,
        public: @category.public,
        icon: @category.icon,
        color: @category.color,
        position: @category.position,
        parent_id: @category.parent_id,
        parent_name: @category.parent&.name,
        children_count: @category.children.count,
        modules_count: @category.node_modules.count,
        depth: @category.depth,
        created_at: @category.created_at,
        updated_at: @category.updated_at
      }
    end
  end
end
