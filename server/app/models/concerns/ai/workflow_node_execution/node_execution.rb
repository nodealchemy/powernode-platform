# frozen_string_literal: true

module Ai
  class WorkflowNodeExecution
    module NodeExecution
      extend ActiveSupport::Concern

      def execute_node!
        return false unless pending?

        begin
          start_execution!

          case node_type
          when "ai_agent"
            execute_ai_agent_node
          when "api_call"
            execute_api_call_node
          when "webhook"
            execute_webhook_node
          when "condition"
            execute_condition_node
          when "loop"
            execute_loop_node
          when "transform"
            execute_transform_node
          when "delay"
            execute_delay_node
          when "human_approval"
            execute_human_approval_node
          when "sub_workflow"
            execute_sub_workflow_node
          when "merge"
            execute_merge_node
          when "split"
            execute_split_node
          else
            fail_execution!("Unknown node type: #{node_type}")
          end
        rescue StandardError => e
          fail_execution!("Node execution failed: #{e.message}", {
            "exception_class" => e.class.name,
            "exception_backtrace" => e.backtrace&.first(10)
          })
        end
      end

      private

      def execute_ai_agent_node
        agent_id = node_configuration("agent_id")

        if agent_id.blank?
          fail_execution!("No agent specified for AI agent node")
          return
        end

        agent = account.ai_agents.find_by(id: agent_id)
        if agent.nil?
          fail_execution!("AI agent not found: #{agent_id}")
          return
        end

        log_info("ai_agent_execution_queued", "AI agent execution queued", {
          "agent_id" => agent_id,
          "agent_name" => agent.name
        })
      end

      def execute_api_call_node
        url = node_configuration("url")
        method = node_configuration("method") || "GET"

        if url.blank?
          fail_execution!("No URL specified for API call node")
          return
        end

        log_info("api_call_queued", "API call queued: #{method} #{url}")
      end

      def execute_webhook_node
        url = node_configuration("url")

        if url.blank?
          fail_execution!("No URL specified for webhook node")
          return
        end

        log_info("webhook_queued", "Webhook queued: #{url}")
      end

      def execute_condition_node
        conditions = node_configuration("conditions")

        if conditions.blank?
          fail_execution!("No conditions specified for condition node")
          return
        end

        log_info("condition_evaluation_queued", "Condition evaluation queued")
      end

      def execute_loop_node
        iteration_source = node_configuration("iteration_source")

        if iteration_source.blank?
          fail_execution!("No iteration source specified for loop node")
          return
        end

        log_info("loop_execution_queued", "Loop execution queued")
      end

      def execute_transform_node
        transformations = node_configuration("transformations")

        if transformations.blank?
          fail_execution!("No transformations specified for transform node")
          return
        end

        log_info("transform_execution_queued", "Transform execution queued")
      end

      def execute_delay_node
        delay_seconds = node_configuration("delay_seconds")

        if delay_seconds.blank? || delay_seconds.to_i <= 0
          fail_execution!("Invalid delay specified for delay node")
          return
        end

        log_info("delay_scheduled", "Delay scheduled for #{delay_seconds} seconds")
      end

      def execute_human_approval_node
        approval_message = node_configuration("approval_message")
        approvers = node_configuration("approvers") || []

        if approvers.empty?
          fail_execution!("No approvers specified for human approval node")
          return
        end

        request_approval!(approval_message, approvers)
        trigger_approval_notifications(approvers)

        log_info("approval_requested", "Human approval requested", {
          "approvers" => approvers,
          "message" => approval_message
        })
      end

      def execute_sub_workflow_node
        workflow_id = node_configuration("workflow_id")

        if workflow_id.blank?
          fail_execution!("No sub-workflow specified")
          return
        end

        sub_workflow = account.ai_workflows.find_by(id: workflow_id)
        if sub_workflow.nil?
          fail_execution!("Sub-workflow not found: #{workflow_id}")
          return
        end

        log_info("sub_workflow_queued", "Sub-workflow execution queued: #{sub_workflow.name}")
      end

      def execute_merge_node
        merge_strategy = node_configuration("merge_strategy") || "wait_all"

        log_info("merge_execution_queued", "Merge execution queued with strategy: #{merge_strategy}")
      end

      def execute_split_node
        split_strategy = node_configuration("split_strategy") || "parallel"
        branches = node_configuration("branches") || []

        log_info("split_execution_queued", "Split execution queued with strategy: #{split_strategy}")
      end

      def trigger_approval_notifications(approvers)
        return if approvers.empty?

        WorkerJobService.enqueue_job(
          job_class: "AiWorkflow::ApprovalNotificationJob",
          args: [id, approvers],
          queue: "email"
        )
      rescue StandardError => e
        Rails.logger.error("Failed to trigger approval notifications for node execution #{id}: #{e.message}")
        log_warning("approval_notification_failed", "Failed to send approval notifications: #{e.message}")
      end
    end
  end
end
