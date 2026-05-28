# frozen_string_literal: true

# AI Orchestration Test Helpers
#
# Provides shared test helpers and contexts for AI orchestration service testing.
# This module standardizes the setup of accounts, users, providers, and other
# AI orchestration models to ensure consistent test data across specs.
#
# Usage:
#   RSpec.describe SomeService do
#     include AiOrchestrationTestHelpers
#
#     it 'does something' do
#       setup_minimal_ai_environment
#       # test implementation
#     end
#   end
#
module AiOrchestrationTestHelpers
  # Creates a minimal AI orchestration environment
  #
  # @return [Hash] Hash containing account, user, provider, credential
  def setup_minimal_ai_environment
    account = create(:account)
    user = create(:user, account: account)
    provider = create(:ai_provider, account: account, slug: 'test-provider')
    credential = create(:ai_provider_credential, provider: provider, is_active: true)

    {
      account: account,
      user: user,
      provider: provider,
      credential: credential
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
    event_store = instance_double('Mcp::ExecutionEventStore')
    tracer = instance_double('Mcp::ExecutionTracer')

    allow(protocol).to receive(:initialize_session)
    allow(protocol).to receive(:send_message)
    allow(protocol).to receive(:close_session)

    allow(registry).to receive(:validate_agent)
    allow(registry).to receive(:get_agent_capabilities)

    allow(event_store).to receive(:record_event)
    allow(event_store).to receive(:get_execution_history).and_return([])

    allow(tracer).to receive(:start_span)
    allow(tracer).to receive(:end_span)
    allow(tracer).to receive(:record_metric)

    {
      protocol: protocol,
      registry: registry,
      event_store: event_store,
      tracer: tracer
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

  # Assert that a run record has expected status
  #
  # @param workflow_run The run record to check
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
end
