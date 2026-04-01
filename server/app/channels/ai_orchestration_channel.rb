# frozen_string_literal: true

# AiOrchestrationChannel - Unified WebSocket channel for AI operations
#
# Handles real-time updates for:
# - Agent executions
# - Ralph Loops
# - Worktree sessions
# - Circuit breakers
# - Monitoring and analytics
# - System alerts
#
# Subscription patterns:
#   # Subscribe to all AI events for an account
#   channel.subscribe(type: 'account')
#
#   # Subscribe to monitoring events
#   channel.subscribe(type: 'monitoring')
#
class AiOrchestrationChannel < ApplicationCable::Channel
  # Event types
  EVENT_TYPES = %w[
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
    circuit_breaker.state_changed
    circuit_breaker.opened
    circuit_breaker.closed
    circuit_breaker.half_opened
    circuit_breaker.failure
    circuit_breaker.success
    circuit_breaker.reset
    ralph_loop.started
    ralph_loop.progress
    ralph_loop.iteration_completed
    ralph_loop.task_status_changed
    ralph_loop.learning_added
    ralph_loop.completed
    ralph_loop.failed
    ralph_loop.paused
    ralph_loop.cancelled
    worktree_session.status_changed
    worktree_session.provisioning
    worktree_session.active
    worktree_session.merging
    worktree_session.completed
    worktree_session.failed
    worktree_session.cancelled
    worktree_session.conflicts_detected
    worktree.status_changed
    worktree.created
    worktree.ready
    worktree.task_started
    worktree.completed
    worktree.failed
    worktree.log
    worktree.timeout
    worktree.test_started
    worktree.test_passed
    worktree.test_failed
    merge.started
    merge.completed
    merge.conflict
    merge.resolved
    merge.failed
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
    # Broadcast agent execution event
    #
    # @param event_type [String] Event type
    # @param agent_execution [Ai::AgentExecution] Agent execution
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

    # =============================================================================
    # RALPH LOOP BROADCASTING
    # =============================================================================

    # Broadcast Ralph Loop status update
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    # @param event_type [String] Event type (e.g., 'loop_started', 'loop_progress')
    # @param payload [Hash] Additional payload data
    def broadcast_ralph_loop_event(ralph_loop, event_type, payload = {})
      message = build_message(
        "ralph_loop.#{event_type}",
        "ralph_loop",
        ralph_loop.id,
        {
          loop_id: ralph_loop.id,
          status: ralph_loop.status,
          progress_percentage: ralph_loop.progress_percentage,
          current_iteration: ralph_loop.current_iteration,
          completed_task_count: ralph_loop.completed_tasks,
          task_count: ralph_loop.total_tasks,
          **payload
        }
      )

      # Broadcast to loop-specific stream
      ActionCable.server.broadcast(stream_key("ralph_loop", ralph_loop.id), message)

      # Also broadcast to account-level stream
      ActionCable.server.broadcast(stream_key("account", ralph_loop.account_id), message)

      Rails.logger.debug "[AiOrchestrationChannel] Ralph loop event #{event_type} broadcast for loop #{ralph_loop.id}"
    end

    # Broadcast Ralph Loop started
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    def broadcast_ralph_loop_started(ralph_loop)
      broadcast_ralph_loop_event(ralph_loop, "started")
    end

    # Broadcast Ralph Loop progress
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    def broadcast_ralph_loop_progress(ralph_loop)
      broadcast_ralph_loop_event(ralph_loop, "progress")
    end

    # Broadcast Ralph Loop iteration completed
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    # @param iteration_number [Integer] Completed iteration number
    def broadcast_ralph_loop_iteration_completed(ralph_loop, iteration_number)
      broadcast_ralph_loop_event(ralph_loop, "iteration_completed", {
        iteration_number: iteration_number
      })
    end

    # Broadcast Ralph Loop task status changed
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    # @param task [Ai::RalphTask] Task that changed
    def broadcast_ralph_loop_task_status_changed(ralph_loop, task)
      broadcast_ralph_loop_event(ralph_loop, "task_status_changed", {
        task_id: task.id,
        task_status: task.status
      })
    end

    # Broadcast Ralph Loop learning added
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    # @param learning [String] Learning text
    def broadcast_ralph_loop_learning_added(ralph_loop, learning)
      broadcast_ralph_loop_event(ralph_loop, "learning_added", {
        learning: learning
      })
    end

    # Broadcast Ralph Loop completed
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    def broadcast_ralph_loop_completed(ralph_loop)
      broadcast_ralph_loop_event(ralph_loop, "completed")
    end

    # Broadcast Ralph Loop failed
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    # @param error_message [String] Error message
    def broadcast_ralph_loop_failed(ralph_loop, error_message = nil)
      broadcast_ralph_loop_event(ralph_loop, "failed", {
        error_message: error_message || ralph_loop.error_message
      })
    end

    # Broadcast Ralph Loop paused
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    def broadcast_ralph_loop_paused(ralph_loop)
      broadcast_ralph_loop_event(ralph_loop, "paused")
    end

    # Broadcast Ralph Loop cancelled
    #
    # @param ralph_loop [Ai::RalphLoop] Ralph loop
    def broadcast_ralph_loop_cancelled(ralph_loop)
      broadcast_ralph_loop_event(ralph_loop, "cancelled")
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

    # =============================================================================
    # WORKTREE SESSION BROADCASTING
    # =============================================================================

    # Broadcast worktree session event
    #
    # @param session [Ai::WorktreeSession] Worktree session
    # @param event_type [String] Event type
    # @param payload [Hash] Additional payload
    def broadcast_worktree_session_event(session, event_type, payload = {})
      message = build_message(
        "worktree_session.#{event_type}",
        "worktree_session",
        session.id,
        session.session_summary.merge(payload)
      )

      ActionCable.server.broadcast(stream_key("worktree_session", session.id), message)
      ActionCable.server.broadcast(stream_key("account", session.account_id), message)

      Rails.logger.debug "[AiOrchestrationChannel] Worktree session event #{event_type} for session #{session.id}"
    end

    # Broadcast individual worktree event
    #
    # @param worktree [Ai::Worktree] Worktree record
    # @param event_type [String] Event type
    # @param payload [Hash] Additional payload
    def broadcast_worktree_event(worktree, event_type, payload = {})
      message = build_message(
        "worktree.#{event_type}",
        "worktree_session",
        worktree.worktree_session_id,
        worktree.worktree_summary.merge(payload)
      )

      ActionCable.server.broadcast(stream_key("worktree_session", worktree.worktree_session_id), message)
      ActionCable.server.broadcast(stream_key("account", worktree.account_id), message)
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
    when "ralph_loop"
      ralph_loop = Ai::RalphLoop.find_by(id: resource_id)
      return unless ralph_loop

      transmit({
        event: "ralph_loop.progress",
        resource_type: "ralph_loop",
        resource_id: resource_id,
        payload: {
          loop_id: ralph_loop.id,
          status: ralph_loop.status,
          progress_percentage: ralph_loop.progress_percentage,
          current_iteration: ralph_loop.current_iteration,
          completed_task_count: ralph_loop.completed_tasks,
          task_count: ralph_loop.total_tasks
        },
        timestamp: Time.current.iso8601,
        is_initial_status: true
      })

      Rails.logger.debug "[AiOrchestrationChannel] Sent initial status for ralph_loop #{resource_id}: #{ralph_loop.status}"
    when "worktree_session"
      wt_session = Ai::WorktreeSession.find_by(id: resource_id)
      return unless wt_session

      transmit({
        event: "worktree_session.status_changed",
        resource_type: "worktree_session",
        resource_id: resource_id,
        payload: wt_session.session_summary,
        timestamp: Time.current.iso8601,
        is_initial_status: true
      })

      Rails.logger.debug "[AiOrchestrationChannel] Sent initial status for worktree_session #{resource_id}: #{wt_session.status}"
    end
  end

  def valid_subscription_type?(type)
    %w[account agent monitoring system circuit_breaker circuit_breaker_service ralph_loop worktree_session].include?(type)
  end

  def authorized_for_subscription?(subscription_type, resource_id)
    return false unless current_user

    case subscription_type
    when "account"
      # User can subscribe to their own account
      current_user.account_id.to_s == resource_id.to_s
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
    when "ralph_loop"
      # User can subscribe to Ralph loops in their account
      ralph_loop = Ai::RalphLoop.find_by(id: resource_id)
      ralph_loop && ralph_loop.account_id == current_user.account_id
    when "worktree_session"
      # User can subscribe to worktree sessions in their account
      wt_session = Ai::WorktreeSession.find_by(id: resource_id)
      wt_session && wt_session.account_id == current_user.account_id
    else
      false
    end
  end
end
