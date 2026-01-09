# frozen_string_literal: true

# AiWorkflowOrchestrationChannel - Workflow management channel
#
# This channel is a specialized wrapper around AiOrchestrationChannel
# focused specifically on workflow orchestration operations.
#
class AiWorkflowOrchestrationChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    # Subscribe to account-level workflow events
    stream_from "ai_orchestration:account:#{current_user.account_id}"

    transmit({
      type: "subscription.confirmed",
      channel: "workflow_orchestration",
      timestamp: Time.current.iso8601
    })

    Rails.logger.info "[AiWorkflowOrchestrationChannel] User #{current_user.id} subscribed to account #{current_user.account_id}"
  end

  def unsubscribed
    Rails.logger.info "[AiWorkflowOrchestrationChannel] User #{current_user&.id} unsubscribed"
  end

  # Create workflow
  def create_workflow(data)
    return transmit_error("Missing workflow data") unless data["workflow"]

    workflow_params = data["workflow"]
    nodes = data["nodes"] || []
    edges = data["edges"] || []

    workflow = AiWorkflow.create!(
      account: current_user.account,
      created_by_user: current_user,
      name: workflow_params["name"],
      description: workflow_params["description"]
    )

    # Create nodes
    nodes.each do |node_data|
      workflow.nodes.create!(
        node_id: node_data["node_id"],
        node_type: node_data["node_type"],
        name: node_data["name"],
        position_x: node_data["position_x"],
        position_y: node_data["position_y"],
        configuration: node_data["configuration"] || {}
      )
    end

    # Create edges
    edges.each do |edge_data|
      workflow.edges.create!(
        edge_id: edge_data["edge_id"],
        source_node_id: edge_data["source_node_id"],
        target_node_id: edge_data["target_node_id"]
      )
    end

    transmit({
      type: "workflow_created",
      workflow: serialize_workflow(workflow)
    })

  rescue StandardError => e
    transmit_error(e.message)
  end

  # Update workflow
  def update_workflow(data)
    return transmit_error("Missing workflow_id") unless data["workflow_id"]

    workflow = AiWorkflow.find(data["workflow_id"])
    return transmit_error("Workflow not found") unless workflow
    return transmit_error("Unauthorized") unless workflow.account_id == current_user.account_id

    workflow.update!(data["updates"])

    transmit({
      type: "workflow_updated",
      workflow: serialize_workflow(workflow)
    })

    # Broadcast collaborative update to other users
    self.class.broadcast_workflow_collaborative_update(
      current_user.account_id,
      workflow.id,
      current_user,
      "updated"
    )

  rescue StandardError => e
    transmit_error(e.message)
  end

  # Execute workflow
  def execute_workflow(data)
    return transmit_error("Missing workflow_id") unless data["workflow_id"]

    workflow = AiWorkflow.find(data["workflow_id"])
    return transmit_error("Workflow not found") unless workflow
    return transmit_error("Unauthorized") unless workflow.account_id == current_user.account_id

    workflow_run = workflow.execute(
      input_variables: data["input_variables"] || {},
      user: current_user
    )

    transmit({
      type: "workflow_execution_started",
      workflow_run: serialize_workflow_run(workflow_run)
    })

  rescue StandardError => e
    transmit_error(e.message)
  end

  # Class methods for broadcasting
  class << self
    def broadcast_workflow_lock(account_id, workflow_id, user)
      ActionCable.server.broadcast(
        "ai_orchestration:account:#{account_id}",
        {
          type: "workflow_locked",
          workflow_id: workflow_id,
          locked_by: {
            id: user.id,
            full_name: user.full_name,
            email: user.email
          },
          timestamp: Time.current.iso8601
        }
      )
    end

    def broadcast_workflow_unlock(account_id, workflow_id, user)
      ActionCable.server.broadcast(
        "ai_orchestration:account:#{account_id}",
        {
          type: "workflow_unlocked",
          workflow_id: workflow_id,
          unlocked_by: {
            id: user.id,
            full_name: user.full_name,
            email: user.email
          },
          timestamp: Time.current.iso8601
        }
      )
    end

    def broadcast_workflow_collaborative_update(account_id, workflow_id, user, action)
      ActionCable.server.broadcast(
        "ai_orchestration:account:#{account_id}",
        {
          type: "workflow_collaborative_update",
          workflow_id: workflow_id,
          updated_by: {
            id: user.id,
            full_name: user.full_name,
            email: user.email
          },
          action: action,
          timestamp: Time.current.iso8601
        }
      )
    end
  end

  private

  def serialize_workflow(workflow)
    {
      id: workflow.id,
      name: workflow.name,
      description: workflow.description,
      status: workflow.status,
      created_at: workflow.created_at.iso8601
    }
  end

  def serialize_workflow_run(workflow_run)
    {
      id: workflow_run.id,
      run_id: workflow_run.run_id,
      status: workflow_run.status,
      trigger_type: workflow_run.trigger_type,
      created_at: workflow_run.created_at.iso8601,
      started_at: workflow_run.started_at&.iso8601
    }
  end

  def transmit_error(message)
    transmit({
      type: "error",
      error: message,
      timestamp: Time.current.iso8601
    })
  end
end
