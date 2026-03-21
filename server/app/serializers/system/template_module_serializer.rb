# frozen_string_literal: true

module System
  class TemplateModuleSerializer
    def initialize(template_module)
      @template_module = template_module
    end

    def as_json
      {
        id: @template_module.id,
        node_template_id: @template_module.node_template_id,
        template_name: @template_module.template_name,
        node_module_id: @template_module.node_module_id,
        module_name: @template_module.module_name,
        module_variety: @template_module.module_variety,
        config: @template_module.config,
        merged_config: @template_module.merged_config,
        enabled: @template_module.enabled,
        priority: @template_module.priority,
        created_at: @template_module.created_at,
        updated_at: @template_module.updated_at
      }
    end
  end
end
