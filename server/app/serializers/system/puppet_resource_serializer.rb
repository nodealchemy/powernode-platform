# frozen_string_literal: true

module System
  class PuppetResourceSerializer
    def initialize(puppet_resource)
      @puppet_resource = puppet_resource
    end

    def as_json
      {
        id: @puppet_resource.id,
        name: @puppet_resource.name,
        description: @puppet_resource.description,
        resource_type: @puppet_resource.resource_type,
        title: @puppet_resource.title,
        path: @puppet_resource.path,
        data: @puppet_resource.data,
        enabled: @puppet_resource.enabled,
        exported: @puppet_resource.exported,
        parameters: @puppet_resource.parameters,
        config: @puppet_resource.config,
        puppet_module_id: @puppet_resource.puppet_module_id,
        puppet_module_name: @puppet_resource.puppet_module.name,
        resource_identifier: @puppet_resource.resource_identifier,
        created_at: @puppet_resource.created_at,
        updated_at: @puppet_resource.updated_at
      }
    end
  end
end
