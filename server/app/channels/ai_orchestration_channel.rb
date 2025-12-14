# frozen_string_literal: true

# AiOrchestrationChannel - Unified WebSocket channel for all AI operations
#
# Replaces:
# - AiWorkflowExecutionChannel
# - AiConversationChannel
# - AiWorkflowAnalyticsChannel
# - AiWorkflowMarketplaceChannel
# - AiWorkflowRecoveryChannel
#
# Handles real-time updates for:
# - Workflow executions
# - Agent executions
# - Conversations
# - Monitoring and analytics
# - System alerts
#
# Subscription patterns:
#   # Subscribe to all AI events for an account
#   channel.subscribe(type: 'account')
#
#   # Subscribe to specific workflow
#   channel.subscribe(type: 'workflow', id: workflow_id)
#
#   # Subscribe to specific workflow run
#   channel.subscribe(type: 'workflow_run', id: run_id)
#
#   # Subscribe to monitoring events
#   channel.subscribe(type: 'monitoring')
#
class AiOrchestrationChannel < ApplicationCable::Channel
  # Event types
  EVENT_TYPES = %w[
    workflow.created
    workflow.updated
    workflow.deleted
    workflow.status.changed
    workflow.execution.started
    workflow.execution.completed
    workflow.execution.failed
    node.execution.started
    node.execution.running
    node.execution.completed
    node.execution.failed
    node.duration.updated
    agent.created
    agent.updated
    agent.deleted
    agent.execution.started
    agent.execution.completed
    agent.execution.failed
    conversation.created
    conversation.updated
    conversation.message.added
    monitoring.alert.triggered
    monitoring.metrics.updated
    system.health.changed
    batch.execution.started
    batch.execution.progress
    batch.execution.paused
    batch.execution.resumed
    batch.execution.cancelled
    batch.execution.completed
    batch.execution.failed
    batch.workflow.started
    batch.workflow.completed
    batch.workflow.failed
    streaming.execution.started
    streaming.execution.paused
    streaming.execution.resumed
    streaming.execution.cancelled
    streaming.execution.completed
    streaming.execution.failed
    streaming.message.received
    streaming.node.changed
    circuit_breaker.state_changed
    circuit_breaker.opened
    circuit_breaker.closed
    circuit_breaker.half_opened
    circuit_breaker.failure
    circuit_breaker.success
    circuit_breaker.reset
  ].freeze

  # =============================================================================
  # SUBSCRIPTION
  # =============================================================================

  def subscribed
    subscription_type = params[:type]
    resource_id = params[:id]

    unless valid_subscription_type?(subscription_type)
      Rails.logger.warn "[AiOrchestrationChannel] Invalid subscription type: #{subscription_type}"
      reject
      return
    end

    unless authorized_for_subscription?(subscription_type, resource_id)
      Rails.logger.warn "[AiOrchestrationChannel] Unauthorized subscription attempt"
      reject
      return
    end

    subscribe_to_stream(subscription_type, resource_id)

    Rails.logger.info "[AiOrchestrationChannel] Subscribed: type=#{subscription_type} id=#{resource_id} user=#{current_user.id}"
  end

  def unsubscribed
    Rails.logger.info "[AiOrchestrationChannel] Unsubscribed user=#{current_user.id}"
    stop_all_streams
  end

  # =============================================================================
  # CLASS METHODS FOR BROADCASTING
  # =============================================================================

  class << self
    # Broadcast workflow event
    #
    # @param event_type [String] Type of event
    # @param workflow_id [String] Workflow ID
    # @param payload [Hash] Event payload
    # @param account [Account] Account context
    def broadcast_workflow_event(event_type, workflow_id, payload, account)
      broadcast_event(
        event_type: event_type,
        resource_type: "workflow",
        resource_id: workflow_id,
        payload: payload,
        account: account
      )
    end

    # Broadcast workflow run event
    #
    # @param event_type [String] Type of event
    # @param workflow_run [AiWorkflowRun] Workflow run
    # @param payload [Hash] Event payload
    def broadcast_workflow_run_event(event_type, workflow_run, payload = {})
      message = build_message(event_type, "workflow_run", workflow_run.run_id, payload)

      # Generate stream keys
      run_stream = stream_key("workflow_run", workflow_run.run_id)
      workflow_stream = stream_key("workflow", workflow_run.ai_workflow_id)
      account_stream = stream_key("account", workflow_run.account_id)

      Rails.logger.debug "[AiOrchestrationChannel] Broadcasting #{event_type} to streams:"
      Rails.logger.debug "  - Run stream: #{run_stream}"
      Rails.logger.debug "  - Workflow stream: #{workflow_stream}"
      Rails.logger.debug "  - Account stream: #{account_stream}"

      # Use ActionCable.server.broadcast for named streams
      # Broadcast to run-specific stream
      ActionCable.server.broadcast(run_stream, message)

      # Also broadcast to workflow-level stream
      ActionCable.server.broadcast(workflow_stream, message)

      # And to account-level stream
      ActionCable.server.broadcast(account_stream, message)

      Rails.logger.debug "[AiOrchestrationChannel] Broadcasts sent successfully"
    end

    # Broadcast node execution update
    #
    # @param node_execution [AiWorkflowNodeExecution] Node execution
    # @param event_type [String] Event type
    def broadcast_node_execution(node_execution, event_type = "node.execution.updated")
      workflow_run = node_execution.ai_workflow_run

      payload = {
        workflow_run_id: workflow_run.id,
        run_id: workflow_run.run_id,
        node_execution: serialize_node_execution(node_execution)
      }

      broadcast_workflow_run_event(event_type, workflow_run, payload)
    end

    # Broadcast node duration update
    #
    # @param node_execution [AiWorkflowNodeExecution] Node execution
    # @param elapsed_ms [Integer] Elapsed time in milliseconds
    def broadcast_node_duration(node_execution, elapsed_ms)
      workflow_run = node_execution.ai_workflow_run

      payload = {
        workflow_run_id: workflow_run.id,
        run_id: workflow_run.run_id,
        node_execution: {
          execution_id: node_execution.execution_id,
          execution_time_ms: elapsed_ms,
          elapsed_ms: elapsed_ms,
          elapsed_display: format_elapsed_time(elapsed_ms),
          status: node_execution.status
        }
      }

      broadcast_workflow_run_event("node.duration.updated", workflow_run, payload)
    end

    # Broadcast agent execution event
    #
    # @param event_type [String] Event type
    # @param agent_execution [AiAgentExecution] Agent execution
    # @param payload [Hash] Event payload
    def broadcast_agent_event(event_type, agent_execution, payload = {})
      broadcast_event(
        event_type: event_type,
        resource_type: "agent_execution",
        resource_id: agent_execution.id,
        payload: {
          agent_id: agent_execution.ai_agent_id,
          execution_id: agent_execution.execution_id,
          **payload
        },
        account: agent_execution.account
      )
    end

    # Broadcast monitoring alert
    #
    # @param alert [Hash] Alert data
    def broadcast_alert(alert)
      account_id = alert[:account_id]

      # CRITICAL FIX: Use ActionCable.server.broadcast for named streams
      ActionCable.server.broadcast(
        stream_key("monitoring", account_id),
        build_message(
          "monitoring.alert.triggered",
          "alert",
          alert[:alert_type],
          alert
        )
      )

      # Also broadcast to account stream
      ActionCable.server.broadcast(
        stream_key("account", account_id),
        build_message(
          "monitoring.alert.triggered",
          "alert",
          alert[:alert_type],
          alert
        )
      )
    end

    # Broadcast system health change
    #
    # @param health_data [Hash] Health status data
    # @param account [Account] Account context
    def broadcast_health_change(health_data, account)
      broadcast_event(
        event_type: "system.health.changed",
        resource_type: "system",
        resource_id: "health",
        payload: health_data,
        account: account
      )
    end

    # =============================================================================
    # BATCH EXECUTION BROADCASTING
    # =============================================================================

    # Broadcast batch execution started
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @param account [Account] Account context
    def broadcast_batch_started(batch_execution, account)
      payload = serialize_batch_execution(batch_execution)

      broadcast_batch_event(
        "batch.execution.started",
        batch_execution.batch_id,
        payload,
        account
      )
    end

    # Broadcast batch execution progress
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @param account [Account] Account context
    def broadcast_batch_progress(batch_execution, account)
      payload = serialize_batch_execution(batch_execution)

      broadcast_batch_event(
        "batch.execution.progress",
        batch_execution.batch_id,
        payload,
        account
      )
    end

    # Broadcast batch workflow completed
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @param workflow_result [Hash] Individual workflow result
    # @param account [Account] Account context
    def broadcast_batch_workflow_completed(batch_execution, workflow_result, account)
      payload = {
        batch_execution: serialize_batch_execution(batch_execution),
        workflow_id: workflow_result[:workflow_id],
        workflow_status: workflow_result
      }

      broadcast_batch_event(
        "batch.workflow.completed",
        batch_execution.batch_id,
        payload,
        account
      )
    end

    # Broadcast batch execution completed
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @param account [Account] Account context
    def broadcast_batch_completed(batch_execution, account)
      payload = serialize_batch_execution(batch_execution)

      broadcast_batch_event(
        "batch.execution.completed",
        batch_execution.batch_id,
        payload,
        account
      )
    end

    # Broadcast batch execution failed
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @param error [String] Error message
    # @param account [Account] Account context
    def broadcast_batch_failed(batch_execution, error, account)
      payload = serialize_batch_execution(batch_execution).merge(
        error: error,
        message: error
      )

      broadcast_batch_event(
        "batch.execution.failed",
        batch_execution.batch_id,
        payload,
        account
      )
    end

    # Broadcast batch execution paused
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @param account [Account] Account context
    def broadcast_batch_paused(batch_execution, account)
      payload = serialize_batch_execution(batch_execution)

      broadcast_batch_event(
        "batch.execution.paused",
        batch_execution.batch_id,
        payload,
        account
      )
    end

    # Broadcast batch execution resumed
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @param account [Account] Account context
    def broadcast_batch_resumed(batch_execution, account)
      payload = serialize_batch_execution(batch_execution)

      broadcast_batch_event(
        "batch.execution.resumed",
        batch_execution.batch_id,
        payload,
        account
      )
    end

    # Broadcast batch execution cancelled
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @param account [Account] Account context
    def broadcast_batch_cancelled(batch_execution, account)
      payload = serialize_batch_execution(batch_execution)

      broadcast_batch_event(
        "batch.execution.cancelled",
        batch_execution.batch_id,
        payload,
        account
      )
    end

    private

    # Build unified message format
    #
    # @param event_type [String] Event type
    # @param resource_type [String] Resource type
    # @param resource_id [String] Resource ID
    # @param payload [Hash] Event payload
    # @return [Hash] Formatted message
    def build_message(event_type, resource_type, resource_id, payload)
      {
        event: event_type,
        resource_type: resource_type,
        resource_id: resource_id,
        payload: payload,
        timestamp: Time.current.iso8601
      }
    end

    # Broadcast event to appropriate streams
    #
    # @param event_type [String] Event type
    # @param resource_type [String] Resource type
    # @param resource_id [String] Resource ID
    # @param payload [Hash] Event payload
    # @param account [Account] Account context
    def broadcast_event(event_type:, resource_type:, resource_id:, payload:, account:)
      message = build_message(event_type, resource_type, resource_id, payload)

      # CRITICAL FIX: Use ActionCable.server.broadcast for named streams
      # Broadcast to resource-specific stream
      ActionCable.server.broadcast(stream_key(resource_type, resource_id), message)

      # Broadcast to account-level stream
      if account
        ActionCable.server.broadcast(stream_key("account", account.id), message)
      end

      # Broadcast to monitoring stream if it's an error or alert
      if event_type.include?("failed") || event_type.include?("alert")
        ActionCable.server.broadcast(stream_key("monitoring", account&.id), message)
      end
    end

    # Generate stream key
    #
    # @param type [String] Stream type
    # @param id [String] Resource ID
    # @return [String] Stream key
    def stream_key(type, id)
      "ai_orchestration:#{type}:#{id}"
    end

    # Serialize node execution for broadcast
    #
    # @param execution [AiWorkflowNodeExecution] Node execution
    # @return [Hash] Serialized data
    def serialize_node_execution(execution)
      {
        id: execution.id,  # CRITICAL: Include database ID to match API response format
        execution_id: execution.execution_id,
        status: execution.status,
        started_at: execution.started_at&.iso8601,
        completed_at: execution.completed_at&.iso8601,
        execution_time_ms: execution.execution_time_ms,
        cost: execution.cost,
        retry_count: execution.retry_count,
        node: {
          node_id: execution.ai_workflow_node.node_id,
          node_type: execution.ai_workflow_node.node_type,
          name: execution.ai_workflow_node.name
        },
        input_data: execution.input_data,
        output_data: execution.output_data,
        error_details: execution.error_details.presence
      }
    end

    # Format elapsed time for display
    #
    # @param elapsed_ms [Integer] Elapsed time in milliseconds
    # @return [String] Formatted time
    def format_elapsed_time(elapsed_ms)
      elapsed_seconds = elapsed_ms / 1000.0

      if elapsed_seconds < 60
        "#{elapsed_seconds.round(1)}s"
      else
        minutes = (elapsed_seconds / 60).floor
        seconds = (elapsed_seconds % 60).round
        "#{minutes}m #{seconds}s"
      end
    end

    # Broadcast batch execution event
    #
    # @param event_type [String] Event type
    # @param batch_id [String] Batch execution ID
    # @param payload [Hash] Event payload
    # @param account [Account] Account context
    def broadcast_batch_event(event_type, batch_id, payload, account)
      message = build_message(event_type, "batch_execution", batch_id, payload)

      # Broadcast to batch-specific stream
      ActionCable.server.broadcast(stream_key("batch_execution", batch_id), message)

      # Also broadcast to account-level stream
      if account
        ActionCable.server.broadcast(stream_key("account", account.id), message)
      end

      Rails.logger.debug "[AiOrchestrationChannel] Batch event #{event_type} broadcast for batch #{batch_id}"
    end

    # Serialize batch execution for broadcast
    #
    # @param batch_execution [BatchWorkflowRun] Batch execution record
    # @return [Hash] Serialized data
    def serialize_batch_execution(batch_execution)
      {
        batch_id: batch_execution.batch_id,
        status: batch_execution.status,
        total_workflows: batch_execution.total_workflows,
        completed_workflows: batch_execution.completed_workflows,
        successful_workflows: batch_execution.successful_workflows,
        failed_workflows: batch_execution.failed_workflows,
        running_workflows: batch_execution.running_workflows,
        pending_workflows: batch_execution.pending_workflows,
        started_at: batch_execution.started_at&.iso8601,
        completed_at: batch_execution.completed_at&.iso8601,
        estimated_completion_at: batch_execution.estimated_completion_at&.iso8601,
        workflows: batch_execution.workflow_results || [],
        configuration: batch_execution.configuration || {}
      }
    end

    # =============================================================================
    # STREAMING EXECUTION BROADCASTING
    # =============================================================================

    # Broadcast streaming execution started
    #
    # @param workflow_run [AiWorkflowRun] Workflow run
    # @param account [Account] Account context
    def broadcast_streaming_started(workflow_run, account)
      payload = {
        run_id: workflow_run.run_id,
        workflow_id: workflow_run.ai_workflow_id,
        workflow_name: workflow_run.ai_workflow&.name || "Unknown Workflow"
      }

      broadcast_workflow_run_event("streaming.execution.started", workflow_run, payload)
    end

    # Broadcast streaming message received
    #
    # @param workflow_run [AiWorkflowRun] Workflow run
    # @param message [Hash] Streaming message data
    def broadcast_streaming_message(workflow_run, message)
      payload = {
        run_id: workflow_run.run_id,
        message: message
      }

      broadcast_workflow_run_event("streaming.message.received", workflow_run, payload)
    end

    # Broadcast streaming node changed
    #
    # @param workflow_run [AiWorkflowRun] Workflow run
    # @param node [AiWorkflowNode] Current node
    def broadcast_streaming_node_changed(workflow_run, node)
      payload = {
        run_id: workflow_run.run_id,
        current_node: {
          node_id: node.node_id,
          node_name: node.name,
          node_type: node.node_type
        }
      }

      broadcast_workflow_run_event("streaming.node.changed", workflow_run, payload)
    end

    # Broadcast streaming execution paused
    #
    # @param workflow_run [AiWorkflowRun] Workflow run
    def broadcast_streaming_paused(workflow_run)
      payload = {
        run_id: workflow_run.run_id
      }

      broadcast_workflow_run_event("streaming.execution.paused", workflow_run, payload)
    end

    # Broadcast streaming execution resumed
    #
    # @param workflow_run [AiWorkflowRun] Workflow run
    def broadcast_streaming_resumed(workflow_run)
      payload = {
        run_id: workflow_run.run_id
      }

      broadcast_workflow_run_event("streaming.execution.resumed", workflow_run, payload)
    end

    # Broadcast streaming execution completed
    #
    # @param workflow_run [AiWorkflowRun] Workflow run
    def broadcast_streaming_completed(workflow_run)
      payload = {
        run_id: workflow_run.run_id
      }

      broadcast_workflow_run_event("streaming.execution.completed", workflow_run, payload)
    end

    # Broadcast streaming execution failed
    #
    # @param workflow_run [AiWorkflowRun] Workflow run
    # @param error [String] Error message
    def broadcast_streaming_failed(workflow_run, error)
      payload = {
        run_id: workflow_run.run_id,
        error: error
      }

      broadcast_workflow_run_event("streaming.execution.failed", workflow_run, payload)
    end

    # Broadcast streaming execution cancelled
    #
    # @param workflow_run [AiWorkflowRun] Workflow run
    def broadcast_streaming_cancelled(workflow_run)
      payload = {
        run_id: workflow_run.run_id
      }

      broadcast_workflow_run_event("streaming.execution.cancelled", workflow_run, payload)
    end

    # =============================================================================
    # CIRCUIT BREAKER BROADCASTING
    # =============================================================================

    # Broadcast circuit breaker state changed
    #
    # @param breaker [Hash] Circuit breaker state
    # @param account [Account] Account context
    def broadcast_circuit_breaker_state_changed(breaker, account)
      broadcast_circuit_breaker_event("circuit_breaker.state_changed", breaker, account)
    end

    # Broadcast circuit breaker opened
    #
    # @param breaker [Hash] Circuit breaker state
    # @param account [Account] Account context
    def broadcast_circuit_breaker_opened(breaker, account)
      broadcast_circuit_breaker_event("circuit_breaker.opened", breaker, account)
    end

    # Broadcast circuit breaker closed
    #
    # @param breaker [Hash] Circuit breaker state
    # @param account [Account] Account context
    def broadcast_circuit_breaker_closed(breaker, account)
      broadcast_circuit_breaker_event("circuit_breaker.closed", breaker, account)
    end

    # Broadcast circuit breaker half-opened
    #
    # @param breaker [Hash] Circuit breaker state
    # @param account [Account] Account context
    def broadcast_circuit_breaker_half_opened(breaker, account)
      broadcast_circuit_breaker_event("circuit_breaker.half_opened", breaker, account)
    end

    # Broadcast circuit breaker failure
    #
    # @param breaker_id [String] Circuit breaker ID
    # @param metadata [Hash] Failure metadata
    # @param account [Account] Account context
    def broadcast_circuit_breaker_failure(breaker_id, metadata, account)
      payload = {
        breaker_id: breaker_id,
        metadata: metadata
      }

      message = build_message("circuit_breaker.failure", "circuit_breaker", breaker_id, payload)

      ActionCable.server.broadcast(stream_key("circuit_breaker", breaker_id), message)
      ActionCable.server.broadcast(stream_key("account", account.id), message) if account
    end

    # Broadcast circuit breaker success
    #
    # @param breaker_id [String] Circuit breaker ID
    # @param metadata [Hash] Success metadata
    # @param account [Account] Account context
    def broadcast_circuit_breaker_success(breaker_id, metadata, account)
      payload = {
        breaker_id: breaker_id,
        metadata: metadata
      }

      message = build_message("circuit_breaker.success", "circuit_breaker", breaker_id, payload)

      ActionCable.server.broadcast(stream_key("circuit_breaker", breaker_id), message)
      ActionCable.server.broadcast(stream_key("account", account.id), message) if account
    end

    # Broadcast circuit breaker reset
    #
    # @param breaker [Hash] Circuit breaker state
    # @param account [Account] Account context
    def broadcast_circuit_breaker_reset(breaker, account)
      broadcast_circuit_breaker_event("circuit_breaker.reset", breaker, account)
    end

    private

    # Broadcast circuit breaker event
    #
    # @param event_type [String] Event type
    # @param breaker [Hash] Circuit breaker state
    # @param account [Account] Account context
    def broadcast_circuit_breaker_event(event_type, breaker, account)
      payload = {
        breaker: breaker
      }

      message = build_message(event_type, "circuit_breaker", breaker[:id], payload)

      # Broadcast to breaker-specific stream
      ActionCable.server.broadcast(stream_key("circuit_breaker", breaker[:id]), message)

      # Broadcast to account-level stream
      ActionCable.server.broadcast(stream_key("account", account.id), message) if account

      Rails.logger.debug "[AiOrchestrationChannel] Circuit breaker event #{event_type} broadcast for breaker #{breaker[:id]}"
    end
  end

  private

  # =============================================================================
  # SUBSCRIPTION HELPERS
  # =============================================================================

  def subscribe_to_stream(subscription_type, resource_id)
    stream_key = self.class.send(:stream_key, subscription_type, resource_id)

    Rails.logger.info "[AiOrchestrationChannel] Subscribing to stream: #{stream_key} (type=#{subscription_type}, id=#{resource_id})"

    stream_from stream_key

    # Send initial connection confirmation
    transmit({
      type: "subscription.confirmed",
      subscription_type: subscription_type,
      resource_id: resource_id,
      stream_key: stream_key,
      timestamp: Time.current.iso8601
    })

    # CRITICAL FIX: Send current status on subscription to prevent race conditions
    # Client may subscribe after status has already changed from initial value
    send_current_status(subscription_type, resource_id)

    Rails.logger.debug "[AiOrchestrationChannel] Subscription confirmed and transmitted"
  end

  # Send current status of resource when client subscribes
  # This prevents race conditions where broadcasts are missed during connection setup
  def send_current_status(subscription_type, resource_id)
    case subscription_type
    when "workflow_run"
      workflow_run = AiWorkflowRun.find_by(run_id: resource_id)
      return unless workflow_run

      workflow_run_data = {
        id: workflow_run.id,
        run_id: workflow_run.run_id,
        ai_workflow_id: workflow_run.ai_workflow_id,
        status: workflow_run.status,
        trigger_type: workflow_run.trigger_type,
        started_at: workflow_run.started_at,
        completed_at: workflow_run.completed_at,
        created_at: workflow_run.created_at,
        duration_seconds: workflow_run.execution_duration_seconds,
        total_nodes: workflow_run.total_nodes,
        completed_nodes: workflow_run.completed_nodes,
        failed_nodes: workflow_run.failed_nodes,
        cost_usd: workflow_run.total_cost,
        error_details: workflow_run.error_details,
        progress_percentage: workflow_run.progress_percentage
      }

      transmit({
        event: "workflow.run.status.changed",
        type: "workflow_run",
        resource_id: resource_id,
        payload: {
          workflow_run: workflow_run_data
        },
        timestamp: Time.current.iso8601,
        is_initial_status: true
      })

      Rails.logger.debug "[AiOrchestrationChannel] Sent initial status for workflow_run #{resource_id}: #{workflow_run.status}"
    end
  end

  def valid_subscription_type?(type)
    %w[account workflow workflow_run agent monitoring system batch_execution circuit_breaker circuit_breaker_service].include?(type)
  end

  def authorized_for_subscription?(subscription_type, resource_id)
    return false unless current_user

    case subscription_type
    when "account"
      # User can subscribe to their own account
      current_user.account_id.to_s == resource_id.to_s
    when "workflow"
      # User can subscribe to workflows in their account
      workflow = AiWorkflow.find_by(id: resource_id)
      workflow && workflow.account_id == current_user.account_id
    when "workflow_run"
      # User can subscribe to workflow runs in their account
      workflow_run = AiWorkflowRun.find_by(run_id: resource_id)
      workflow_run && workflow_run.account_id == current_user.account_id
    when "agent"
      # User can subscribe to agents in their account
      agent = AiAgent.find_by(id: resource_id)
      agent && agent.account_id == current_user.account_id
    when "monitoring"
      # User can subscribe to monitoring for their account
      current_user.account_id.to_s == resource_id.to_s
    when "system"
      # System-level monitoring requires special permission
      current_user.has_permission?("system.admin")
    when "batch_execution"
      # User can subscribe to batch executions in their account
      batch_execution = BatchWorkflowRun.find_by(batch_id: resource_id)
      batch_execution && batch_execution.account_id == current_user.account_id
    when "circuit_breaker"
      # User can subscribe to circuit breakers in their account
      # If resource_id is 'all', allow subscription for monitoring all breakers
      if resource_id == "all"
        current_user.has_permission?("ai_orchestration.read") ||
          current_user.has_permission?("system.admin")
      else
        # Specific breaker subscription - would need to check breaker ownership
        # For now, allow if user has monitoring permissions
        current_user.has_permission?("ai_orchestration.read")
      end
    when "circuit_breaker_service"
      # User can subscribe to all breakers for a specific service
      current_user.has_permission?("ai_orchestration.read") ||
        current_user.has_permission?("system.admin")
    else
      false
    end
  end
end
