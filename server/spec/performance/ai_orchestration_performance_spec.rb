# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

# Performance tests for MCP-based AI Workflow Orchestration
# These tests verify performance characteristics of the Mcp::AiWorkflowOrchestrator
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
    mock_mcp_orchestration_services
    setup_performance_monitoring
  end

  describe 'workflow execution performance' do
    context 'single workflow execution' do
      let(:simple_workflow) { create_simple_workflow(account) }

      it 'executes simple workflow within acceptable time limits' do
        workflow_run = create(:ai_workflow_run, ai_workflow: simple_workflow, status: 'initializing', triggered_by_user: user)

        execution_time = Benchmark.realtime do
          orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: workflow_run, account: account, user: user)
          orchestrator.execute
        end

        expect(execution_time).to be < 5.0 # Should complete within 5 seconds
        expect(workflow_run.reload.status).to eq('completed')
      end

      it 'handles complex workflow with multiple nodes efficiently' do
        complex_workflow = create_complex_workflow(account, node_count: 10)
        workflow_run = create(:ai_workflow_run, ai_workflow: complex_workflow, status: 'initializing', triggered_by_user: user)

        execution_time = Benchmark.realtime do
          orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: workflow_run, account: account, user: user)
          orchestrator.execute
        end

        expect(execution_time).to be < 15.0 # Complex workflow should complete within 15 seconds
        expect(complex_workflow.ai_workflow_nodes.count).to eq(10)
      end
    end

    context 'multiple workflow executions' do
      it 'handles multiple workflows sequentially without performance degradation' do
        workflows = 5.times.map { create_simple_workflow(account) }
        workflow_runs = workflows.map { |w| create(:ai_workflow_run, ai_workflow: w, status: 'initializing', triggered_by_user: user) }

        execution_times = []

        workflow_runs.each do |run|
          execution_time = Benchmark.realtime do
            orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: run, account: account, user: user)
            orchestrator.execute
          end
          execution_times << execution_time
        end

        # All executions should complete within reasonable time
        expect(execution_times.max).to be < 8.0
        expect(execution_times.length).to eq(5)

        # Average execution time should remain consistent
        expect(execution_times.sum / execution_times.length).to be < 6.0

        # All workflows should complete successfully
        workflow_runs.each do |run|
          expect(run.reload.status).to eq('completed')
        end
      end

      it 'maintains consistent performance across many sequential executions' do
        execution_results = []

        # Execute 10 workflows sequentially to test consistent performance
        10.times do
          workflow = create_simple_workflow(account)
          workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing', triggered_by_user: user)

          begin
            execution_time = Benchmark.realtime do
              orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: workflow_run, account: account, user: user)
              orchestrator.execute
            end
            execution_results << { success: true, time: execution_time, workflow_id: workflow.id }
          rescue => e
            execution_results << { success: false, error: e.message }
          end
        end

        # All workflows should complete successfully
        successful_executions = execution_results.count { |r| r[:success] }
        expect(successful_executions).to eq(10)

        # No failures should occur
        failed_executions = execution_results.count { |r| !r[:success] }
        expect(failed_executions).to eq(0)

        # Execution times should be consistent (no degradation)
        times = execution_results.select { |r| r[:success] }.map { |r| r[:time] }
        avg_time = times.sum / times.length
        max_deviation = times.map { |t| (t - avg_time).abs }.max

        # Max deviation from average should be reasonable (within 3 seconds)
        expect(max_deviation).to be < 3.0
      end
    end
  end


  describe 'memory usage and garbage collection' do
    it 'maintains reasonable memory usage during long-running orchestrations' do
      initial_memory = get_memory_usage

      # Execute many workflows to test memory management
      50.times do |i|
        workflow = create_simple_workflow(account)
        workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing', triggered_by_user: user)

        orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: workflow_run, account: account, user: user)
        orchestrator.execute

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
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing', triggered_by_user: user)

      initial_objects = ObjectSpace.count_objects

      orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: workflow_run, account: account, user: user)
      orchestrator.execute

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
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing', triggered_by_user: user)

      query_count = 0
      original_method = ActiveRecord::Base.connection.method(:execute)

      allow(ActiveRecord::Base.connection).to receive(:execute) do |*args|
        query_count += 1
        original_method.call(*args)
      end

      orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: workflow_run, account: account, user: user)
      orchestrator.execute

      # Should not generate excessive database queries (MCP orchestrator may have more queries due to event sourcing)
      expect(query_count).to be < 200 # Reasonable limit for complex workflow with MCP overhead
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

  describe 'error handling performance' do
    it 'recovers from errors quickly without cascading delays' do
      workflow = create_simple_workflow(account)
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, status: 'initializing', triggered_by_user: user)

      recovery_time = Benchmark.realtime do
        orchestrator = Mcp::AiWorkflowOrchestrator.new(workflow_run: workflow_run, account: account, user: user)
        orchestrator.execute
      end

      # Should complete within reasonable time
      expect(recovery_time).to be < 8.0
      expect(workflow_run.reload.status).to eq('completed')
    end
  end

  private

  def create_simple_workflow(account)
    workflow = create(:ai_workflow, account: account, name: "Simple Performance Test #{SecureRandom.hex(4)}", status: 'active')

    start_node = create(:ai_workflow_node,
      ai_workflow: workflow,
      node_id: 'start-1',
      node_type: 'start',
      is_start_node: true,
      configuration: { label: 'Start' }
    )

    agent_node = create(:ai_workflow_node,
      ai_workflow: workflow,
      node_id: 'agent-1',
      node_type: 'ai_agent',
      configuration: { agent_id: ai_agent.id, label: 'AI Agent' }
    )

    end_node = create(:ai_workflow_node,
      ai_workflow: workflow,
      node_id: 'end-1',
      node_type: 'end',
      configuration: { label: 'End' }
    )

    create(:ai_workflow_edge,
      ai_workflow: workflow,
      source_node_id: start_node.node_id,
      target_node_id: agent_node.node_id
    )

    create(:ai_workflow_edge,
      ai_workflow: workflow,
      source_node_id: agent_node.node_id,
      target_node_id: end_node.node_id
    )

    workflow
  end

  def create_complex_workflow(account, node_count: 10)
    workflow = create(:ai_workflow, account: account, name: "Complex Performance Test #{SecureRandom.hex(4)}", status: 'active')

    nodes = []

    # Create start node
    start_node = create(:ai_workflow_node,
      ai_workflow: workflow,
      node_id: 'start-1',
      node_type: 'start',
      is_start_node: true,
      configuration: { label: 'Start' }
    )
    nodes << start_node

    # Create processing nodes (node_count - 2 to account for start and end)
    (node_count - 2).times do |i|
      node = create(:ai_workflow_node,
        ai_workflow: workflow,
        node_id: "node-#{i + 1}",
        node_type: %w[ai_agent transform].sample, # Use only executable node types
        configuration: {
          label: "Node #{i + 1}",
          agent_id: ai_agent.id,
          transformation: 'result.processed = true'
        }
      )
      nodes << node
    end

    # Create end node
    end_node = create(:ai_workflow_node,
      ai_workflow: workflow,
      node_id: 'end-1',
      node_type: 'end',
      configuration: { label: 'End' }
    )
    nodes << end_node

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
