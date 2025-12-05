# frozen_string_literal: true

# AiAgentExecutionChannel - Agent execution monitoring channel
#
# This channel is a specialized wrapper around AiOrchestrationChannel
# focused specifically on agent execution monitoring and updates.
#
class AiAgentExecutionChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user
    return reject unless params[:execution_id]

    execution_id = params[:execution_id]
    @execution = AiAgentExecution.find_by(execution_id: execution_id)

    return reject unless @execution
    return reject unless @execution.account_id == current_user.account_id

    # Subscribe to agent execution updates
    stream_from "ai_agent_execution:#{execution_id}"

    transmit({
      type: 'subscription.confirmed',
      channel: 'agent_execution',
      execution_id: execution_id,
      timestamp: Time.current.iso8601
    })

    Rails.logger.info "[AiAgentExecutionChannel] User #{current_user.id} subscribed to execution #{execution_id}"
  end

  def unsubscribed
    Rails.logger.info "[AiAgentExecutionChannel] User #{current_user&.id} unsubscribed"
  end

  # Request execution status
  def request_status(_data = {})
    return transmit_error('Execution not found') unless @execution

    @execution.reload

    transmit({
      type: 'execution_status',
      execution: serialize_execution(@execution),
      timestamp: Time.current.iso8601
    })
  rescue StandardError => e
    transmit_error(e.message)
  end

  # Request agent status through orchestration channel
  def request_agent_status(data)
    return transmit_error('Missing agent_id') unless data['agent_id']

    agent = AiAgent.find_by(id: data['agent_id'], account_id: current_user.account_id)
    return transmit_error('Agent not found') unless agent

    # Get recent executions for the agent
    recent_executions = AiAgentExecution.where(
      ai_agent_id: agent.id,
      account_id: current_user.account_id
    ).order(created_at: :desc).limit(5)

    transmit({
      type: 'agent_status',
      agent_id: agent.id,
      agent_name: agent.name,
      status: agent.status,
      recent_executions: recent_executions.map { |exec| serialize_execution(exec) },
      timestamp: Time.current.iso8601
    })
  rescue StandardError => e
    transmit_error(e.message)
  end

  # Class methods for broadcasting
  class << self
    def broadcast_execution_update(execution_id, update_data)
      ActionCable.server.broadcast(
        "ai_agent_execution:#{execution_id}",
        update_data.merge(
          timestamp: Time.current.iso8601
        )
      )
    end

    def broadcast_status_change(execution_id, status, details = {})
      ActionCable.server.broadcast(
        "ai_agent_execution:#{execution_id}",
        {
          type: 'status_change',
          execution_id: execution_id,
          status: status,
          **details,
          timestamp: Time.current.iso8601
        }
      )
    end
  end

  private

  def serialize_execution(execution)
    {
      id: execution.id,
      execution_id: execution.execution_id,
      agent_id: execution.ai_agent_id,
      agent_name: execution.ai_agent&.name,
      status: execution.status,
      started_at: execution.started_at&.iso8601,
      completed_at: execution.completed_at&.iso8601,
      execution_time_ms: execution.execution_time_ms,
      total_cost: execution.total_cost,
      input_data: execution.input_data,
      output_data: execution.output_data,
      error_details: execution.error_details
    }
  end

  def transmit_error(message)
    transmit({
      type: 'error',
      error: message,
      timestamp: Time.current.iso8601
    })
  end
end
