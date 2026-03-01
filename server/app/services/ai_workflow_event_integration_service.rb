# frozen_string_literal: true

# AiWorkflowEventIntegrationService - Platform integration for AI workflow events
#
# This service integrates the AI workflow event system with the broader platform,
# including broadcasting events to WebSocket channels, recording to audit logs,
# and triggering external integrations.
#
# Usage:
#   integration_service = AiWorkflowEventIntegrationService.instance
#   integration_service.broadcast_workflow_update(workflow_run)
#
class AiWorkflowEventIntegrationService
  include Singleton

  def initialize
    @running = false
    @mutex = Mutex.new
    @stats = {
      broadcasts_sent: 0,
      integrations_triggered: 0,
      errors: 0
    }

    setup_event_handlers
  end

  # Start the integration service
  def start
    @mutex.synchronize do
      return if @running

      @running = true
      Rails.logger.info "[IntegrationService] Started"
    end
  end

  # Stop the integration service
  def stop
    @mutex.synchronize do
      return unless @running

      @running = false
      Rails.logger.info "[IntegrationService] Stopped"
    end
  end

  # Get service status
  #
  # @return [Hash] Service status
  def status
    @mutex.synchronize do
      {
        running: @running,
        stats: @stats.dup
      }
    end
  end

  # Broadcast workflow run update to WebSocket channels
  #
  # @param workflow_run [Ai::WorkflowRun] The workflow run
  # @param event_type [String] The event type
  # @param additional_data [Hash] Additional data to include
  def broadcast_workflow_update(workflow_run, event_type = "workflow.updated", additional_data = {})
    return unless @running

    begin
      data = build_workflow_broadcast_data(workflow_run, additional_data)

      # Broadcast via ActionCable
      if defined?(AiOrchestrationChannel)
        AiOrchestrationChannel.broadcast_workflow_run_event(
          event_type,
          workflow_run,
          data
        )
      end

      # Also broadcast via MCP broadcast service
      if defined?(Mcp::BroadcastService)
        Mcp::BroadcastService.broadcast_workflow_event(
          event_type.tr(".", "_"),
          workflow_run.workflow_id,
          data,
          workflow_run.account
        )
      end

      @mutex.synchronize { @stats[:broadcasts_sent] += 1 }

      Rails.logger.debug "[IntegrationService] Broadcast: #{event_type} for run #{workflow_run.run_id}"
    rescue StandardError => e
      Rails.logger.error "[IntegrationService] Broadcast error: #{e.message}"
      @mutex.synchronize { @stats[:errors] += 1 }
    end
  end

  # Broadcast node execution update
  #
  # @param node_execution [Ai::WorkflowNodeExecution] The node execution
  # @param event_type [String] The event type
  def broadcast_node_update(node_execution, event_type = "workflow.node.updated")
    return unless @running

    begin
      workflow_run = node_execution.workflow_run
      node = node_execution.workflow_node

      data = {
        workflow_run_id: workflow_run.id,
        run_id: workflow_run.run_id,
        node_execution: {
          id: node_execution.id,
          execution_id: node_execution.execution_id,
          node_id: node_execution.node_id,
          node_name: node&.name,
          node_type: node&.node_type,
          status: node_execution.status,
          started_at: node_execution.started_at&.iso8601,
          completed_at: node_execution.completed_at&.iso8601,
          duration_ms: calculate_duration(node_execution),
          output_preview: truncate_output(node_execution.output_data)
        }
      }

      if defined?(AiOrchestrationChannel)
        AiOrchestrationChannel.broadcast_node_execution_event(
          event_type,
          node_execution,
          data
        )
      end

      @mutex.synchronize { @stats[:broadcasts_sent] += 1 }
    rescue StandardError => e
      Rails.logger.error "[IntegrationService] Node broadcast error: #{e.message}"
      @mutex.synchronize { @stats[:errors] += 1 }
    end
  end

  # Record workflow event to audit log
  #
  # @param workflow_run [Ai::WorkflowRun] The workflow run
  # @param event_type [String] The event type
  # @param details [Hash] Additional details
  def record_audit_event(workflow_run, event_type, details = {})
    return unless @running

    begin
      # Record to AuditLog if the model exists
      if defined?(AuditLog)
        AuditLog.create!(
          account_id: workflow_run.account_id,
          user_id: workflow_run.user_id,
          auditable_type: "Ai::WorkflowRun",
          auditable_id: workflow_run.id,
          action: event_type,
          changes: details,
          metadata: {
            workflow_id: workflow_run.workflow_id,
            run_id: workflow_run.run_id,
            recorded_at: Time.current.iso8601
          }
        )
      end

      Rails.logger.debug "[IntegrationService] Audit recorded: #{event_type} for run #{workflow_run.run_id}"
    rescue StandardError => e
      Rails.logger.error "[IntegrationService] Audit error: #{e.message}"
      @mutex.synchronize { @stats[:errors] += 1 }
    end
  end

  # Trigger external webhook for workflow event
  #
  # @param workflow [Ai::Workflow] The workflow
  # @param event_type [String] The event type
  # @param payload [Hash] The webhook payload
  def trigger_webhook(workflow, event_type, payload = {})
    return unless @running

    webhook_config = workflow.webhook_config
    return unless webhook_config.present? && webhook_config["url"].present?

    begin
      # Queue webhook delivery
      if defined?(WebhookDeliveryJob)
        WebhookDeliveryJob.perform_later(
          url: webhook_config["url"],
          event_type: event_type,
          payload: payload.merge(
            workflow_id: workflow.id,
            workflow_name: workflow.name,
            timestamp: Time.current.iso8601
          ),
          headers: webhook_config["headers"] || {},
          secret: webhook_config["secret"]
        )
      end

      @mutex.synchronize { @stats[:integrations_triggered] += 1 }

      Rails.logger.info "[IntegrationService] Webhook queued for #{workflow.name}: #{event_type}"
    rescue StandardError => e
      Rails.logger.error "[IntegrationService] Webhook error: #{e.message}"
      @mutex.synchronize { @stats[:errors] += 1 }
    end
  end

  # Send notification for workflow completion
  #
  # @param workflow_run [Ai::WorkflowRun] The completed workflow run
  def notify_completion(workflow_run)
    return unless @running

    begin
      workflow = workflow_run.workflow
      user = workflow_run.user

      return unless user

      notification_data = {
        title: "Workflow Completed",
        message: "#{workflow.name} has #{workflow_run.status}",
        workflow_id: workflow.id,
        workflow_run_id: workflow_run.id,
        status: workflow_run.status,
        duration_ms: workflow_run.duration_ms
      }

      # Create in-app notification if the model exists
      if defined?(Notification)
        Notification.create!(
          account_id: workflow_run.account_id,
          user_id: user.id,
          notification_type: "workflow_completion",
          title: notification_data[:title],
          message: notification_data[:message],
          data: notification_data,
          read: false
        )
      end

      # Broadcast real-time notification
      if defined?(NotificationChannel)
        NotificationChannel.broadcast_to(
          user,
          type: "workflow_completion",
          data: notification_data
        )
      end

      Rails.logger.debug "[IntegrationService] Completion notification sent for run #{workflow_run.run_id}"
    rescue StandardError => e
      Rails.logger.error "[IntegrationService] Notification error: #{e.message}"
      @mutex.synchronize { @stats[:errors] += 1 }
    end
  end

  private

  def setup_event_handlers
    # Register handlers with the event dispatcher
    dispatcher = AiWorkflowEventDispatcherService.instance

    # Handle workflow execution events
    dispatcher.register_handler("workflow.execution.started") do |event|
      handle_execution_started(event)
    end

    dispatcher.register_handler("workflow.execution.completed") do |event|
      handle_execution_completed(event)
    end

    dispatcher.register_handler("workflow.execution.failed") do |event|
      handle_execution_failed(event)
    end

    # Handle node events
    dispatcher.register_handler("workflow.node.completed") do |event|
      handle_node_completed(event)
    end

    dispatcher.register_handler("workflow.node.failed") do |event|
      handle_node_failed(event)
    end

    Rails.logger.info "[IntegrationService] Event handlers registered"
  rescue StandardError => e
    Rails.logger.error "[IntegrationService] Failed to setup handlers: #{e.message}"
  end

  def handle_execution_started(event)
    workflow_run = find_workflow_run(event[:data])
    return unless workflow_run

    broadcast_workflow_update(workflow_run, "workflow.execution.started")
    record_audit_event(workflow_run, "execution_started", event[:data])
  end

  def handle_execution_completed(event)
    workflow_run = find_workflow_run(event[:data])
    return unless workflow_run

    broadcast_workflow_update(workflow_run, "workflow.execution.completed")
    record_audit_event(workflow_run, "execution_completed", event[:data])
    notify_completion(workflow_run)

    # Trigger webhooks
    trigger_webhook(workflow_run.workflow, "execution.completed", {
      run_id: workflow_run.run_id,
      status: workflow_run.status,
      output: workflow_run.output_variables
    })
  end

  def handle_execution_failed(event)
    workflow_run = find_workflow_run(event[:data])
    return unless workflow_run

    broadcast_workflow_update(workflow_run, "workflow.execution.failed")
    record_audit_event(workflow_run, "execution_failed", event[:data])
    notify_completion(workflow_run)

    # Trigger webhooks
    trigger_webhook(workflow_run.workflow, "execution.failed", {
      run_id: workflow_run.run_id,
      status: workflow_run.status,
      error: workflow_run.error_details
    })
  end

  def handle_node_completed(event)
    node_execution = find_node_execution(event[:data])
    return unless node_execution

    broadcast_node_update(node_execution, "workflow.node.completed")
  end

  def handle_node_failed(event)
    node_execution = find_node_execution(event[:data])
    return unless node_execution

    broadcast_node_update(node_execution, "workflow.node.failed")
  end

  def find_workflow_run(data)
    workflow_run_id = data[:workflow_run_id] || data["workflow_run_id"]
    run_id = data[:run_id] || data["run_id"]

    Ai::WorkflowRun.find_by(id: workflow_run_id) ||
      Ai::WorkflowRun.find_by(run_id: run_id)
  end

  def find_node_execution(data)
    node_execution_id = data[:node_execution_id] || data["node_execution_id"]
    execution_id = data[:execution_id] || data["execution_id"]

    Ai::WorkflowNodeExecution.find_by(id: node_execution_id) ||
      Ai::WorkflowNodeExecution.find_by(execution_id: execution_id)
  end

  def build_workflow_broadcast_data(workflow_run, additional_data)
    {
      workflow_run: {
        id: workflow_run.id,
        run_id: workflow_run.run_id,
        workflow_id: workflow_run.workflow_id,
        workflow_name: workflow_run.workflow&.name,
        status: workflow_run.status,
        progress_percentage: calculate_progress(workflow_run),
        completed_nodes: workflow_run.completed_nodes || 0,
        failed_nodes: workflow_run.failed_nodes || 0,
        total_nodes: workflow_run.total_nodes || 0,
        started_at: workflow_run.started_at&.iso8601,
        completed_at: workflow_run.completed_at&.iso8601,
        duration_ms: workflow_run.duration_ms,
        cost_usd: workflow_run.total_cost
      }.merge(additional_data)
    }
  end

  def calculate_progress(workflow_run)
    total = workflow_run.total_nodes || 0
    return 0 if total.zero?

    completed = (workflow_run.completed_nodes || 0) + (workflow_run.failed_nodes || 0)
    ((completed.to_f / total) * 100).round
  end

  def calculate_duration(node_execution)
    return nil unless node_execution.started_at

    end_time = node_execution.completed_at || Time.current
    ((end_time - node_execution.started_at) * 1000).round
  end

  def truncate_output(output, max_length = 500)
    return nil if output.blank?

    output_str = output.is_a?(Hash) ? output.to_json : output.to_s
    output_str.length > max_length ? "#{output_str[0...max_length]}..." : output_str
  end
end
