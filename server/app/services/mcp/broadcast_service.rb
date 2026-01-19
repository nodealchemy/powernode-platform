# frozen_string_literal: true

# MCP Broadcast Service - Coordinates MCP event broadcasting across the platform
module Mcp
  class BroadcastService
  include Singleton

  def initialize
    @logger = Rails.logger
  end

  # =============================================================================
  # TOOL EVENT BROADCASTING
  # =============================================================================

  def self.broadcast_tool_event(event_type, tool_id, data, account)
    instance.broadcast_tool_event(event_type, tool_id, data, account)
  end

  def broadcast_tool_event(event_type, tool_id, data, account)
    @logger.info "[MCP_BROADCAST] Broadcasting tool event: #{event_type} for #{tool_id}"

    message = {
      type: "tool_event",
      event_type: event_type,
      tool_id: tool_id,
      data: data,
      account_id: account&.id,
      timestamp: Time.current.iso8601
    }

    # Broadcast to multiple channels
    broadcast_to_mcp_channels(message, account)
    broadcast_to_tool_specific_streams(tool_id, message)
    broadcast_to_monitoring_systems(message)
  end

  # =============================================================================
  # WORKFLOW EVENT BROADCASTING
  # =============================================================================

  def self.broadcast_workflow_event(event_type, workflow_id, data, account)
    instance.broadcast_workflow_event(event_type, workflow_id, data, account)
  end

  def broadcast_workflow_event(event_type, workflow_id, data, account)
    @logger.info "[MCP_BROADCAST] Broadcasting workflow event: #{event_type} for #{workflow_id}"

    message = {
      type: "workflow_event",
      event_type: event_type,
      workflow_id: workflow_id,
      data: data,
      account_id: account&.id,
      timestamp: Time.current.iso8601
    }

    broadcast_to_mcp_channels(message, account)
    broadcast_to_workflow_specific_streams(workflow_id, message)
    broadcast_to_monitoring_systems(message)
  end

  # =============================================================================
  # AGENT EVENT BROADCASTING
  # =============================================================================

  def self.broadcast_agent_event(event_type, agent_id, data, account)
    instance.broadcast_agent_event(event_type, agent_id, data, account)
  end

  def broadcast_agent_event(event_type, agent_id, data, account)
    @logger.info "[MCP_BROADCAST] Broadcasting agent event: #{event_type} for #{agent_id}"

    message = {
      type: "agent_event",
      event_type: event_type,
      agent_id: agent_id,
      data: data,
      account_id: account&.id,
      timestamp: Time.current.iso8601
    }

    broadcast_to_mcp_channels(message, account)
    broadcast_to_agent_specific_streams(agent_id, message)
    broadcast_to_monitoring_systems(message)
  end

  # =============================================================================
  # EXECUTION EVENT BROADCASTING
  # =============================================================================

  def self.broadcast_execution_event(event_type, execution_data, account)
    instance.broadcast_execution_event(event_type, execution_data, account)
  end

  def broadcast_execution_event(event_type, execution_data, account)
    @logger.info "[MCP_BROADCAST] Broadcasting execution event: #{event_type}"

    message = {
      type: "execution_event",
      event_type: event_type,
      execution_data: execution_data,
      account_id: account&.id,
      timestamp: Time.current.iso8601
    }

    broadcast_to_mcp_channels(message, account)
    broadcast_to_monitoring_systems(message)
  end

  # =============================================================================
  # REGISTRY EVENT BROADCASTING
  # =============================================================================

  def self.broadcast_registry_event(event_type, registry_data, account)
    instance.broadcast_registry_event(event_type, registry_data, account)
  end

  def broadcast_registry_event(event_type, registry_data, account)
    @logger.info "[MCP_BROADCAST] Broadcasting registry event: #{event_type}"

    message = {
      type: "registry_event",
      event_type: event_type,
      registry_data: registry_data,
      account_id: account&.id,
      timestamp: Time.current.iso8601
    }

    broadcast_to_mcp_channels(message, account)
    broadcast_to_tool_registry_streams(message, account)
    broadcast_to_monitoring_systems(message)
  end

  # =============================================================================
  # CONNECTION EVENT BROADCASTING
  # =============================================================================

  def self.broadcast_connection_event(event_type, connection_data)
    instance.broadcast_connection_event(event_type, connection_data)
  end

  def broadcast_connection_event(event_type, connection_data)
    @logger.debug "[MCP_BROADCAST] Broadcasting connection event: #{event_type}"

    message = {
      type: "connection_event",
      event_type: event_type,
      connection_data: connection_data,
      timestamp: Time.current.iso8601
    }

    # Only broadcast to monitoring systems for connection events
    broadcast_to_monitoring_systems(message)
  end

  # =============================================================================
  # SYSTEM EVENT BROADCASTING
  # =============================================================================

  def self.broadcast_system_event(event_type, system_data)
    instance.broadcast_system_event(event_type, system_data)
  end

  def broadcast_system_event(event_type, system_data)
    @logger.info "[MCP_BROADCAST] Broadcasting system event: #{event_type}"

    message = {
      type: "system_event",
      event_type: event_type,
      system_data: system_data,
      timestamp: Time.current.iso8601
    }

    # Broadcast to all MCP channels for system events
    broadcast_to_all_mcp_channels(message)
    broadcast_to_monitoring_systems(message)
  end

  # =============================================================================
  # PRIVATE BROADCASTING METHODS
  # =============================================================================

  private

  def broadcast_to_mcp_channels(message, account)
    return unless account

    # Broadcast to account-specific MCP channel
    McpChannel.broadcast_to_account(account.id, message)

    @logger.debug "[MCP_BROADCAST] Broadcasted to MCP channels for account #{account.id}"
  end

  def broadcast_to_tool_specific_streams(tool_id, message)
    # Broadcast to tool-specific stream
    ActionCable.server.broadcast("mcp_tool_#{tool_id}_events", format_mcp_message(message))

    # Also broadcast to all tools stream if this is a significant event
    if significant_tool_event?(message[:event_type])
      ActionCable.server.broadcast("mcp_tool_events_global", format_mcp_message(message))
    end

    @logger.debug "[MCP_BROADCAST] Broadcasted to tool-specific streams for #{tool_id}"
  end

  def broadcast_to_workflow_specific_streams(workflow_id, message)
    # Broadcast to workflow-specific stream
    ActionCable.server.broadcast("mcp_workflow_#{workflow_id}_events", format_mcp_message(message))

    @logger.debug "[MCP_BROADCAST] Broadcasted to workflow-specific streams for #{workflow_id}"
  end

  def broadcast_to_agent_specific_streams(agent_id, message)
    # Broadcast to agent-specific stream
    ActionCable.server.broadcast("mcp_agent_#{agent_id}_events", format_mcp_message(message))

    @logger.debug "[MCP_BROADCAST] Broadcasted to agent-specific streams for #{agent_id}"
  end

  def broadcast_to_tool_registry_streams(message, account)
    return unless account

    # Broadcast to account-specific tool registry stream
    ActionCable.server.broadcast("mcp_tools_#{account.id}", format_mcp_message(message))

    @logger.debug "[MCP_BROADCAST] Broadcasted to tool registry streams for account #{account.id}"
  end

  def broadcast_to_all_mcp_channels(message)
    # Broadcast to global MCP system stream
    ActionCable.server.broadcast("mcp_system_events", format_mcp_message(message))

    @logger.debug "[MCP_BROADCAST] Broadcasted to all MCP channels"
  end

  def broadcast_to_monitoring_systems(message)
    # Send to external monitoring systems if configured
    send_to_external_monitoring(message)

    # Broadcast to internal monitoring streams
    ActionCable.server.broadcast("mcp_monitoring", format_mcp_message(message))

    @logger.debug "[MCP_BROADCAST] Broadcasted to monitoring systems"
  end

  def send_to_external_monitoring(message)
    # Integration with external monitoring systems
    # This could include DataDog, New Relic, custom webhooks, etc.

    if Rails.env.production?
      # Example: Send to DataDog
      send_to_datadog(message) if datadog_configured?

      # Example: Send to custom webhook
      send_to_webhook(message) if webhook_configured?

      # Example: Send to logging service
      send_to_logging_service(message)
    end
  rescue StandardError => e
    @logger.error "[MCP_BROADCAST] Failed to send to external monitoring: #{e.message}"
  end

  def send_to_datadog(message)
    # DataDog integration
    return unless defined?(Datadog)

    Datadog::Statsd.increment("mcp.event", tags: [
      "event_type:#{message[:event_type]}",
      "type:#{message[:type]}",
      "account_id:#{message[:account_id]}"
    ])

    @logger.debug "[MCP_BROADCAST] Sent metrics to DataDog"
  end

  def send_to_webhook(message)
    # Custom webhook integration
    webhook_url = Rails.application.credentials.dig(:monitoring, :webhook_url)
    return unless webhook_url

    # Send async webhook request
    WebhookDeliveryJob.perform_async(webhook_url, message.to_json)

    @logger.debug "[MCP_BROADCAST] Queued webhook delivery"
  end

  def send_to_logging_service(message)
    # Structured logging for external log aggregation
    Rails.logger.tagged("MCP_EVENT") do
      Rails.logger.info({
        event_type: message[:event_type],
        type: message[:type],
        account_id: message[:account_id],
        timestamp: message[:timestamp],
        data: message.except(:timestamp)
      }.to_json)
    end
  end

  def format_mcp_message(message)
    {
      jsonrpc: "2.0",
      method: "notification",
      params: message
    }
  end

  def significant_tool_event?(event_type)
    %w[registered unregistered health_changed error].include?(event_type)
  end

  def datadog_configured?
    defined?(Datadog) && Rails.application.credentials.dig(:datadog, :api_key).present?
  end

  def webhook_configured?
    Rails.application.credentials.dig(:monitoring, :webhook_url).present?
  end
  end
end
