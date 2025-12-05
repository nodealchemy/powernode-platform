# frozen_string_literal: true

class AddCurrentNodeIdToAiWorkflowRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_workflow_runs, :current_node_id, :string
  end
end
