# frozen_string_literal: true

# AiAgentOrchestrationService - Main facade for AI workflow orchestration
#
# This service acts as the primary public API for AI workflow and agent orchestration,
# delegating actual execution to the MCP (Model Context Protocol) core services while
# providing a stable, high-level interface.
#
# Key responsibilities:
# - Public API facade for workflow execution
# - Agent execution coordination with load balancing
# - Provider selection and optimization
# - Resource limit enforcement
# - Workflow validation and orchestration
# - Real-time execution monitoring and broadcasting
# - Performance metrics and analytics
#
class AiAgentOrchestrationService
  include ActiveModel::Model
  include ActiveModel::Attributes
  include AiNodeExecutors
  include AiOrchestrationBroadcasting

  # Include extracted modules
  include Orchestration::Initialization
  include Orchestration::WorkflowExecution
  include Orchestration::AgentExecution
  include Orchestration::Monitoring
  include Orchestration::LoadBalancing
  include Orchestration::WorkflowControl
  include Orchestration::Statistics
  include Orchestration::NodeOperations

  class OrchestrationError < StandardError; end
  class ExecutionError < StandardError; end
  class ResourceLimitError < StandardError; end

  def initialize(workflow = nil, account: nil, user: nil)
    if workflow
      @workflow = workflow
      @account = workflow.account
      @user = user || workflow.creator
    else
      @account = account
      @user = user
    end
    @logger = Rails.logger
    @execution_context = build_execution_context
    @node_executors = build_node_executors_registry

    # Initialize enhanced services with error handling
    begin
      @load_balancer = AiProviderLoadBalancerService.new(@account, strategy: "cost_optimized") if @account
      @error_recovery = AiErrorRecoveryService.new(@account, @execution_context) if @account
    rescue StandardError => e
      @logger.warn "Failed to initialize enhanced services: #{e.message}"
      @load_balancer = nil
      @error_recovery = nil
    end
  end
end
