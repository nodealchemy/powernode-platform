# frozen_string_literal: true

module Api
  module V1
    module System
      module NodeApi
        # Status reporting endpoint for node instances
        # Allows instances to report their status and receive commands
        class StatusController < BaseController
          # GET /api/v1/system/node_api/status
          # Get current instance status
          def show
            render_success(
              instance: serialize_instance_status,
              node: serialize_node_status,
              pending_operations: pending_operations_count
            )
          end

          # POST /api/v1/system/node_api/status/report
          # Report instance status update
          def report
            status = params[:status]
            metrics = params[:metrics] || {}

            # Validate status
            unless ::System::NodeInstance::STATUSES.include?(status)
              return render_error("Invalid status: #{status}")
            end

            # Update instance status
            current_instance.update!(
              status: status,
              config: current_instance.config.merge(
                "last_report" => Time.current.iso8601,
                "metrics" => metrics
              )
            )

            # Check for pending operations
            pending = pending_operations

            render_success(
              status_updated: true,
              current_status: current_instance.status,
              pending_operations: pending.map { |o| serialize_operation(o) }
            )
          end

          # POST /api/v1/system/node_api/status/heartbeat
          # Simple heartbeat endpoint
          def heartbeat
            current_instance.update!(
              config: current_instance.config.merge(
                "last_heartbeat" => Time.current.iso8601
              )
            )

            render_success(
              acknowledged: true,
              server_time: Time.current.iso8601
            )
          end

          # GET /api/v1/system/node_api/status/operations
          # Get pending operations for this instance
          def operations
            operations = pending_operations.order(created_at: :asc)

            render_success(
              operations: operations.map { |o| serialize_operation_full(o) },
              count: operations.size
            )
          end

          # POST /api/v1/system/node_api/status/operations/:id/ack
          # Acknowledge operation receipt
          def acknowledge_operation
            operation = current_instance.operations.find(params[:id])

            if operation.pending?
              operation.update!(
                status: "acknowledged",
                events: (operation.events || []) << {
                  type: "acknowledged",
                  message: "Acknowledged by instance",
                  timestamp: Time.current.iso8601
                }
              )
            end

            render_success(
              operation: serialize_operation(operation),
              acknowledged: true
            )
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Operation")
          end

          # POST /api/v1/system/node_api/status/operations/:id/complete
          # Report operation completion
          def complete_operation
            operation = current_instance.operations.find(params[:id])

            unless operation.running? || operation.status == "acknowledged"
              return render_error("Operation cannot be completed from #{operation.status} state")
            end

            result = params[:result] || {}
            message = params[:message] || "Completed by instance"

            operation.update!(
              status: "complete",
              progress: 100,
              completed_at: Time.current,
              result: result,
              events: (operation.events || []) << {
                type: "completed",
                message: message,
                timestamp: Time.current.iso8601
              }
            )

            render_success(
              operation: serialize_operation(operation),
              completed: true
            )
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Operation")
          end

          # POST /api/v1/system/node_api/status/operations/:id/fail
          # Report operation failure
          def fail_operation
            operation = current_instance.operations.find(params[:id])

            unless operation.pending? || operation.running? || operation.status == "acknowledged"
              return render_error("Operation cannot be marked as failed from #{operation.status} state")
            end

            error_message = params[:error_message] || "Failed by instance"

            operation.update!(
              status: "failed",
              completed_at: Time.current,
              error_message: error_message,
              events: (operation.events || []) << {
                type: "failed",
                message: error_message,
                timestamp: Time.current.iso8601
              }
            )

            render_success(
              operation: serialize_operation(operation),
              failed: true
            )
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Operation")
          end

          private

          def serialize_instance_status
            {
              id: current_instance.id,
              name: current_instance.name,
              status: current_instance.status,
              variety: current_instance.variety,
              last_heartbeat: current_instance.config&.dig("last_heartbeat"),
              last_report: current_instance.config&.dig("last_report"),
              metrics: current_instance.config&.dig("metrics")
            }
          end

          def serialize_node_status
            {
              id: current_node.id,
              name: current_node.name,
              worker_assigned: current_node.worker_id.present?
            }
          end

          def pending_operations
            current_instance.operations.where(status: %w[pending acknowledged running])
          end

          def pending_operations_count
            pending_operations.count
          end

          def serialize_operation(operation)
            {
              id: operation.id,
              command: operation.command,
              status: operation.status,
              progress: operation.progress,
              created_at: operation.created_at
            }
          end

          def serialize_operation_full(operation)
            serialize_operation(operation).merge(
              options: operation.options,
              started_at: operation.started_at,
              events: operation.events || []
            )
          end
        end
      end
    end
  end
end
