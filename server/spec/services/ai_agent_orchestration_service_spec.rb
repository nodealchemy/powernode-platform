# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentOrchestrationService, type: :service do
  include AiOrchestrationTestHelpers

  # Timeout protection to prevent infinite loops in workflow execution
  around(:each) do |example|
    Timeout.timeout(30) do
      example.run
    end
  rescue Timeout::Error
    fail "Test exceeded 30 second timeout - likely infinite loop in workflow execution"
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) do
    wf = create(:ai_workflow, account: account)
    start_node = create(:ai_workflow_node, :start_node, ai_workflow: wf)
    end_node = create(:ai_workflow_node, :end_node, ai_workflow: wf)
    create(:ai_workflow_edge, ai_workflow: wf, source_node_id: start_node.node_id, target_node_id: end_node.node_id)
    wf
  end
  let(:ai_provider) { create(:ai_provider, account: account) }
  let(:service) { described_class.new(workflow) }

  describe '#initialize' do
    it 'initializes with a workflow' do
      expect(service.workflow).to eq(workflow)
      expect(service.account).to eq(account)
    end

    it 'sets up execution context' do
      expect(service.execution_context).to be_a(Hash)
      expect(service.execution_context[:workflow_id]).to eq(workflow.id)
      expect(service.execution_context[:account_id]).to eq(account.id)
    end

    it 'initializes node executors registry' do
      expect(service.node_executors).to be_a(Hash)
      expect(service.node_executors.keys).to include(
        'ai_agent', 'api_call', 'condition', 'loop', 'webhook'
      )
    end

    it 'initializes without a workflow' do
      service_without_workflow = described_class.new(nil, account: account, user: user)
      expect(service_without_workflow.account).to eq(account)
      expect(service_without_workflow.user).to eq(user)
      expect(service_without_workflow.workflow).to be_nil
    end
  end

  describe '#execute_workflow' do
    let(:input_variables) { { topic: 'AI Technology', style: 'technical' } }

    before do
      allow_any_instance_of(Mcp::AiWorkflowOrchestrator).to receive(:execute).and_return(true)
    end

    it 'creates a new workflow run' do
      expect {
        service.execute_workflow(input_variables: input_variables)
      }.to change { workflow.ai_workflow_runs.count }.by(1)

      run = workflow.ai_workflow_runs.last
      expect(run.input_variables).to eq(input_variables.stringify_keys)
      expect(run.status).to be_in(['initializing', 'running', 'completed'])
    end

    it 'handles workflow failures gracefully' do
      allow_any_instance_of(Mcp::AiWorkflowOrchestrator).to receive(:execute)
        .and_raise(StandardError, 'API timeout')

      run = service.execute_workflow(input_variables: input_variables)

      expect(run.reload.status).to eq('failed')
      expect(run.error_details['error_message']).to include('API timeout')
    end
  end

  describe '#execute_node' do
    let(:run) { create(:ai_workflow_run, ai_workflow: workflow, account: account) }
    let(:start_node) { workflow.ai_workflow_nodes.find_by(node_type: 'start') }
    let(:end_node) { workflow.ai_workflow_nodes.find_by(node_type: 'end') }

    it 'creates node execution record for start node' do
      expect {
        service.execute_node(start_node, run, { input: 'test data' })
      }.to change { run.ai_workflow_node_executions.count }.by(1)

      execution = run.ai_workflow_node_executions.last
      expect(execution.ai_workflow_node).to eq(start_node)
    end

    it 'executes start nodes correctly' do
      execution = service.execute_node(start_node, run, { prompt: 'Test' })

      expect(execution.status).to eq('completed')
      expect(execution.output_data).to be_present
    end

    it 'executes end nodes correctly' do
      execution = service.execute_node(end_node, run, { result: 'done' })

      expect(execution.status).to eq('completed')
    end

    it 'tracks execution metrics' do
      start_time = Time.current
      execution = service.execute_node(start_node, run, { input: 'test' })

      expect(execution.started_at).to be >= start_time
    end
  end

  describe '#validate_workflow_structure' do
    it 'validates workflow has start and end nodes' do
      empty_workflow = create(:ai_workflow, account: account)
      empty_service = described_class.new(empty_workflow)

      result = empty_service.validate_workflow_structure

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(match(/start node/i))
    end

    it 'returns valid for properly structured workflows' do
      result = service.validate_workflow_structure

      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end

    it 'detects circular dependencies' do
      circular_workflow = create(:ai_workflow, account: account)
      node1 = create(:ai_workflow_node, :ai_agent, ai_workflow: circular_workflow)
      node2 = create(:ai_workflow_node, :transform, ai_workflow: circular_workflow)

      create(:ai_workflow_edge, ai_workflow: circular_workflow,
             source_node_id: node1.node_id, target_node_id: node2.node_id)
      create(:ai_workflow_edge, ai_workflow: circular_workflow,
             source_node_id: node2.node_id, target_node_id: node1.node_id)

      circular_service = described_class.new(circular_workflow)
      result = circular_service.validate_workflow_structure

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(match(/circular dependency/i))
    end
  end

  describe '#calculate_execution_path' do
    it 'calculates linear execution path' do
      path = service.calculate_execution_path

      expect(path).to be_an(Array)
      expect(path.first.node_type).to eq('start')
      expect(path.last.node_type).to eq('end')
    end
  end

  describe '#pause_execution' do
    let(:run) { create(:ai_workflow_run, :running, ai_workflow: workflow, account: account) }

    it 'cannot pause completed workflows' do
      completed_run = create(:ai_workflow_run, :completed, ai_workflow: workflow, account: account)

      expect {
        service.pause_execution(completed_run)
      }.to raise_error(StandardError, /cannot pause/i)
    end
  end

  describe '#resume_execution' do
    it 'cannot resume non-paused workflows' do
      running_run = create(:ai_workflow_run, :running, ai_workflow: workflow, account: account)

      expect {
        service.resume_execution(running_run)
      }.to raise_error(StandardError, /not paused/i)
    end
  end

  describe '#cancel_execution' do
    let(:run) { create(:ai_workflow_run, :running, ai_workflow: workflow, account: account) }

    it 'cancels running workflow execution' do
      service.cancel_execution(run)

      expect(run.reload.status).to eq('cancelled')
      expect(run.completed_at).to be_present
    end

    it 'stops all active node executions' do
      # Create separate nodes for each execution to avoid unique constraint violation
      3.times do
        node = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow)
        create(:ai_workflow_node_execution, :running, ai_workflow_run: run, ai_workflow_node: node)
      end

      service.cancel_execution(run)

      run.ai_workflow_node_executions.each do |execution|
        expect(execution.reload.status).to eq('cancelled')
      end
    end
  end

  describe '#execution_statistics' do
    let(:run) { create(:ai_workflow_run, :completed, ai_workflow: workflow, account: account) }

    before do
      # Create separate nodes for each execution to avoid unique constraint violation
      3.times do
        node = create(:ai_workflow_node, :ai_agent, ai_workflow: workflow)
        create(:ai_workflow_node_execution, :completed, ai_workflow_run: run, ai_workflow_node: node, cost: 0.25)
      end
      failed_node = create(:ai_workflow_node, :api_call, ai_workflow: workflow)
      create(:ai_workflow_node_execution, :failed, ai_workflow_run: run, ai_workflow_node: failed_node, cost: 0.05)
    end

    it 'calculates comprehensive execution statistics' do
      stats = service.execution_statistics(run)

      expect(stats[:total_nodes]).to eq(4)
      expect(stats[:completed_nodes]).to eq(3)
      expect(stats[:failed_nodes]).to eq(1)
      expect(stats[:success_rate]).to eq(75.0)
      expect(stats[:total_cost]).to eq(0.80)
      expect(stats[:total_tokens]).to be_a(Integer) # Estimated from cost
    end

    it 'includes performance metrics when requested' do
      stats = service.execution_statistics(run, include_performance: true)

      expect(stats[:average_node_execution_time]).to be_present
      expect(stats[:execution_efficiency_score]).to be_present
      expect(stats[:cost_per_token]).to be_present
    end
  end

  describe 'load balancing and provider selection' do
    let(:agent) { create(:ai_agent, account: account) }
    let(:provider1) { create(:ai_provider, account: account, name: 'OpenAI') }
    let(:provider2) { create(:ai_provider, account: account, name: 'Anthropic') }
    let(:orchestration_service) { described_class.new(nil, account: account, user: user) }

    describe '#balance_load_across_providers' do
      before do
        provider1
        provider2
      end

      it 'returns load metrics for providers' do
        load_metrics = orchestration_service.balance_load_across_providers

        expect(load_metrics).to be_an(Array)
        expect(load_metrics.length).to eq(2)

        metric = load_metrics.first
        expect(metric).to have_key(:provider)
        expect(metric).to have_key(:current_load)
        expect(metric).to have_key(:utilization)
      end
    end

    describe '#predict_and_scale_resources' do
      it 'returns scaling recommendations' do
        recommendations = orchestration_service.predict_and_scale_resources

        expect(recommendations[:immediate_actions]).to be_an(Array)
        expect(recommendations[:short_term_scaling]).to be_a(Hash)
        expect(recommendations[:long_term_planning]).to be_a(Hash)
      end
    end

    describe '#optimize_execution_parameters' do
      it 'returns optimization recommendations' do
        optimizations = orchestration_service.optimize_execution_parameters(
          agent, { prompt: 'Test' }
        )

        expect(optimizations[:provider_preferences]).to be_an(Array)
        expect(optimizations[:resource_allocation]).to be_a(Hash)
        expect(optimizations[:execution_settings]).to be_a(Hash)
        expect(optimizations[:cost_optimization]).to be_a(Hash)
      end
    end
  end

  describe 'monitoring' do
    let(:orchestration_service) { described_class.new(workflow, account: account, user: user) }

    before do
      create_list(:ai_agent_execution, 3, :queued, account: account)
      create_list(:ai_agent_execution, 2, :processing, account: account)
      create_list(:ai_agent_execution, 1, :completed, account: account)
    end

    describe '#monitor_executions' do
      it 'provides monitoring metrics' do
        metrics = orchestration_service.monitor_executions

        expect(metrics[:total_active]).to eq(5)
        expect(metrics[:by_status]).to be_a(Hash)
        expect(metrics[:resource_usage]).to be_a(Hash)
        expect(metrics[:performance_metrics]).to be_a(Hash)
      end
    end
  end

  describe 'workflow configuration validation' do
    let(:orchestration_service) { described_class.new(workflow, account: account, user: user) }

    describe '#orchestrate_workflow' do
      it 'validates workflow configuration before execution' do
        invalid_config = { 'name' => 'Invalid' }

        expect {
          orchestration_service.orchestrate_workflow(invalid_config)
        }.to raise_error(described_class::OrchestrationError, /Missing required workflow/)
      end

      it 'requires agents array in configuration' do
        config = { 'name' => 'Test', 'execution_order' => 'sequential' }

        expect {
          orchestration_service.orchestrate_workflow(config)
        }.to raise_error(described_class::OrchestrationError, /Missing required workflow/)
      end
    end
  end

  describe 'helper methods' do
    let(:orchestration_service) { described_class.new(workflow, account: account, user: user) }

    describe '#build_agent_prompt' do
      it 'builds prompt from configuration' do
        agent_config = { 'system_prompt' => 'You are helpful' }
        prompt = orchestration_service.send(:build_agent_prompt, agent_config, 'Hello')

        expect(prompt).to include('You are helpful')
        expect(prompt).to include('Hello')
      end

      it 'handles hash input data' do
        agent_config = { 'prompt' => 'Base prompt' }
        prompt = orchestration_service.send(:build_agent_prompt, agent_config, { key: 'value' })

        expect(prompt).to include('key: value')
      end
    end

    describe '#calculate_cost_from_usage' do
      it 'calculates cost for OpenAI' do
        usage = { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 }
        cost = orchestration_service.send(:calculate_cost_from_usage, usage, 'openai')

        expect(cost).to be > 0
      end

      it 'returns 0 for Ollama' do
        usage = { prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500 }
        cost = orchestration_service.send(:calculate_cost_from_usage, usage, 'ollama')

        expect(cost).to eq(0)
      end

      it 'handles nil usage' do
        cost = orchestration_service.send(:calculate_cost_from_usage, nil, 'openai')

        expect(cost).to eq(0.0)
      end
    end

    describe '#compile_workflow_output' do
      it 'compiles sequential workflow results' do
        results = [
          { 'agent_id' => 1, 'result' => 'first' },
          { 'agent_id' => 2, 'result' => 'second' }
        ]
        config = { 'execution_order' => 'sequential' }

        output = orchestration_service.send(:compile_workflow_output, results, config)

        expect(output['primary_output']).to eq('second')
        expect(output['all_results']).to eq(results)
        expect(output['execution_summary']['success']).to be true
      end

      it 'compiles parallel workflow results' do
        results = [
          { 'agent_id' => 1, 'result' => 'one' },
          { 'agent_id' => 2, 'result' => 'two' }
        ]
        config = { 'execution_order' => 'parallel' }

        output = orchestration_service.send(:compile_workflow_output, results, config)

        expect(output['results']).to eq(results)
        expect(output['execution_summary']['total_executions']).to eq(2)
      end

      it 'handles empty results' do
        output = orchestration_service.send(:compile_workflow_output, [], {})

        expect(output).to eq({})
      end
    end

    describe '#should_execute_asynchronously?' do
      it 'returns true for ai_agent nodes' do
        expect(orchestration_service.send(:should_execute_asynchronously?, 'ai_agent')).to be true
      end

      it 'returns true for api_call nodes' do
        expect(orchestration_service.send(:should_execute_asynchronously?, 'api_call')).to be true
      end

      it 'returns false for simple nodes' do
        expect(orchestration_service.send(:should_execute_asynchronously?, 'simple')).to be false
      end
    end
  end

  describe 'workflow condition evaluation' do
    let(:orchestration_service) { described_class.new(workflow, account: account, user: user) }

    describe '#evaluate_workflow_condition' do
      it 'returns true for present conditions' do
        result = orchestration_service.send(:evaluate_workflow_condition, { 'expression' => 'true' })
        expect(result).to be true
      end

      it 'returns false for blank conditions' do
        result = orchestration_service.send(:evaluate_workflow_condition, {})
        expect(result).to be false
      end
    end
  end
end
