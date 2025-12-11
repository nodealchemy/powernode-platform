# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

RSpec.describe 'AI Orchestration Performance Tests', type: :performance do
  include AiOrchestrationHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [
    'ai.monitor', 'ai.agents.read', 'ai.workflows.read', 'ai.workflows.execute'
  ]) }
  let(:ai_provider) { create(:ai_provider, account: account, provider_type: 'openai', is_active: true) }
  let(:ai_agent) { create(:ai_agent, account: account, ai_provider: ai_provider) }

  before do
    mock_action_cable_broadcasting
    mock_ai_provider_responses
    setup_performance_monitoring
  end

  describe 'workflow execution performance' do
    context 'single workflow execution' do
      let(:simple_workflow) { create_simple_workflow(account) }

      it 'executes simple workflow within acceptable time limits' do
        execution_time = Benchmark.realtime do
          orchestration_service = AiAgentOrchestrationService.new(account: account)
          workflow_run = create(:ai_workflow_run, ai_workflow: simple_workflow, status: 'initializing')

          orchestration_service.orchestrate_workflow(workflow_run)
        end

        expect(execution_time).to be < 5.0 # Should complete within 5 seconds
        expect(Rails.logger).to have_received(:info).with(/Workflow execution completed/)
      end

      it 'handles complex workflow with multiple nodes efficiently' do
        complex_workflow = create_complex_workflow(account, node_count: 10)

        execution_time = Benchmark.realtime do
          orchestration_service = AiAgentOrchestrationService.new(account: account)
          workflow_run = create(:ai_workflow_run, ai_workflow: complex_workflow, status: 'initializing')

          orchestration_service.orchestrate_workflow(workflow_run)
        end

        expect(execution_time).to be < 15.0 # Complex workflow should complete within 15 seconds
        expect(complex_workflow.ai_workflow_nodes.count).to eq(10)
      end
    end

    context 'concurrent workflow executions' do
      it 'handles multiple concurrent workflows without performance degradation' do
        workflows = 5.times.map { create_simple_workflow(account) }
        workflow_runs = workflows.map { |w| create(:ai_workflow_run, ai_workflow: w, status: 'initializing') }

        execution_times = []
        threads = []

        workflow_runs.each do |run|
          threads << Thread.new do
            execution_time = Benchmark.realtime do
              orchestration_service = AiAgentOrchestrationService.new(account: account)
              orchestration_service.orchestrate_workflow(run)
            end
            execution_times << execution_time
          end
        end

        threads.each(&:join)

        # All executions should complete within reasonable time
        expect(execution_times.max).to be < 8.0
        expect(execution_times.length).to eq(5)

        # Average execution time should not significantly increase
        expect(execution_times.sum / execution_times.length).to be < 6.0
      end

      it 'maintains consistent performance under high concurrency' do
        workflows = 20.times.map { create_simple_workflow(account) }
        workflow_runs = workflows.map { |w| create(:ai_workflow_run, ai_workflow: w, status: 'initializing') }

        start_time = Time.current
        execution_results = []

        # Process workflows in batches to simulate real load
        workflow_runs.each_slice(5) do |batch|
          batch_threads = batch.map do |run|
            Thread.new do
              begin
                orchestration_service = AiAgentOrchestrationService.new(account: account)
                result = orchestration_service.orchestrate_workflow(run)
                execution_results << { success: true, workflow_id: run.ai_workflow.id }
              rescue => e
                execution_results << { success: false, error: e.message }
              end
            end
          end
          batch_threads.each(&:join)
        end

        total_time = Time.current - start_time

        # All workflows should complete successfully
        successful_executions = execution_results.count { |r| r[:success] }
        expect(successful_executions).to eq(20)

        # Total time should scale reasonably
        expect(total_time).to be < 30.0 # 20 workflows in under 30 seconds

        # No failures should occur
        failed_executions = execution_results.count { |r| !r[:success] }
        expect(failed_executions).to eq(0)
      end
    end
  end

  describe 'provider selection performance' do
    it 'efficiently selects optimal provider from multiple options' do
      # Create multiple providers with different characteristics
      providers = [
        create(:ai_provider, account: account, provider_type: 'openai', is_active: true),
        create(:ai_provider, account: account, provider_type: 'anthropic', is_active: true),
        create(:ai_provider, account: account, provider_type: 'google', is_active: true),
        create(:ai_provider, account: account, provider_type: 'cohere', is_active: true)
      ]

      # Simulate different performance metrics for each provider
      providers.each_with_index do |provider, index|
        simulate_provider_metrics(provider, {
          average_response_time: 100 + (index * 50),
          success_rate: 0.95 - (index * 0.02),
          current_load: index * 25,
          cost_per_token: 0.001 + (index * 0.0005)
        })
      end

      selection_time = Benchmark.realtime do
        1000.times do
          orchestration_service = AiAgentOrchestrationService.new(account: account)
          selected_provider = orchestration_service.send(:select_optimal_provider, providers, {})
          expect(selected_provider).to be_present
        end
      end

      # 1000 provider selections should complete very quickly
      expect(selection_time).to be < 1.0
    end

    it 'handles provider failover without significant delay' do
      primary_provider = create(:ai_provider, account: account, is_active: true)
      fallback_provider = create(:ai_provider, account: account, is_active: true)

      # Mock primary provider failure
      allow_any_instance_of(AiProviderClientService).to receive(:execute_request)
        .with(primary_provider, anything)
        .and_raise(StandardError, 'Provider timeout')

      # Mock successful fallback
      allow_any_instance_of(AiProviderClientService).to receive(:execute_request)
        .with(fallback_provider, anything)
        .and_return(mock_ai_provider_response)

      workflow = create_simple_workflow(account)
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing')

      failover_time = Benchmark.realtime do
        orchestration_service = AiAgentOrchestrationService.new(account: account)
        orchestration_service.orchestrate_workflow(workflow_run)
      end

      # Failover should add minimal overhead
      expect(failover_time).to be < 6.0
      expect(workflow_run.reload.status).to eq('completed')
    end
  end

  describe 'memory usage and garbage collection' do
    it 'maintains reasonable memory usage during long-running orchestrations' do
      initial_memory = get_memory_usage

      # Execute many workflows to test memory management
      50.times do |i|
        workflow = create_simple_workflow(account)
        workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing')

        orchestration_service = AiAgentOrchestrationService.new(account: account)
        orchestration_service.orchestrate_workflow(workflow_run)

        # Force garbage collection every 10 iterations
        GC.start if i % 10 == 0
      end

      final_memory = get_memory_usage
      memory_increase = final_memory - initial_memory

      # Memory increase should be reasonable (less than 50MB)
      expect(memory_increase).to be < 50.0
    end

    it 'properly cleans up resources after workflow completion' do
      workflow = create_complex_workflow(account, node_count: 15)
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing')

      initial_objects = ObjectSpace.count_objects

      orchestration_service = AiAgentOrchestrationService.new(account: account)
      orchestration_service.orchestrate_workflow(workflow_run)

      # Force garbage collection
      GC.start

      final_objects = ObjectSpace.count_objects

      # Object count should not increase significantly
      object_increase = final_objects[:TOTAL] - initial_objects[:TOTAL]
      expect(object_increase).to be < 10000
    end
  end

  describe 'database query performance' do
    it 'executes workflow queries efficiently' do
      workflow = create_complex_workflow(account, node_count: 20)
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing')

      query_count = 0
      original_method = ActiveRecord::Base.connection.method(:execute)

      allow(ActiveRecord::Base.connection).to receive(:execute) do |*args|
        query_count += 1
        original_method.call(*args)
      end

      orchestration_service = AiAgentOrchestrationService.new(account: account)
      orchestration_service.orchestrate_workflow(workflow_run)

      # Should not generate excessive database queries
      expect(query_count).to be < 100 # Reasonable limit for complex workflow
    end

    it 'uses efficient eager loading for related data' do
      workflows = 10.times.map { create_complex_workflow(account, node_count: 5) }

      query_time = Benchmark.realtime do
        AiWorkflow.includes(:ai_workflow_nodes, :ai_workflow_edges)
                  .where(account: account)
                  .find_each do |workflow|
          # Access related data (should be loaded via includes)
          workflow.ai_workflow_nodes.each(&:configuration)
          workflow.ai_workflow_edges.each(&:condition)
        end
      end

      # Eager loading should make this very fast
      expect(query_time).to be < 0.5
    end
  end

  describe 'WebSocket broadcasting performance' do
    it 'broadcasts updates efficiently to multiple subscribers' do
      # Simulate multiple subscribers
      subscriber_count = 100
      broadcast_count = 50

      broadcasting_time = Benchmark.realtime do
        broadcast_count.times do |i|
          ActionCable.server.broadcast(
            "ai_orchestration_#{account.id}",
            {
              type: 'workflow_update',
              workflow_id: "workflow-#{i}",
              status: 'running',
              timestamp: Time.current.iso8601
            }
          )
        end
      end

      # Broadcasting should be very fast
      expect(broadcasting_time).to be < 1.0

      # Verify all broadcasts were sent
      expect(ActionCable.server).to have_received(:broadcast).exactly(50).times
    end

    it 'handles high-frequency real-time updates without bottlenecks' do
      workflow_run_id = 'test-run-123'
      update_count = 200

      rapid_update_time = Benchmark.realtime do
        update_count.times do |i|
          ActionCable.server.broadcast(
            "ai_workflow_execution_#{workflow_run_id}",
            {
              type: 'node_progress',
              node_id: "node-#{i % 10}",
              progress: (i * 100.0 / update_count).round(2),
              timestamp: Time.current.iso8601
            }
          )
        end
      end

      # High-frequency updates should complete quickly
      expect(rapid_update_time).to be < 2.0
    end
  end

  describe 'load balancing performance' do
    it 'distributes load evenly across multiple providers' do
      providers = 4.times.map do |i|
        create(:ai_provider, account: account, is_active: true, provider_type: "provider_#{i}")
      end

      # Simulate equal provider capabilities
      providers.each do |provider|
        simulate_provider_metrics(provider, {
          average_response_time: 150,
          success_rate: 0.98,
          current_load: 0,
          cost_per_token: 0.001
        })
      end

      selected_providers = []
      selection_time = Benchmark.realtime do
        100.times do
          orchestration_service = AiAgentOrchestrationService.new(account: account)
          selected = orchestration_service.send(:select_optimal_provider, providers, {})
          selected_providers << selected.id
        end
      end

      # Load balancing should be fast
      expect(selection_time).to be < 0.5

      # Verify relatively even distribution
      provider_counts = selected_providers.group_by(&:itself).transform_values(&:count)
      expect(provider_counts.values.max - provider_counts.values.min).to be <= 15
    end
  end

  describe 'error handling performance' do
    it 'recovers from errors quickly without cascading delays' do
      workflow = create_simple_workflow(account)
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing')

      # Mock random failures
      failure_count = 0
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text) do
        failure_count += 1
        if failure_count <= 3
          raise StandardError, 'Simulated failure'
        else
          mock_ai_provider_response
        end
      end

      recovery_time = Benchmark.realtime do
        orchestration_service = AiAgentOrchestrationService.new(account: account)
        orchestration_service.orchestrate_workflow(workflow_run)
      end

      # Should recover and complete within reasonable time
      expect(recovery_time).to be < 8.0
      expect(workflow_run.reload.status).to eq('completed')
    end
  end

  private

  def create_simple_workflow(account)
    workflow = create(:ai_workflow, account: account, name: 'Simple Performance Test')

    start_node = create(:ai_workflow_node,
      ai_workflow: workflow,
      node_id: 'start-1',
      node_type: 'start',
      configuration: { label: 'Start' }
    )

    agent_node = create(:ai_workflow_node,
      ai_workflow: workflow,
      node_id: 'agent-1',
      node_type: 'ai_agent',
      configuration: { agent_id: ai_agent.id, label: 'AI Agent' }
    )

    create(:ai_workflow_edge,
      ai_workflow: workflow,
      source_node_id: start_node.node_id,
      target_node_id: agent_node.node_id
    )

    workflow
  end

  def create_complex_workflow(account, node_count: 10)
    workflow = create(:ai_workflow, account: account, name: 'Complex Performance Test')

    nodes = []

    # Create start node
    start_node = create(:ai_workflow_node,
      ai_workflow: workflow,
      node_id: 'start-1',
      node_type: 'start',
      configuration: { label: 'Start' }
    )
    nodes << start_node

    # Create processing nodes
    (node_count - 1).times do |i|
      node = create(:ai_workflow_node,
        ai_workflow: workflow,
        node_id: "node-#{i + 1}",
        node_type: %w[ai_agent condition transform webhook].sample,
        configuration: {
          label: "Node #{i + 1}",
          agent_id: ai_agent.id,
          condition: 'result.success == true',
          transformation: 'result.processed = true'
        }
      )
      nodes << node
    end

    # Create edges to form a chain
    nodes.each_cons(2) do |source, target|
      create(:ai_workflow_edge,
        ai_workflow: workflow,
        source_node_id: source.node_id,
        target_node_id: target.node_id
      )
    end

    workflow
  end

  def setup_performance_monitoring
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  def mock_ai_provider_responses
    allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
      .and_return(mock_ai_provider_response(
        content: 'Performance test response',
        processing_time: 100
      ))
  end

  def get_memory_usage
    # Get memory usage in MB
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  end
end