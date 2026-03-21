# frozen_string_literal: true

module System
  class PuppetModuleSerializer
    def initialize(puppet_module)
      @puppet_module = puppet_module
    end

    def as_json
      {
        id: @puppet_module.id,
        name: @puppet_module.name,
        description: @puppet_module.description,
        enabled: @puppet_module.enabled,
        public: @puppet_module.public,
        version: @puppet_module.version,
        author: @puppet_module.author,
        license: @puppet_module.license,
        source_url: @puppet_module.source_url,
        project_url: @puppet_module.project_url,
        forge_name: @puppet_module.forge_name,
        dependencies: @puppet_module.dependencies,
        config: @puppet_module.config,
        metadata: @puppet_module.metadata,
        resource_count: @puppet_module.puppet_resources.count,
        resource_types: @puppet_module.resource_types,
        assigned_modules_count: @puppet_module.module_puppet_assignments.count,
        created_at: @puppet_module.created_at,
        updated_at: @puppet_module.updated_at
      }
    end
  end
end
