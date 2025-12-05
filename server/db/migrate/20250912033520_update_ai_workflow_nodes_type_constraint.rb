# frozen_string_literal: true

class UpdateAiWorkflowNodesTypeConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing constraint
    remove_check_constraint :ai_workflow_nodes, name: "ai_workflow_nodes_type_check"
    
    # Add updated constraint with start and end node types
    add_check_constraint :ai_workflow_nodes, 
      "node_type::text = ANY (ARRAY['start'::character varying::text, 'end'::character varying::text, 'ai_agent'::character varying::text, 'api_call'::character varying::text, 'webhook'::character varying::text, 'condition'::character varying::text, 'loop'::character varying::text, 'transform'::character varying::text, 'delay'::character varying::text, 'human_approval'::character varying::text, 'sub_workflow'::character varying::text, 'merge'::character varying::text, 'split'::character varying::text])", 
      name: "ai_workflow_nodes_type_check"
  end

  def down
    # Remove the updated constraint
    remove_check_constraint :ai_workflow_nodes, name: "ai_workflow_nodes_type_check"
    
    # Restore the original constraint
    add_check_constraint :ai_workflow_nodes,
      "node_type::text = ANY (ARRAY['ai_agent'::character varying::text, 'api_call'::character varying::text, 'webhook'::character varying::text, 'condition'::character varying::text, 'loop'::character varying::text, 'transform'::character varying::text, 'delay'::character varying::text, 'human_approval'::character varying::text, 'sub_workflow'::character varying::text, 'merge'::character varying::text, 'split'::character varying::text])", 
      name: "ai_workflow_nodes_type_check"
  end
end
