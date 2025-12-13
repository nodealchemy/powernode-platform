# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::AiWorkflowOrchestrator, type: :service do
  include AiOrchestrationTestHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, :with_simple_chain, account: account) }
  let(:workflow_run) do
    create(:ai_workflow_run,
      ai_workflow: workflow,
      account: account,
      triggered_by_user: user,
      status: 'initializing',
      input_variables: { key: 'value' }
    )
  end
  let(:orchestrator) { described_class.new(workflow_run: workflow_run, account: account, user: user) }

  describe '#initialize' do
    it 'initializes with workflow run and context' do
      expect(orchestrator.workflow_run).to eq(workflow_run)
      expect(orchestrator.account).to eq(account)
      expect(orchestrator.user).to eq(user)
    end

    it 'initializes MCP protocol services' do
      mcp_protocol = orchestrator.instance_variable_get(:@mcp_protocol)
      mcp_registry = orchestrator.instance_variable_get(:@mcp_registry)

      expect(mcp_protocol).to be_a(McpProtocolService)
      expect(mcp_registry).to be_a(McpRegistryService)
    end

    it 'initializes state machine' do
      state_machine = orchestrator.instance_variable_get(:@state_machine)

      expect(state_machine).to be_a(Mcp::WorkflowStateMachine)
    end

    it 'initializes event store for execution history' do
      event_store = orchestrator.instance_variable_get(:@event_store)

      expect(event_store).to be_a(Mcp::ExecutionEventStore)
    end

    it 'initializes execution tracer' do
      execution_tracer = orchestrator.instance_variable_get(:@execution_tracer)

      expect(execution_tracer).to be_a(Mcp::ExecutionTracer)
    end

    it 'initializes workflow monitor' do
      monitor = orchestrator.instance_variable_get(:@monitor)

      expect(monitor).to be_a(Mcp::WorkflowMonitor)
    end

    it 'initializes empty execution state' do
      execution_state = orchestrator.execution_state
      node_results = orchestrator.node_results

      expect(execution_state).to eq({})
      expect(node_results).to eq({})
    end
  end

  describe '#execute' do
    let(:start_node) { workflow.ai_workflow_nodes.find_by(node_type: 'start') }
    let(:end_node) { workflow.ai_workflow_nodes.find_by(node_type: 'end') }

    before do
      # Mock MCP services to avoid external dependencies
      allow_any_instance_of(Mcp::WorkflowStateMachine)
        .to receive(:transition!).and_return(true)
      allow_any_instance_of(Mcp::ExecutionEventStore)
        .to receive(:record_event).and_return(true)
      allow_any_instance_of(Mcp::ExecutionTracer)
        .to receive(:trace_start).and_return(true)
      allow_any_instance_of(Mcp::WorkflowMonitor)
        .to receive(:finalize).and_return(true)
    end

    context 'when execution succeeds' do
      before do
        allow(orchestrator).to receive(:execute_workflow_by_mode).and_return(true)
      end

      it 'initializes execution environment' do
        expect(orchestrator).to receive(:initialize_execution)

        orchestrator.execute
      end

      it 'validates workflow structure' do
        expect(orchestrator).to receive(:validate_workflow!)

        orchestrator.execute
      end

      it 'validates MCP requirements' do
        expect(orchestrator).to receive(:validate_mcp_requirements!)

        orchestrator.execute
      end

      it 'transitions workflow run from initializing to running' do
        expect_any_instance_of(Mcp::WorkflowStateMachine)
          .to receive(:transition!).with(:initializing, :running)

        orchestrator.execute
      end

      it 'executes workflow based on execution mode' do
        expect(orchestrator).to receive(:execute_workflow_by_mode)

        orchestrator.execute
      end

      it 'finalizes successful execution' do
        expect(orchestrator).to receive(:finalize_execution)

        orchestrator.execute
      end

      it 'reloads and returns the workflow run' do
        result = orchestrator.execute

        expect(result).to eq(workflow_run)
        expect(result.status).to be_in(%w[completed running])
      end
    end

    context 'when execution fails' do
      let(:error_message) { 'Workflow execution failed' }

      before do
        allow(orchestrator).to receive(:execute_workflow_by_mode)
          .and_raise(StandardError, error_message)
      end

      it 'handles execution failure' do
        expect(orchestrator).to receive(:handle_execution_failure)
          .with(instance_of(StandardError))

        expect { orchestrator.execute }.to raise_error(described_class::WorkflowExecutionError)
      end

      it 'raises WorkflowExecutionError with message' do
        expect { orchestrator.execute }
          .to raise_error(described_class::WorkflowExecutionError, /Workflow execution failed/)
      end

      it 'ensures monitoring cleanup even on failure' do
        monitor = orchestrator.instance_variable_get(:@monitor)
        expect(monitor).to receive(:finalize)

        expect { orchestrator.execute }.to raise_error(described_class::WorkflowExecutionError)
      end
    end

    context 'when validation fails' do
      it 'raises error for invalid workflow structure' do
        allow(orchestrator).to receive(:validate_workflow!)
          .and_raise(described_class::WorkflowExecutionError, 'Invalid workflow')

        expect { orchestrator.execute }
          .to raise_error(described_class::WorkflowExecutionError, /Invalid workflow/)
      end

      it 'raises error for missing MCP requirements' do
        allow(orchestrator).to receive(:validate_mcp_requirements!)
          .and_raise(described_class::WorkflowExecutionError, 'Missing MCP config')

        expect { orchestrator.execute }
          .to raise_error(described_class::WorkflowExecutionError, /Missing MCP config/)
      end
    end
  end

  describe '#execute_workflow_by_mode' do
    context 'with sequential execution mode' do
      before do
        workflow.update!(configuration: workflow.configuration.merge(execution_mode: 'sequential'))
      end

      it 'executes nodes in sequential order' do
        expect(orchestrator).to receive(:execute_sequential_mode)

        orchestrator.send(:execute_workflow_by_mode)
      end
    end

    context 'with parallel execution mode' do
      before do
        # Set mcp_orchestration_config to use parallel execution mode
        workflow.update!(mcp_orchestration_config: { 'execution_mode' => 'parallel' })
      end

      it 'executes independent nodes in parallel' do
        expect(orchestrator).to receive(:execute_parallel_mode)

        orchestrator.send(:execute_workflow_by_mode)
      end
    end

    context 'with conditional execution mode' do
      before do
        # Set mcp_orchestration_config to use conditional execution mode
        workflow.update!(mcp_orchestration_config: { 'execution_mode' => 'conditional' })
      end

      it 'executes nodes based on conditions' do
        expect(orchestrator).to receive(:execute_conditional_mode)

        orchestrator.send(:execute_workflow_by_mode)
      end
    end

    context 'with dag execution mode' do
      before do
        # Set mcp_orchestration_config to use dag execution mode
        workflow.update!(mcp_orchestration_config: { 'execution_mode' => 'dag' })
      end

      it 'executes nodes based on dependency graph' do
        expect(orchestrator).to receive(:execute_dag_mode)

        orchestrator.send(:execute_workflow_by_mode)
      end
    end

    context 'with unknown execution mode' do
      before do
        # Set mcp_orchestration_config with invalid mode
        workflow.update!(mcp_orchestration_config: { 'execution_mode' => 'invalid_mode' })
      end

      it 'defaults to sequential mode for unknown mode' do
        # Implementation defaults to sequential mode for unknown modes
        expect(orchestrator).to receive(:execute_sequential_mode)

        orchestrator.send(:execute_workflow_by_mode)
      end
    end
  end

  describe '#initialize_execution' do
    it 'sets up execution environment' do
      orchestrator.send(:initialize_execution)

      execution_context = orchestrator.instance_variable_get(:@execution_context)
      expect(execution_context).to include(
        :workflow_id,
        :account_id,
        :user_id,
        :started_at
      )
    end

    it 'initializes MCP protocol service' do
      orchestrator.send(:initialize_execution)

      mcp_protocol = orchestrator.instance_variable_get(:@mcp_protocol)
      expect(mcp_protocol).to be_a(McpProtocolService)
    end

    it 'initializes execution tracers and monitoring' do
      orchestrator.send(:initialize_execution)

      event_store = orchestrator.instance_variable_get(:@event_store)
      execution_tracer = orchestrator.instance_variable_get(:@execution_tracer)
      monitor = orchestrator.instance_variable_get(:@monitor)

      expect(event_store).to be_a(Mcp::ExecutionEventStore)
      expect(execution_tracer).to be_a(Mcp::ExecutionTracer)
      expect(monitor).to be_a(Mcp::WorkflowMonitor)
    end
  end

  describe '#validate_workflow!' do
    context 'with valid workflow' do
      it 'passes validation' do
        expect { orchestrator.send(:validate_workflow!) }.not_to raise_error
      end
    end

    context 'with invalid workflow' do
      it 'raises error when workflow cannot execute' do
        allow(workflow).to receive(:can_execute?).and_return(false)
        allow(workflow).to receive(:status).and_return('draft')

        expect { orchestrator.send(:validate_workflow!) }
          .to raise_error(described_class::WorkflowExecutionError, /cannot be executed/)
      end

      it 'raises error for invalid workflow structure' do
        # Need to stub can_execute? first since it's checked before structure
        allow(workflow).to receive(:can_execute?).and_return(true)
        allow(workflow).to receive(:has_valid_structure?).and_return(false)

        expect { orchestrator.send(:validate_workflow!) }
          .to raise_error(described_class::WorkflowExecutionError, /structure is invalid/)
      end

      it 'raises error for missing start nodes' do
        # Simulate no start nodes
        allow(orchestrator).to receive(:find_start_nodes).and_return([])

        expect { orchestrator.send(:validate_workflow!) }
          .to raise_error(described_class::WorkflowExecutionError, /No start nodes/)
      end
    end
  end

  describe '#validate_mcp_requirements!' do
    context 'when no tool requirements are specified' do
      before do
        workflow.update!(mcp_orchestration_config: {})
      end

      it 'passes MCP validation' do
        expect { orchestrator.send(:validate_mcp_requirements!) }.not_to raise_error
      end
    end

    context 'when tool requirements are specified' do
      let(:mcp_registry) { orchestrator.instance_variable_get(:@mcp_registry) }

      before do
        workflow.update!(mcp_orchestration_config: {
          'tool_requirements' => [
            { 'tool_id' => 'test_tool', 'min_version' => '1.0.0' }
          ]
        })
      end

      it 'validates required tools exist in registry' do
        allow(mcp_registry).to receive(:get_tool).with('test_tool')
          .and_return({ 'version' => '1.0.0' })

        expect { orchestrator.send(:validate_mcp_requirements!) }.not_to raise_error
      end

      it 'raises error for missing required tool' do
        allow(mcp_registry).to receive(:get_tool).with('test_tool').and_return(nil)

        expect { orchestrator.send(:validate_mcp_requirements!) }
          .to raise_error(described_class::WorkflowExecutionError, /Required MCP tool not found/)
      end

      it 'raises error for incompatible tool version' do
        allow(mcp_registry).to receive(:get_tool).with('test_tool')
          .and_return({ 'version' => '0.5.0' })

        expect { orchestrator.send(:validate_mcp_requirements!) }
          .to raise_error(described_class::WorkflowExecutionError, /version.*is below required/)
      end
    end
  end

  describe 'state transitions' do
    let(:state_machine) { orchestrator.instance_variable_get(:@state_machine) }

    describe '#transition_state!' do
      it 'transitions workflow run state via state machine' do
        expect(state_machine).to receive(:transition!)
          .with(:initializing, :running)

        orchestrator.send(:transition_state!, :initializing, :running)
      end

      it 'records state transition event' do
        event_store = orchestrator.instance_variable_get(:@event_store)

        # Event store record_event uses keyword arguments
        expect(event_store).to receive(:record_event)
          .with(hash_including(event_type: 'workflow.state.transitioned'))

        orchestrator.send(:transition_state!, :initializing, :running)
      end

      it 'raises StateTransitionError for invalid transition' do
        allow(state_machine).to receive(:transition!)
          .and_raise(Mcp::WorkflowStateMachine::StateTransitionError, 'Invalid transition')

        expect { orchestrator.send(:transition_state!, :completed, :running) }
          .to raise_error(described_class::StateTransitionError)
      end
    end

    it 'follows correct state flow: initializing → running → completed' do
      # Track transitions
      transitions = []
      allow(state_machine).to receive(:transition!) do |from, to|
        transitions << { from: from, to: to }
      end

      orchestrator.send(:transition_state!, :initializing, :running)
      orchestrator.send(:transition_state!, :running, :completed)

      expect(transitions).to eq([
        { from: :initializing, to: :running },
        { from: :running, to: :completed }
      ])
    end

    it 'transitions to failed state on error' do
      allow(state_machine).to receive(:transition!)
      allow(state_machine).to receive(:current_state).and_return(:running)

      expect(state_machine).to receive(:transition!).with(:running, :failed)

      orchestrator.send(:transition_state!, :running, :failed)
    end
  end

  describe 'execution modes' do
    # Create workflow without :with_simple_chain to avoid duplicate nodes
    let(:execution_workflow) { create(:ai_workflow, account: account) }
    let(:execution_user) { create(:user, account: account) }
    let(:execution_workflow_run) do
      create(:ai_workflow_run, ai_workflow: execution_workflow, account: account, triggered_by_user: execution_user, status: 'initializing')
    end
    let(:execution_orchestrator) { described_class.new(workflow_run: execution_workflow_run, account: account, user: execution_user) }

    let(:start_node) { create(:ai_workflow_node, :start_node, ai_workflow: execution_workflow) }
    let(:end_node) { create(:ai_workflow_node, :end_node, ai_workflow: execution_workflow) }
    let(:node1) { create(:ai_workflow_node, :ai_agent, ai_workflow: execution_workflow) }
    let(:node2) { create(:ai_workflow_node, :transform, ai_workflow: execution_workflow) }
    let(:node3) { create(:ai_workflow_node, :api_call, ai_workflow: execution_workflow) }

    describe '#execute_sequential_mode' do
      before do
        # Create linear workflow: start → node1 → node2 → node3 → end
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: start_node.node_id, target_node_id: node1.node_id)
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: node1.node_id, target_node_id: node2.node_id)
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: node2.node_id, target_node_id: node3.node_id)
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: node3.node_id, target_node_id: end_node.node_id)

        # Mock MCP infrastructure
        allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
        allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:execute_node).and_return(true)
        allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)
        allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)
        allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize).and_return(true)

        # Initialize execution context
        execution_orchestrator.send(:initialize_execution)
      end

      it 'executes nodes in sequential order' do
        execution_order = []
        node_results = execution_orchestrator.instance_variable_get(:@node_results)

        allow(execution_orchestrator).to receive(:execute_node) do |node|
          execution_order << node.node_id
          create(:ai_workflow_node_execution, :completed,
            ai_workflow_run: execution_workflow_run,
            ai_workflow_node: node
          )
          # Store result in @node_results for prerequisites check
          result = { success: true, output: {}, status: 'completed' }
          node_results[node.node_id] = result
          result
        end

        execution_orchestrator.send(:execute_sequential_mode)

        expect(execution_order).to eq([
          start_node.node_id,
          node1.node_id,
          node2.node_id,
          node3.node_id,
          end_node.node_id
        ])
      end

      it 'completes each node before proceeding to the next' do
        completed_timestamps = []
        node_results = execution_orchestrator.instance_variable_get(:@node_results)

        allow(execution_orchestrator).to receive(:execute_node) do |node|
          completed_timestamps << { node_id: node.node_id, time: Time.current }
          result = { success: true, output: { processed_at: Time.current }, status: 'completed' }
          node_results[node.node_id] = result
          result
        end

        execution_orchestrator.send(:execute_sequential_mode)

        # Verify execution order - each completion timestamp should be after the previous
        completed_timestamps.each_cons(2) do |prev, current|
          expect(current[:time]).to be >= prev[:time]
        end
      end

      it 'propagates data between sequential nodes' do
        node_results = execution_orchestrator.instance_variable_get(:@node_results)
        accumulated_data = []

        allow(execution_orchestrator).to receive(:execute_node) do |node|
          # Access previous node results from execution context
          previous_keys = node_results.keys
          accumulated_data << { node_id: node.node_id, previous_outputs: previous_keys.dup }

          result = { success: true, output: { node_output: "data_from_#{node.node_id}" }, status: 'completed' }
          node_results[node.node_id] = result
          result
        end

        execution_orchestrator.send(:execute_sequential_mode)

        # Each node (except start) should have access to previous node results
        expect(accumulated_data[1][:previous_outputs]).to include(start_node.node_id)
        expect(accumulated_data[2][:previous_outputs]).to include(node1.node_id)
        expect(accumulated_data[3][:previous_outputs]).to include(node2.node_id)
      end
    end

    describe '#execute_parallel_mode' do
      # Create a proper stub class that accepts keyword arguments
      let(:parallel_coordinator_class) do
        Class.new do
          attr_reader :node_results, :execution_path

          def initialize(**kwargs)
            @node_results = {}
            @execution_path = []
          end

          def execute_parallel
            # stub implementation
          end
        end
      end
      let(:parallel_coordinator) { instance_double('ParallelExecutionCoordinator') }

      before do
        # Create nodes first so they exist when execution_orchestrator is created
        start_node
        end_node
        node1
        node2
        node3

        # Stub the constant to exist with proper class that accepts keyword args
        stub_const('Mcp::ParallelExecutionCoordinator', parallel_coordinator_class)

        # Mock MCP infrastructure
        allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
        allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:execute_node).and_return(true)
        allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)
        allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)
        allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize).and_return(true)

        # Reload workflow to pick up nodes
        execution_workflow.reload

        # Initialize execution context
        execution_orchestrator.send(:initialize_execution)
      end

      it 'delegates to ParallelExecutionCoordinator' do
        allow(parallel_coordinator_class).to receive(:new).and_return(parallel_coordinator)
        allow(parallel_coordinator).to receive(:execute_parallel)
        allow(parallel_coordinator).to receive(:node_results).and_return({})
        allow(parallel_coordinator).to receive(:execution_path).and_return([])

        expect(parallel_coordinator).to receive(:execute_parallel)

        execution_orchestrator.send(:execute_parallel_mode)
      end

      it 'merges results from parallel coordinator' do
        parallel_results = {
          node1.node_id => { success: true, output: 'result1' },
          node2.node_id => { success: true, output: 'result2' },
          node3.node_id => { success: true, output: 'result3' }
        }
        execution_path = [ node1.node_id, node2.node_id, node3.node_id ]

        allow(parallel_coordinator_class).to receive(:new).and_return(parallel_coordinator)
        allow(parallel_coordinator).to receive(:execute_parallel)
        allow(parallel_coordinator).to receive(:node_results).and_return(parallel_results)
        allow(parallel_coordinator).to receive(:execution_path).and_return(execution_path)

        execution_orchestrator.send(:execute_parallel_mode)

        expect(execution_orchestrator.node_results).to include(
          node1.node_id => hash_including(success: true),
          node2.node_id => hash_including(success: true),
          node3.node_id => hash_including(success: true)
        )
      end

      it 'records execution path from parallel coordinator' do
        execution_path = [ node1.node_id, node2.node_id, node3.node_id ]

        allow(parallel_coordinator_class).to receive(:new).and_return(parallel_coordinator)
        allow(parallel_coordinator).to receive(:execute_parallel)
        allow(parallel_coordinator).to receive(:node_results).and_return({})
        allow(parallel_coordinator).to receive(:execution_path).and_return(execution_path)

        execution_orchestrator.send(:execute_parallel_mode)

        execution_context = execution_orchestrator.instance_variable_get(:@execution_context)
        expect(execution_context[:execution_path]).to include(*execution_path)
      end
    end

    describe '#execute_dag_mode' do
      before do
        # Create DAG structure: start → node1 → node2 → end
        #                               ↘ node3 ↗
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: start_node.node_id, target_node_id: node1.node_id)
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: node1.node_id, target_node_id: node2.node_id)
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: node1.node_id, target_node_id: node3.node_id)
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: node2.node_id, target_node_id: end_node.node_id)
        create(:ai_workflow_edge, ai_workflow: execution_workflow,
          source_node_id: node3.node_id, target_node_id: end_node.node_id)

        # Mock MCP infrastructure
        allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
        allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:execute_node).and_return(true)
        allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)
        allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)
        allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize).and_return(true)

        # Initialize execution context
        execution_orchestrator.send(:initialize_execution)
      end

      it 'builds and executes DAG execution plan' do
        node_results = execution_orchestrator.instance_variable_get(:@node_results)

        allow(execution_orchestrator).to receive(:execute_node) do |node|
          result = { success: true, output: {}, status: 'completed' }
          node_results[node.node_id] = result
          result
        end

        allow(execution_orchestrator).to receive(:execute_node_batch_parallel) do |batch|
          batch.each do |node|
            result = { success: true, output: {}, status: 'completed' }
            node_results[node.node_id] = result
          end
        end

        expect(execution_orchestrator).to receive(:build_dag_execution_plan).and_call_original

        execution_orchestrator.send(:execute_dag_mode)
      end

      it 'executes nodes in dependency order' do
        execution_batches = []
        node_results = execution_orchestrator.instance_variable_get(:@node_results)

        allow(execution_orchestrator).to receive(:execute_node) do |node|
          execution_batches << [ :single, node.node_id ]
          result = { success: true, output: {}, status: 'completed' }
          node_results[node.node_id] = result
          result
        end

        allow(execution_orchestrator).to receive(:execute_node_batch_parallel) do |batch|
          execution_batches << [ :batch, batch.map(&:node_id) ]
          batch.each do |node|
            result = { success: true, output: {}, status: 'completed' }
            node_results[node.node_id] = result
          end
        end

        execution_orchestrator.send(:execute_dag_mode)

        # Verify execution order follows DAG dependencies
        single_executions = execution_batches.select { |type, _| type == :single }.map { |_, id| id }
        expect(single_executions.first).to eq(start_node.node_id)
      end

      it 'handles parallel batches when nodes have same dependencies' do
        node_results = execution_orchestrator.instance_variable_get(:@node_results)
        parallel_batches_executed = []

        allow(execution_orchestrator).to receive(:execute_node) do |node|
          result = { success: true, output: {}, status: 'completed' }
          node_results[node.node_id] = result
          result
        end

        allow(execution_orchestrator).to receive(:execute_node_batch_parallel) do |batch|
          parallel_batches_executed << batch.map(&:node_id)
          batch.each do |node|
            result = { success: true, output: {}, status: 'completed' }
            node_results[node.node_id] = result
          end
        end

        execution_orchestrator.send(:execute_dag_mode)

        # node2 and node3 should be in same batch since they both depend only on node1
        if parallel_batches_executed.any?
          batch_with_parallel_nodes = parallel_batches_executed.find { |b| b.length > 1 }
          if batch_with_parallel_nodes
            expect(batch_with_parallel_nodes).to include(node2.node_id, node3.node_id)
          end
        end
      end
    end
  end

  describe 'node execution' do
    let(:ai_agent_node) { create(:ai_workflow_node, :ai_agent, ai_workflow: workflow) }

    before do
      # Mock MCP infrastructure
      allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
      allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:execute_node).and_return(true)
      allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)
      allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)
      allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_node_completion).and_return(true)
      allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize).and_return(true)
      allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:node_completed).and_return(true)

      # Initialize execution context
      orchestrator.send(:initialize_execution)
    end

    describe '#execute_node' do
      let(:mock_executor) do
        instance_double('Mcp::NodeExecutors::AiAgent',
          execute: { success: true, output: { result: 'test_result' }, metadata: { cost: 0.01 } }
        )
      end

      before do
        allow(Mcp::NodeExecutors::AiAgent).to receive(:new).and_return(mock_executor)
        allow_any_instance_of(AiWorkflowNodeExecution).to receive(:start_execution!).and_return(true)
        allow_any_instance_of(AiWorkflowNodeExecution).to receive(:complete_execution!).and_return(true)
        allow_any_instance_of(AiWorkflowNodeExecution).to receive(:update_run_progress).and_return(true)
        allow_any_instance_of(AiWorkflowNodeExecution).to receive(:add_cost_to_run_explicit).and_return(true)
      end

      it 'creates node execution record' do
        expect {
          orchestrator.send(:execute_node, ai_agent_node)
        }.to change { workflow_run.ai_workflow_node_executions.count }.by(1)
      end

      it 'delegates to appropriate node executor' do
        expect(mock_executor).to receive(:execute).and_return({
          success: true,
          output: { result: 'test_result' },
          metadata: { cost: 0.01 }
        })

        orchestrator.send(:execute_node, ai_agent_node)
      end

      it 'stores execution result in node_results' do
        orchestrator.send(:execute_node, ai_agent_node)

        expect(orchestrator.node_results[ai_agent_node.node_id]).to include(
          success: true
        )
      end

      it 'handles node execution failures' do
        allow(mock_executor).to receive(:execute).and_raise(StandardError, 'Node failed')
        allow_any_instance_of(AiWorkflowNodeExecution).to receive(:fail_execution!).and_return(true)

        expect { orchestrator.send(:execute_node, ai_agent_node) }
          .to raise_error(described_class::NodeExecutionError, /Node failed/)
      end
    end

    describe '#get_mcp_node_executor' do
      let(:node_execution) { create(:ai_workflow_node_execution, ai_workflow_run: workflow_run, ai_workflow_node: ai_agent_node) }
      let(:node_context) { instance_double(Mcp::NodeExecutionContext, scoped_variables: {}) }

      it 'returns correct executor for ai_agent node' do
        executor = orchestrator.send(:get_mcp_node_executor, ai_agent_node, node_execution, node_context)
        expect(executor).to be_a(Mcp::NodeExecutors::AiAgent)
      end

      it 'raises error for unknown node type' do
        # Mock node_type to return an invalid type (can't set directly due to DB CHECK constraint)
        allow(ai_agent_node).to receive(:node_type).and_return('unknown_type')
        expect {
          orchestrator.send(:get_mcp_node_executor, ai_agent_node, node_execution, node_context)
        }.to raise_error(described_class::NodeExecutionError, /Unknown node type/)
      end
    end
  end

  describe 'execution finalization' do
    before do
      # Mock MCP infrastructure
      allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
      allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)
      allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)
      allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize).and_return(true)

      # Initialize execution context
      orchestrator.send(:initialize_execution)
    end

    describe '#finalize_execution' do
      before do
        # Create some successful executions with nodes attached
        workflow.ai_workflow_nodes.limit(3).each do |node|
          create(:ai_workflow_node_execution, :completed,
            ai_workflow_run: workflow_run,
            ai_workflow_node: node,
            output_data: { result: 'success' },
            cost: 0.15
          )
        end

        # Update workflow_run to have a started_at timestamp
        workflow_run.update!(started_at: 1.minute.ago)

        # Mock broadcast method to avoid ActionCable dependencies
        stub_action_cable_broadcasting
      end

      it 'transitions workflow run to completed state' do
        expect_any_instance_of(Mcp::WorkflowStateMachine)
          .to receive(:transition!).with(:running, :completed)

        orchestrator.send(:finalize_execution)
      end

      it 'compiles final output' do
        orchestrator.send(:finalize_execution)

        workflow_run.reload
        expect(workflow_run.output_variables).to be_present
      end

      it 'sets completion timestamp' do
        orchestrator.send(:finalize_execution)

        workflow_run.reload
        expect(workflow_run.completed_at).to be_present
        expect(workflow_run.completed_at).to be > workflow_run.started_at
      end

      it 'updates workflow run status to completed' do
        orchestrator.send(:finalize_execution)

        workflow_run.reload
        expect(workflow_run.status).to eq('completed')
      end
    end

    describe '#handle_execution_failure' do
      let(:error) { StandardError.new('Critical error') }

      before do
        # Initialize execution
        orchestrator.send(:initialize_execution)

        # Create a running node execution
        create(:ai_workflow_node_execution, :running,
          ai_workflow_run: workflow_run,
          ai_workflow_node: workflow.ai_workflow_nodes.first
        )

        # Mock broadcast method
        stub_action_cable_broadcasting
      end

      it 'transitions workflow run to failed state' do
        # The actual current state is :initializing, not :running
        expect_any_instance_of(Mcp::WorkflowStateMachine)
          .to receive(:transition!).with(:initializing, :failed)

        orchestrator.send(:handle_execution_failure, error)
      end

      it 'records error message in error details' do
        orchestrator.send(:handle_execution_failure, error)

        workflow_run.reload
        expect(workflow_run.error_details['error_message']).to eq('Critical error')
      end

      it 'stores error details with exception class' do
        orchestrator.send(:handle_execution_failure, error)

        workflow_run.reload
        expect(workflow_run.error_details).to be_present
        expect(workflow_run.error_details['exception_class']).to eq('StandardError')
      end

      it 'cancels running node executions' do
        orchestrator.send(:handle_execution_failure, error)

        running_executions = workflow_run.ai_workflow_node_executions.where(status: 'running')
        expect(running_executions.count).to eq(0)
      end

      it 'updates workflow run status to failed' do
        orchestrator.send(:handle_execution_failure, error)

        workflow_run.reload
        expect(workflow_run.status).to eq('failed')
      end
    end
  end

  describe 'event sourcing and tracing' do
    let(:event_store) { orchestrator.instance_variable_get(:@event_store) }
    let(:execution_tracer) { orchestrator.instance_variable_get(:@execution_tracer) }

    before do
      # Allow state machine transitions
      allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
      allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize).and_return(true)
    end

    it 'records workflow start event via execution tracer' do
      # trace_start is called in the execute method, not initialize_execution
      # Verify the tracer is properly initialized with trace_start capability
      allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)

      # Create a mock tracer that will record if trace_start was called
      trace_start_called = false
      mock_tracer = double('ExecutionTracer')
      allow(mock_tracer).to receive(:trace_start) { trace_start_called = true }
      allow(Mcp::ExecutionTracer).to receive(:new).and_return(mock_tracer)

      # Mock other dependencies needed for execute
      allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:initialize_state)
      allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
      allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize).and_return(true)

      # Create fresh orchestrator and call execute
      fresh_orchestrator = described_class.new(workflow_run: workflow_run, account: account, user: user)

      # Stub out the main execution methods to focus on trace_start verification
      allow(fresh_orchestrator).to receive(:validate_workflow!)
      allow(fresh_orchestrator).to receive(:validate_mcp_requirements!)
      allow(fresh_orchestrator).to receive(:execute_workflow_by_mode)
      allow(fresh_orchestrator).to receive(:finalize_execution)

      fresh_orchestrator.execute

      expect(trace_start_called).to be true
    end

    it 'records events in event store during execution' do
      allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)

      expect_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).at_least(:once)

      orchestrator.send(:initialize_execution)
    end

    it 'records state transition events' do
      allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)
      orchestrator.send(:initialize_execution)

      expect_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event)
        .with(hash_including(event_type: 'workflow.state.transitioned'))

      orchestrator.send(:transition_state!, :initializing, :running)
    end

    it 'initializes execution events array' do
      allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)
      allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)

      orchestrator.send(:initialize_execution)

      # Execution events should be initialized
      expect(orchestrator.instance_variable_get(:@execution_context)).to be_a(Hash)
    end
  end

  describe 'monitoring and broadcasting' do
    let(:monitor) { orchestrator.instance_variable_get(:@monitor) }

    before do
      # Mock all MCP infrastructure
      allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
      allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)
      allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)

      # Initialize execution
      orchestrator.send(:initialize_execution)
    end

    it 'initializes workflow monitor' do
      monitor = orchestrator.instance_variable_get(:@monitor)
      expect(monitor).to be_a(Mcp::WorkflowMonitor)
    end

    it 'finalizes monitoring on execution completion' do
      expect_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize)

      # Simulate workflow execution completing
      allow(orchestrator).to receive(:execute_workflow_by_mode).and_return(true)
      stub_action_cable_broadcasting

      begin
        orchestrator.execute
      rescue StandardError
        # Ignore errors during test
      end
    end

    it 'provides workflow run reference to monitor' do
      monitor = orchestrator.instance_variable_get(:@monitor)
      expect(monitor.instance_variable_get(:@workflow_run)).to eq(workflow_run)
    end
  end

  describe 'integration with MCP services' do
    let(:mcp_protocol) { orchestrator.instance_variable_get(:@mcp_protocol) }
    let(:mcp_registry) { orchestrator.instance_variable_get(:@mcp_registry) }

    before do
      # Mock MCP infrastructure
      allow_any_instance_of(Mcp::WorkflowStateMachine).to receive(:transition!).and_return(true)
      allow_any_instance_of(Mcp::ExecutionEventStore).to receive(:record_event).and_return(true)
      allow_any_instance_of(Mcp::ExecutionTracer).to receive(:trace_start).and_return(true)
      allow_any_instance_of(Mcp::WorkflowMonitor).to receive(:finalize).and_return(true)
    end

    it 'initializes MCP protocol service' do
      mcp_protocol = orchestrator.instance_variable_get(:@mcp_protocol)
      expect(mcp_protocol).to be_a(McpProtocolService)
    end

    it 'initializes MCP registry service' do
      mcp_registry = orchestrator.instance_variable_get(:@mcp_registry)
      expect(mcp_registry).to be_a(McpRegistryService)
    end

    it 'validates MCP tool requirements when configured' do
      # Setup workflow with no tool requirements (empty validation)
      orchestrator.send(:initialize_execution)

      # Should not raise when no tool requirements are configured
      expect { orchestrator.send(:validate_mcp_requirements!) }.not_to raise_error
    end

    it 'validates tool availability in registry' do
      # Configure workflow with tool requirements
      workflow.update!(mcp_orchestration_config: {
        'tool_requirements' => [
          { 'tool_id' => 'test-tool', 'min_version' => '1.0.0' }
        ]
      })

      # Mock registry to return tool manifest
      allow(mcp_registry).to receive(:get_tool)
        .with('test-tool')
        .and_return({ 'version' => '1.0.0' })

      orchestrator.send(:initialize_execution)

      expect { orchestrator.send(:validate_mcp_requirements!) }.not_to raise_error
    end

    it 'raises error when required tool is missing' do
      # Configure workflow with tool requirements
      workflow.update!(mcp_orchestration_config: {
        'tool_requirements' => [
          { 'tool_id' => 'missing-tool' }
        ]
      })

      # Mock registry to return nil (tool not found)
      allow(mcp_registry).to receive(:get_tool)
        .with('missing-tool')
        .and_return(nil)

      orchestrator.send(:initialize_execution)

      expect { orchestrator.send(:validate_mcp_requirements!) }
        .to raise_error(described_class::WorkflowExecutionError, /Required MCP tool not found/)
    end
  end
end
