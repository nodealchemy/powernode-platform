# frozen_string_literal: true

# AI Orchestration Test Helpers
#
# Provides shared test helpers and contexts for AI orchestration service testing.
# This module standardizes the setup of accounts, users, providers, workflows,
# and other AI orchestration models to ensure consistent test data across specs.
#
# Usage:
#   RSpec.describe SomeService do
#     include AiOrchestrationTestHelpers
#
#     it 'does something' do
#       setup_ai_orchestration_environment
#       # test implementation
#     end
#   end
#
module AiOrchestrationTestHelpers
  # Sets up a complete AI orchestration test environment with all required models
  #
  # Creates:
  # - Account
  # - User (creator)
  # - AI Provider with active credential
  # - AI Workflow with simple chain structure
  # - Workflow Run in initializing state
  #
  # @return [Hash] Hash containing all created models
  def setup_ai_orchestration_environment
    account = create(:account)
    user = create(:user, account: account)
    provider = create(:ai_provider, account: account, slug: 'test-provider')
    credential = create(:ai_provider_credential, provider: provider, is_active: true)
    workflow = create(:ai_workflow, :with_simple_chain, account: account, creator: user)
    workflow_run = create(:ai_workflow_run, workflow: workflow, account: account)

    {
      account: account,
      user: user,
      provider: provider,
      credential: credential,
      workflow: workflow,
      workflow_run: workflow_run
    }
  end

  # Creates a minimal AI orchestration environment without workflow run
  #
  # @return [Hash] Hash containing account, user, provider, credential, workflow
  def setup_minimal_ai_environment
    account = create(:account)
    user = create(:user, account: account)
    provider = create(:ai_provider, account: account, slug: 'test-provider')
    credential = create(:ai_provider_credential, provider: provider, is_active: true)
    workflow = create(:ai_workflow, account: account, creator: user)

    {
      account: account,
      user: user,
      provider: provider,
      credential: credential,
      workflow: workflow
    }
  end

  # Creates an AI provider with active credentials
  #
  # @param account [Account] The account to associate the provider with
  # @param slug [String] Optional slug for the provider (default: 'test-provider')
  # @return [Ai::Provider] The created provider with active credential
  def create_ai_provider_with_credentials(account, slug: 'test-provider')
    provider = create(:ai_provider, account: account, slug: slug)
    create(:ai_provider_credential, provider: provider, is_active: true)
    provider
  end

  # Creates multiple AI providers for testing fallback/switching scenarios
  #
  # @param account [Account] The account to associate providers with
  # @param count [Integer] Number of providers to create (default: 3)
  # @return [Array<Ai::Provider>] Array of created providers with credentials
  def create_multiple_providers(account, count: 3)
    count.times.map do |i|
      provider = create(:ai_provider, account: account, slug: "provider-#{i}")
      create(:ai_provider_credential, provider: provider, is_active: true)
      provider
    end
  end

  # Creates a workflow with specified execution mode and structure
  #
  # @param account [Account] The account to associate the workflow with
  # @param creator [User] The user creating the workflow
  # @param mode [Symbol] Execution mode (:sequential, :parallel, :conditional)
  # @param structure [Symbol] Workflow structure (:simple_chain, :complex_flow, :with_loop)
  # @return [AiWorkflow] The created workflow
  def create_workflow_with_structure(account, creator, mode: :sequential, structure: :simple_chain)
    trait = structure == :simple_chain ? :with_simple_chain : structure
    config_trait = mode == :parallel ? :parallel_execution : nil

    if config_trait
      create(:ai_workflow, trait, config_trait, account: account, creator: creator)
    else
      create(:ai_workflow, trait, account: account, creator: creator)
    end
  end

  # Creates a workflow run with specific status and execution context
  #
  # @param workflow [AiWorkflow] The workflow to create a run for
  # @param status [String] Run status ('initializing', 'running', 'completed', 'failed')
  # @param input [Hash] Input variables for the run
  # @return [AiWorkflowRun] The created workflow run
  def create_workflow_run_with_status(workflow, status: 'initializing', input: {})
    trait = case status
    when 'running' then :running
    when 'completed' then :completed
    when 'failed' then :failed
    else nil
    end

    if trait
      create(:ai_workflow_run, trait, workflow: workflow, account: workflow.account)
    else
      create(:ai_workflow_run, workflow: workflow, account: workflow.account, input_variables: input)
    end
  end

  # Stub Redis connection for tests that require Redis mocking
  #
  # @return [Double] Redis mock instance
  def stub_redis_connection
    redis_mock = instance_double(Redis)
    allow(Redis).to receive(:new).and_return(redis_mock)
    allow(redis_mock).to receive(:hgetall).and_return({})
    allow(redis_mock).to receive(:hget).and_return(nil)
    allow(redis_mock).to receive(:hset)
    allow(redis_mock).to receive(:hincrby)
    allow(redis_mock).to receive(:expire)
    allow(redis_mock).to receive(:del)
    redis_mock
  end

  # Stub circuit breaker service for provider availability testing
  #
  # @param provider [Ai::Provider] The provider to stub circuit breaker for
  # @param available [Boolean] Whether provider should be available (default: true)
  # @return [Double] Monitoring::CircuitBreaker mock instance
  def stub_circuit_breaker(provider, available: true)
    circuit_breaker = instance_double(Ai::ProviderCircuitBreakerService)
    allow(Ai::ProviderCircuitBreakerService).to receive(:new).with(provider).and_return(circuit_breaker)
    allow(circuit_breaker).to receive(:provider_available?).and_return(available)
    allow(circuit_breaker).to receive(:call).and_yield if available
    allow(circuit_breaker).to receive(:circuit_state).and_return(available ? :closed : :open)
    circuit_breaker
  end

  # Stub load balancer service for provider selection testing
  #
  # @param account [Account] The account to stub load balancer for
  # @param providers [Array<Ai::Provider>] Available providers
  # @return [Double] LoadBalancer mock instance
  def stub_load_balancer(account, providers: [])
    load_balancer = instance_double(Ai::ProviderLoadBalancerService)
    allow(Ai::ProviderLoadBalancerService).to receive(:new).with(account).and_return(load_balancer)
    allow(load_balancer).to receive(:send).with(:get_available_providers).and_return(providers)

    providers.each do |provider|
      allow(load_balancer).to receive(:send).with(:get_provider_avg_response_time, provider).and_return(250.0)
      allow(load_balancer).to receive(:send).with(:get_provider_success_rate, provider).and_return(95.0)
    end

    load_balancer
  end

  # Stub MCP protocol services for workflow orchestration testing
  #
  # @return [Hash] Hash of MCP service mocks
  def stub_mcp_services
    protocol = instance_double('Mcp::ProtocolService')
    registry = instance_double('Mcp::RegistryService')
    state_machine = instance_double('Mcp::WorkflowStateMachine')
    event_store = instance_double('Mcp::ExecutionEventStore')
    tracer = instance_double('Mcp::ExecutionTracer')
    monitor = instance_double('Mcp::RealtimeMonitor')

    allow(protocol).to receive(:initialize_session)
    allow(protocol).to receive(:send_message)
    allow(protocol).to receive(:close_session)

    allow(registry).to receive(:validate_agent)
    allow(registry).to receive(:get_agent_capabilities)

    allow(state_machine).to receive(:transition!)
    allow(state_machine).to receive(:can_transition?).and_return(true)
    allow(state_machine).to receive(:current_state).and_return(:initializing)

    allow(event_store).to receive(:record_event)
    allow(event_store).to receive(:get_execution_history).and_return([])

    allow(tracer).to receive(:start_span)
    allow(tracer).to receive(:end_span)
    allow(tracer).to receive(:record_metric)

    allow(monitor).to receive(:start_monitoring)
    allow(monitor).to receive(:update_progress)
    allow(monitor).to receive(:broadcast_event)
    allow(monitor).to receive(:finalize)

    {
      protocol: protocol,
      registry: registry,
      state_machine: state_machine,
      event_store: event_store,
      tracer: tracer,
      monitor: monitor
    }
  end

  # Creates a mock successful execution result
  #
  # @param output [Hash] Output data from execution
  # @return [Hash] Standardized success result
  def mock_success_result(output = { result: 'success' })
    {
      success: true,
      output: output,
      execution_time: 150.5,
      tokens_used: 500,
      cost: 0.005
    }
  end

  # Creates a mock failed execution result
  #
  # @param error_message [String] Error message
  # @param error_type [Symbol] Type of error
  # @return [Hash] Standardized error result
  def mock_error_result(error_message = 'Test error', error_type = :server_error)
    {
      success: false,
      error: error_message,
      error_type: error_type,
      execution_time: 50.0,
      tokens_used: 0,
      cost: 0.0
    }
  end

  # Stub ActionCable broadcasting for real-time update testing
  def stub_action_cable_broadcasting
    allow(ActionCable.server).to receive(:broadcast)
  end

  # Stub Sidekiq job enqueueing for async task testing
  def stub_sidekiq_jobs
    allow_any_instance_of(Class).to receive(:perform_async)
    allow_any_instance_of(Class).to receive(:perform_in)
  end

  # Create node execution record for testing
  #
  # @param workflow_run [Ai::WorkflowRun] The workflow run
  # @param node [Ai::WorkflowNode] The node being executed
  # @param status [String] Execution status
  # @return [Ai::WorkflowNodeExecution] The created node execution
  def create_node_execution(workflow_run, node, status: 'pending')
    trait = case status
    when 'running' then :running
    when 'completed' then :completed
    when 'failed' then :failed
    else nil
    end

    attrs = {
      workflow_run: workflow_run,
      node: node,
      node_id: node.node_id,
      node_type: node.node_type
    }

    if trait
      create(:ai_workflow_node_execution, trait, **attrs)
    else
      create(:ai_workflow_node_execution, **attrs, status: status)
    end
  end

  # Assert that a workflow run has expected status
  #
  # @param workflow_run [AiWorkflowRun] The workflow run to check
  # @param expected_status [String] Expected status value
  def expect_workflow_status(workflow_run, expected_status)
    workflow_run.reload
    expect(workflow_run.status).to eq(expected_status)
  end

  # Assert that an event was broadcast to ActionCable
  #
  # @param channel_name [String] The channel name
  # @param event_type [String] The event type
  def expect_broadcast(channel_name, event_type: nil)
    if event_type
      expect(ActionCable.server).to have_received(:broadcast).with(
        channel_name,
        hash_including(event: event_type)
      )
    else
      expect(ActionCable.server).to have_received(:broadcast).with(channel_name, anything)
    end
  end
end

# Shared RSpec configuration
RSpec.configure do |config|
  config.include AiOrchestrationTestHelpers, type: :service

  # Stub AI Workflow Execution Channel globally for tests
  config.before(:each, type: :service) do
    channel_stub = class_double('AiWorkflowExecutionChannel')
    allow(channel_stub).to receive(:broadcast_run_status)
    allow(channel_stub).to receive(:broadcast_node_status)
    allow(channel_stub).to receive(:broadcast_node_update)
    allow(channel_stub).to receive(:broadcast_error)
    allow(channel_stub).to receive(:broadcast_to)
    stub_const('AiWorkflowExecutionChannel', channel_stub)
  end
end
