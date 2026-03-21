# frozen_string_literal: true

module System
  class NodeModuleAssignmentSerializer
    def initialize(assignment)
      @assignment = assignment
    end

    def as_json
      {
        id: @assignment.id,
        node_id: @assignment.node_id,
        node_name: @assignment.node&.name,
        node_module_id: @assignment.node_module_id,
        module_name: @assignment.module_name,
        module_variety: @assignment.module_variety,
        config: @assignment.config,
        merged_config: @assignment.merged_config,
        enabled: @assignment.enabled,
        priority: @assignment.priority,
        created_at: @assignment.created_at,
        updated_at: @assignment.updated_at
      }
    end
  end
end
