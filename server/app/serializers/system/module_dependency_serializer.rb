# frozen_string_literal: true

module System
  class ModuleDependencySerializer
    def initialize(dependency)
      @dependency = dependency
    end

    def as_json
      {
        id: @dependency.id,
        node_module_id: @dependency.node_module_id,
        node_module_name: @dependency.node_module&.name,
        dependency_id: @dependency.dependency_id,
        dependency_name: @dependency.dependency&.name,
        dependency_type: @dependency.dependency_type,
        required: @dependency.required,
        version_constraint: @dependency.version_constraint,
        created_at: @dependency.created_at,
        updated_at: @dependency.updated_at
      }
    end
  end
end
