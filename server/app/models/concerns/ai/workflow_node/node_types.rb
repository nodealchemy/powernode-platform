# frozen_string_literal: true

module Ai
  class WorkflowNode
    module NodeTypes
      extend ActiveSupport::Concern

      # Node type check methods
      def ai_agent_node?
        node_type == "ai_agent"
      end

      def api_call_node?
        node_type == "api_call"
      end

      def webhook_node?
        node_type == "webhook"
      end

      def condition_node?
        node_type == "condition"
      end

      def loop_node?
        node_type == "loop"
      end

      def transform_node?
        node_type == "transform"
      end

      def delay_node?
        node_type == "delay"
      end

      def human_approval_node?
        node_type == "human_approval"
      end

      def sub_workflow_node?
        node_type == "sub_workflow"
      end

      def merge_node?
        node_type == "merge"
      end

      def split_node?
        node_type == "split"
      end

      def start_node?
        node_type == "start"
      end

      def end_node?
        node_type == "end"
      end

      def trigger_node?
        node_type == "trigger"
      end

      # Consolidated node type check methods
      def kb_article_node?
        node_type == "kb_article"
      end

      def page_node?
        node_type == "page"
      end

      def mcp_operation_node?
        node_type == "mcp_operation"
      end

      # Action/operation type helpers for consolidated nodes
      def kb_article_action
        return nil unless kb_article_node?

        configuration["action"]
      end

      def page_action
        return nil unless page_node?

        configuration["action"]
      end

      def mcp_operation_type
        return nil unless mcp_operation_node?

        configuration["operation_type"]
      end

      # CI/CD node type check methods
      def ci_trigger_node?
        node_type == "ci_trigger"
      end

      def ci_wait_status_node?
        node_type == "ci_wait_status"
      end

      def ci_get_logs_node?
        node_type == "ci_get_logs"
      end

      def ci_cancel_node?
        node_type == "ci_cancel"
      end

      def git_commit_status_node?
        node_type == "git_commit_status"
      end

      def git_create_check_node?
        node_type == "git_create_check"
      end

      # CI/CD helper methods
      def ci_node?
        %w[ci_trigger ci_wait_status ci_get_logs ci_cancel git_commit_status git_create_check].include?(node_type)
      end

      def ci_trigger_action
        return nil unless ci_trigger_node?

        configuration["trigger_action"]
      end

      def git_commit_status_state
        return nil unless git_commit_status_node?

        configuration["state"]
      end
    end
  end
end
