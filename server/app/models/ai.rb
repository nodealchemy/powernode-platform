# frozen_string_literal: true

# AI namespace for workflow-related models
# This module provides namespace for:
# - Ai::Workflow
# - Ai::WorkflowNode
# - Ai::WorkflowEdge
# - Ai::WorkflowRun
# - Ai::WorkflowNodeExecution
# - Ai::WorkflowVariable
# - Ai::WorkflowTrigger
# - Ai::WorkflowSchedule
# - Ai::WorkflowTemplate
# - Ai::WorkflowTemplateInstallation
# - Ai::WorkflowApprovalToken
# - Ai::WorkflowCheckpoint
# - Ai::WorkflowCompensation
# - Ai::WorkflowRunLog
module Ai
  def self.table_name_prefix
    "ai_"
  end
end
