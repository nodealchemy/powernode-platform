# frozen_string_literal: true

module System
  class NodeModuleSerializer
    def initialize(node_module)
      @node_module = node_module
    end

    def as_json
      {
        id: @node_module.id,
        name: @node_module.name,
        description: @node_module.description,
        variety: @node_module.variety,
        enabled: @node_module.enabled,
        public: @node_module.public,
        priority: @node_module.priority,
        mask: @node_module.mask,
        file_spec: @node_module.file_spec,
        config: @node_module.config,
        node_platform_id: @node_module.node_platform_id,
        node_platform_name: @node_module.node_platform&.name,
        category_id: @node_module.category_id,
        category_name: @node_module.category&.name,
        copy_path_id: @node_module.copy_path_id,
        copy_path_name: @node_module.copy_path&.name,
        dependencies_count: @node_module.module_dependencies.count,
        dependents_count: @node_module.dependent_relationships.count,
        assignments_count: @node_module.node_module_assignments.count,
        templates_count: @node_module.template_modules.count,
        created_at: @node_module.created_at,
        updated_at: @node_module.updated_at
      }
    end
  end
end
