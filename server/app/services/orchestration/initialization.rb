# frozen_string_literal: true

module Orchestration
  module Initialization
    extend ActiveSupport::Concern

    included do
      attr_accessor :account, :user, :workflow
    end

    def build_execution_context
      return {} unless @workflow

      {
        workflow_id: @workflow.id,
        account_id: @account.id,
        user_id: @user&.id,
        created_at: Time.current.iso8601
      }
    end

    def build_node_executors_registry
      {
        "ai_agent" => "AiWorkflowNodeExecutors::AiAgentExecutor",
        "api_call" => "AiWorkflowNodeExecutors::ApiCallExecutor",
        "webhook" => "AiWorkflowNodeExecutors::WebhookExecutor",
        "condition" => "AiWorkflowNodeExecutors::ConditionExecutor",
        "loop" => "AiWorkflowNodeExecutors::LoopExecutor",
        "transform" => "AiWorkflowNodeExecutors::TransformExecutor",
        "delay" => "AiWorkflowNodeExecutors::DelayExecutor",
        "human_approval" => "AiWorkflowNodeExecutors::HumanApprovalExecutor",
        "sub_workflow" => "AiWorkflowNodeExecutors::SubWorkflowExecutor",
        "merge" => "AiWorkflowNodeExecutors::MergeExecutor",
        "split" => "AiWorkflowNodeExecutors::SplitExecutor"
      }
    end

    def build_workflow_execution_context
      {
        workflow_id: @workflow.id,
        account_id: @account.id,
        user_id: @user&.id,
        execution_started_at: Time.current.iso8601,
        orchestration_service: self.class.name
      }
    end

    def execution_context
      @execution_context
    end

    def node_executors
      @node_executors
    end
  end
end
