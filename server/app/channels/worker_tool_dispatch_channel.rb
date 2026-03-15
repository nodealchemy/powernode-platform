# frozen_string_literal: true

# WebSocket channel for worker tool dispatch requests.
# Workers subscribe during agent execution to send tool_definitions and
# dispatch_tool requests over a persistent connection instead of per-call HTTP.
#
# Protocol:
#   1. Worker connects with a worker JWT token
#   2. Worker subscribes to this channel
#   3. Worker sends action messages with request_id for correlation
#   4. Channel transmits responses with matching request_id
#
# Actions:
#   - tool_definitions: Get available tools for an agent
#   - dispatch_tool: Execute a tool call through the platform
#   - ping: Connection health check
class WorkerToolDispatchChannel < ApplicationCable::Channel
  def subscribed
    unless connection.current_worker&.active?
      Rails.logger.warn "[WorkerToolDispatch] Rejected: no active worker on connection"
      reject
      return
    end

    stream_from "worker_tool_dispatch:#{connection.current_worker.id}"
    Rails.logger.info "[WorkerToolDispatch] Worker #{connection.current_worker.name} subscribed"
  end

  def unsubscribed
    Rails.logger.info "[WorkerToolDispatch] Worker #{connection.current_worker&.name} unsubscribed"
  end

  # Return tool definitions available to the specified agent.
  # data: { request_id:, agent_id: }
  def tool_definitions(data)
    agent = Ai::Agent.find(data["agent_id"])
    bridge = Ai::AgentToolBridgeService.new(agent: agent, account: agent.account)

    transmit({
      request_id: data["request_id"],
      success: true,
      data: { tools: bridge.tool_definitions_for_llm, tools_enabled: bridge.tools_enabled? }
    })
  rescue StandardError => e
    Rails.logger.error "[WorkerToolDispatch] tool_definitions error: #{e.message}"
    transmit({ request_id: data["request_id"], success: false, error: e.message })
  end

  # Dispatch a tool call through the platform tool registrar.
  # data: { request_id:, agent_id:, tool_call: { name:, id:, arguments: } }
  def dispatch_tool(data)
    agent = Ai::Agent.find(data["agent_id"])
    bridge = Ai::AgentToolBridgeService.new(agent: agent, account: agent.account)
    tool_call = data["tool_call"].deep_symbolize_keys

    result_json = bridge.dispatch_tool_call(tool_call)
    result = begin
      JSON.parse(result_json)
    rescue StandardError
      result_json
    end

    transmit({ request_id: data["request_id"], success: true, data: { result: result } })
  rescue StandardError => e
    Rails.logger.error "[WorkerToolDispatch] dispatch_tool error: #{e.message}"
    transmit({ request_id: data["request_id"], success: false, error: e.message })
  end

  # Connection health check.
  # data: { request_id: }
  def ping(data)
    transmit({ request_id: data["request_id"], success: true, data: { pong: true } })
  end
end
