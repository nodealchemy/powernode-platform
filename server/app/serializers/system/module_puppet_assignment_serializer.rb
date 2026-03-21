# frozen_string_literal: true

module System
  class ModulePuppetAssignmentSerializer
    def initialize(assignment)
      @assignment = assignment
    end

    def as_json
      {
        id: @assignment.id,
        node_module_id: @assignment.node_module_id,
        node_module_name: @assignment.node_module_name,
        puppet_module_id: @assignment.puppet_module_id,
        puppet_module_name: @assignment.puppet_module_name,
        config: @assignment.config,
        parameters: @assignment.parameters,
        enabled: @assignment.enabled,
        priority: @assignment.priority,
        display_name: @assignment.display_name,
        created_at: @assignment.created_at,
        updated_at: @assignment.updated_at
      }
    end
  end
end
