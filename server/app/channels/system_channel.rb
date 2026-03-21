# frozen_string_literal: true

# SystemChannel - Real-time updates for Powernode System infrastructure
#
# Provides WebSocket updates for:
# - Operation status changes (progress, completion, failure)
# - Node status changes
# - Instance status changes
# - System statistics updates
#
# Broadcast events from models/jobs using:
#   SystemChannel.broadcast_operation_update(account, operation)
#   SystemChannel.broadcast_node_update(account, node)
#   SystemChannel.broadcast_stats_update(account)
#
class SystemChannel < ApplicationCable::Channel
  def subscribed
    account_id = params[:account_id]

    if current_user && authorized_for_account?(account_id)
      stream_from stream_name(account_id)
      stream_for_account(current_account)

      Rails.logger.info "User #{current_user.id} subscribed to System updates for account #{account_id}"

      # Send connection confirmation
      transmit({
        type: "connection_established",
        account_id: account_id,
        timestamp: Time.current.iso8601
      })
    else
      Rails.logger.warn "Unauthorized System channel subscription attempt for account #{account_id} by user #{current_user&.id}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from System updates"
  end

  # Client requests a refresh of operations list
  def refresh_operations
    return reject_unauthorized unless current_account

    operations = System::Operation.where(account: current_account)
                                   .order(created_at: :desc)
                                   .limit(50)

    transmit({
      type: "operations_list",
      operations: operations.map { |op| serialize_operation(op) },
      timestamp: Time.current.iso8601
    })
  end

  # Client requests a specific operation's status
  def get_operation(data)
    return reject_unauthorized unless current_account

    operation = System::Operation.find_by(id: data["operation_id"], account: current_account)

    if operation
      transmit({
        type: "operation_status",
        operation: serialize_operation(operation),
        timestamp: Time.current.iso8601
      })
    else
      transmit({
        type: "error",
        message: "Operation not found",
        operation_id: data["operation_id"]
      })
    end
  end

  # Client requests system statistics
  def refresh_stats
    return reject_unauthorized unless current_account

    transmit({
      type: "system_stats",
      stats: build_system_stats,
      timestamp: Time.current.iso8601
    })
  end

  # Ping for connection health check
  def ping
    transmit({ type: "pong", timestamp: Time.current.iso8601 })
  end

  # Class methods for broadcasting updates from models/jobs
  class << self
    def broadcast_operation_update(account, operation)
      ActionCable.server.broadcast(
        stream_name_for(account.id),
        {
          type: "operation_updated",
          operation: serialize_operation_static(operation),
          timestamp: Time.current.iso8601
        }
      )
    end

    def broadcast_operation_progress(account, operation)
      ActionCable.server.broadcast(
        stream_name_for(account.id),
        {
          type: "operation_progress",
          operation_id: operation.id,
          status: operation.status,
          progress: operation.progress,
          description: operation.description,
          timestamp: Time.current.iso8601
        }
      )
    end

    def broadcast_node_update(account, node)
      ActionCable.server.broadcast(
        stream_name_for(account.id),
        {
          type: "node_updated",
          node: serialize_node_static(node),
          timestamp: Time.current.iso8601
        }
      )
    end

    def broadcast_instance_update(account, instance)
      ActionCable.server.broadcast(
        stream_name_for(account.id),
        {
          type: "instance_updated",
          instance: serialize_instance_static(instance),
          timestamp: Time.current.iso8601
        }
      )
    end

    def broadcast_stats_update(account)
      ActionCable.server.broadcast(
        stream_name_for(account.id),
        {
          type: "stats_updated",
          timestamp: Time.current.iso8601
        }
      )
    end

    def stream_name_for(account_id)
      "system_channel_#{account_id}"
    end

    private

    def serialize_operation_static(operation)
      {
        id: operation.id,
        command: operation.command,
        status: operation.status,
        progress: operation.progress,
        description: operation.description,
        error_message: operation.error_message,
        scheduled_at: operation.scheduled_at&.iso8601,
        started_at: operation.started_at&.iso8601,
        completed_at: operation.completed_at&.iso8601,
        operable_type: operation.operable_type,
        operable_id: operation.operable_id,
        created_at: operation.created_at.iso8601,
        updated_at: operation.updated_at.iso8601
      }
    end

    def serialize_node_static(node)
      {
        id: node.id,
        name: node.name,
        enabled: node.enabled,
        public_address: node.public_address,
        instances_count: node.node_instances.count,
        created_at: node.created_at.iso8601,
        updated_at: node.updated_at.iso8601
      }
    end

    def serialize_instance_static(instance)
      {
        id: instance.id,
        name: instance.name,
        status: instance.status,
        variety: instance.variety,
        private_ip_address: instance.private_ip_address,
        public_ip_address: instance.public_ip_address,
        node_id: instance.node_id,
        created_at: instance.created_at.iso8601,
        updated_at: instance.updated_at.iso8601
      }
    end
  end

  private

  def stream_name(account_id)
    self.class.stream_name_for(account_id)
  end

  def reject_unauthorized
    transmit({ type: "error", message: "Unauthorized" })
  end

  def serialize_operation(operation)
    self.class.send(:serialize_operation_static, operation)
  end

  def build_system_stats
    return {} unless current_account

    {
      nodes: {
        total: System::Node.where(account: current_account).count,
        enabled: System::Node.where(account: current_account, enabled: true).count
      },
      instances: {
        total: System::NodeInstance.joins(:node).where(system_nodes: { account_id: current_account.id }).count,
        running: System::NodeInstance.joins(:node).where(system_nodes: { account_id: current_account.id }, status: "running").count,
        stopped: System::NodeInstance.joins(:node).where(system_nodes: { account_id: current_account.id }, status: "stopped").count
      },
      operations: {
        total: System::Operation.where(account: current_account).count,
        pending: System::Operation.where(account: current_account, status: "pending").count,
        running: System::Operation.where(account: current_account, status: "running").count
      }
    }
  end
end
