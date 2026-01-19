# frozen_string_literal: true

module Ai
  class WorkflowNodeExecution
    module Broadcasting
      extend ActiveSupport::Concern

      included do
        before_save :capture_pending_status_change
        after_commit :check_workflow_failure_on_node_failure, on: [ :update ]
        after_commit :broadcast_node_status_change_if_needed, on: [ :update ]
        after_commit :clear_pending_status_change, on: [ :update ]
        after_commit :broadcast_node_creation, on: [ :create ]
      end

      def capture_pending_status_change
        if status_changed?
          @pending_status_change = [status_was, status]
          Rails.logger.debug "[NodeExecution] Captured pending status change: #{status_was} -> #{status}"
        end
      end

      def force_status_broadcast!
        Rails.logger.info "Force broadcasting status for node: #{node.name} (#{status})"
        broadcast_node_status_change
      end

      def broadcast_node_creation
        Rails.logger.info "[NodeExecution] Broadcasting node creation: #{execution_id} -> #{status} (#{node.name})"
        broadcast_node_status_change
      end

      private

      def broadcast_node_status_change
        Rails.logger.info "[NodeExecution] Broadcasting node status change: #{execution_id} -> #{status} (#{node.name})"

        begin
          if defined?(AiOrchestrationChannel)
            AiOrchestrationChannel.broadcast_node_execution(self)
          else
            Rails.logger.warn "[NodeExecution] AiOrchestrationChannel not available, skipping WebSocket broadcast"
          end
        rescue NameError => e
          Rails.logger.error "[NodeExecution] WebSocket broadcast failed (channel not loaded): #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
        rescue StandardError => e
          Rails.logger.error "[NodeExecution] WebSocket broadcast failed: #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
        end
      end

      def broadcast_node_status_change_if_needed
        Rails.logger.debug "[NodeExecution] broadcast_node_status_change_if_needed called, @pending_status_change=#{@pending_status_change.inspect}"

        if @pending_status_change
          old_status, new_status = @pending_status_change

          broadcast_transitions = [
            [ "running", "completed" ],
            [ "running", "failed" ],
            [ "running", "cancelled" ],
            [ "pending", "running" ],
            [ "waiting_approval", "running" ]
          ]

          should_broadcast = broadcast_transitions.include?([ old_status, new_status ])

          Rails.logger.info "[NodeExecution] Status transition: #{old_status} -> #{new_status}, should_broadcast=#{should_broadcast}"

          if should_broadcast
            broadcast_node_status_change
          else
            Rails.logger.debug "[NodeExecution] Skipping broadcast - transition not in broadcast list"
          end
        else
          Rails.logger.debug "[NodeExecution] No @pending_status_change set"
        end
      end

      def clear_pending_status_change
        @pending_status_change = nil
      end

      def check_workflow_failure_on_node_failure
        if @pending_status_change
          old_status, new_status = @pending_status_change

          if new_status == "failed" && old_status != "failed"
            begin
              workflow_run.log(
                "error",
                "node_execution_failed",
                "Node #{node.name} failed",
                {
                  "node_id" => node_id,
                  "execution_id" => execution_id,
                  "error_details" => error_details
                },
                self
              )
            rescue StandardError => e
              Rails.logger.error "Failed to log node failure: #{e.message}"
            end
          end
        end
      end
    end
  end
end
