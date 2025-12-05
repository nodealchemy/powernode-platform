# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentOrchestrationService, type: :service do
  include AiOrchestrationTestHelpers

  # Timeout protection to prevent infinite loops in workflow execution
  # This spec file tests async workflow execution which can hang if loop logic is broken
  around(:each) do |example|
    Timeout.timeout(30) do  # 30 seconds max per test
      example.run
    end
  rescue Timeout::Error
    fail "Test exceeded 30 second timeout - likely infinite loop in workflow execution (see line 108 'processes loops correctly')"
  end

  let(:account) { create(:account) }
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
  end

  describe '#execute_workflow' do
    let(:input_variables) { { topic: 'AI Technology', style: 'technical' } }
    
    before do
      # Mock AI provider responses
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
        .and_return({
          success: true,
          data: {
            choices: [{ 
              message: { content: 'Generated AI content based on the topic' } 
            }],
            usage: { prompt_tokens: 150, completion_tokens: 200, total_tokens: 350 },
            model: 'gpt-4'
          },
          provider: 'OpenAI'
        })
    end

    it 'creates a new workflow run' do
      expect {
        service.execute_workflow(input_variables: input_variables)
      }.to change { workflow.runs.count }.by(1)
      
      run = workflow.runs.last
      expect(run.input_variables).to eq(input_variables.stringify_keys)
      expect(run.status).to be_in(['running', 'completed'])
    end

    it 'executes workflow nodes in correct order' do
      run = service.execute_workflow(input_variables: input_variables)
      
      
      # Should create node executions for each node in the workflow
      expect(run.node_executions.count).to be > 0
      
      # Should execute nodes according to the workflow graph
      first_execution = run.node_executions.order(:created_at).first
      expect(first_execution.ai_workflow_node.node_type).to eq('start')
    end

    it 'propagates data between connected nodes' do
      run = service.execute_workflow(input_variables: input_variables)
      
      # Wait for execution to complete
      run.reload
      
      # Should have output data from AI agent nodes
      ai_executions = run.node_executions.joins(:ai_workflow_node)
                        .where(ai_workflow_nodes: { node_type: 'ai_agent' })
      
      expect(ai_executions.any? { |exec| exec.output_data.present? }).to be true
    end

    it 'handles conditional branching correctly' do
      # Create workflow with conditional nodes
      condition_workflow = create(:ai_workflow, :with_conditional_branch, account: account)
      condition_service = described_class.new(condition_workflow)
      
      run = condition_service.execute_workflow(
        input_variables: { score: 0.9, threshold: 0.8 }
      )
      
      # Should follow the success branch when condition is met
      condition_executions = run.node_executions.joins(:ai_workflow_node)
                               .where(ai_workflow_nodes: { node_type: 'condition' })
      
      expect(condition_executions.first.output_data['condition_result']).to be true
    end

    it 'processes loops correctly' do
      # Create workflow with loop nodes
      loop_workflow = create(:ai_workflow, :with_loop, account: account)
      loop_service = described_class.new(loop_workflow)
      
      run = loop_service.execute_workflow(
        input_variables: { items: ['item1', 'item2', 'item3'] }
      )
      
      # Should execute loop body for each item
      loop_executions = run.node_executions.joins(:ai_workflow_node)
                          .where(ai_workflow_nodes: { node_type: 'loop' })
      
      expect(loop_executions.count).to be >= 1
      expect(loop_executions.first.output_data['iterations_completed']).to eq(3)
    end

    it 'marks workflow as completed when finished' do
      run = service.execute_workflow(input_variables: input_variables)
      
      # Wait for async execution to complete
      sleep(0.1) while run.reload.status == 'running'
      
      expect(run.status).to eq('completed')
      expect(run.completed_at).to be_present
      expect(run.output_data).to be_present
    end

    it 'handles workflow failures gracefully' do
      # Mock API failure
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
        .and_raise(StandardError, 'API timeout')
      
      run = service.execute_workflow(input_variables: input_variables)
      
      # Should mark run as failed
      expect(run.reload.status).to eq('failed')
      expect(run.error_message).to include('API timeout')
    end

    it 'respects workflow timeout settings' do
      workflow.update!(timeout_minutes: 0.01) # 0.6 seconds
      
      # Mock slow execution
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text) do
        sleep(1)
        {
          success: true,
          data: {
            choices: [{ message: { content: 'response' } }],
            usage: { prompt_tokens: 50, completion_tokens: 50, total_tokens: 100 },
            model: 'gpt-4'
          },
          provider: 'OpenAI'
        }
      end
      
      run = service.execute_workflow(input_variables: input_variables)
      
      expect(run.reload.status).to eq('timeout')
    end
  end

  describe '#execute_node' do
    let(:run) { create(:ai_workflow_run, ai_workflow: workflow) }
    let(:ai_node) { create(:ai_workflow_node, :ai_agent, ai_workflow: workflow) }
    
    before do
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
        .and_return({
          success: true,
          data: {
            choices: [{ message: { content: 'AI generated response' } }],
            usage: { prompt_tokens: 100, completion_tokens: 150, total_tokens: 250 },
            model: 'gpt-4'
          },
          provider: 'OpenAI'
        })
    end

    it 'creates node execution record' do
      expect {
        service.execute_node(ai_node, run, { input: 'test data' })
      }.to change { run.node_executions.count }.by(1)
      
      execution = run.node_executions.last
      expect(execution.ai_workflow_node).to eq(ai_node)
      expect(execution.status).to eq('completed')
    end

    it 'executes AI agent nodes correctly' do
      execution = service.execute_node(ai_node, run, { prompt: 'Generate content about AI' })
      
      expect(execution.output_data['content']).to eq('AI generated response')
      expect(execution.tokens_consumed).to eq(100)
      expect(execution.tokens_generated).to eq(150)
    end

    it 'handles API call nodes' do
      api_node = create(:ai_workflow_node, :api_call, ai_workflow: workflow)
      
      # Mock HTTP response
      stub_request(:get, api_node.configuration['url'])
        .to_return(status: 200, body: { result: 'success' }.to_json)
      
      execution = service.execute_node(api_node, run, {})
      
      expect(execution.output_data['response']).to include('result' => 'success')
      expect(execution.status).to eq('completed')
    end

    it 'handles webhook nodes' do
      webhook_node = create(:ai_workflow_node, :webhook, ai_workflow: workflow)
      
      # Mock webhook delivery
      stub_request(:post, webhook_node.configuration['url'])
        .to_return(status: 200, body: 'OK')
      
      execution = service.execute_node(webhook_node, run, { data: 'test payload' })
      
      expect(execution.output_data['webhook_delivered']).to be true
      expect(execution.status).to eq('completed')
    end

    it 'evaluates condition nodes' do
      condition_node = create(:ai_workflow_node, :condition, ai_workflow: workflow,
                             configuration: {
                               condition: 'input.score > 0.8',
                               true_path: 'success_node',
                               false_path: 'failure_node'
                             })
      
      execution = service.execute_node(condition_node, run, { score: 0.9 })
      
      expect(execution.output_data['condition_result']).to be true
      expect(execution.output_data['next_path']).to eq('success_node')
    end

    it 'processes transform nodes' do
      transform_node = create(:ai_workflow_node, :transform, ai_workflow: workflow,
                             configuration: {
                               script: 'output.upper_text = input.text.toUpperCase();'
                             })
      
      execution = service.execute_node(transform_node, run, { text: 'hello world' })
      
      expect(execution.output_data['upper_text']).to eq('HELLO WORLD')
    end

    it 'handles human approval nodes' do
      approval_node = create(:ai_workflow_node, :human_approval, ai_workflow: workflow)
      
      execution = service.execute_node(approval_node, run, { content: 'Please review this' })
      
      expect(execution.status).to eq('pending')
      expect(execution.output_data['approval_required']).to be true
      expect(execution.output_data['approval_url']).to be_present
    end

    it 'tracks execution metrics' do
      start_time = Time.current
      execution = service.execute_node(ai_node, run, { input: 'test' })
      
      expect(execution.started_at).to be >= start_time
      expect(execution.completed_at).to be > execution.started_at
      expect(execution.duration).to be > 0
    end

    it 'handles node execution failures' do
      # Mock API failure
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
        .and_raise(StandardError, 'Node execution failed')
      
      execution = service.execute_node(ai_node, run, { input: 'test' })
      
      expect(execution.status).to eq('failed')
      expect(execution.error_message).to include('Node execution failed')
    end

    it 'applies retry logic for failed nodes' do
      ai_node.update!(configuration: ai_node.configuration.merge(max_retries: 3))
      
      call_count = 0
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text) do
        call_count += 1
        if call_count < 3
          raise StandardError, 'Temporary failure'
        else
          {
            success: true,
            data: {
              choices: [{ message: { content: 'Success after retry' } }],
              usage: { prompt_tokens: 50, completion_tokens: 50, total_tokens: 100 },
              model: 'gpt-4'
            },
            provider: 'OpenAI'
          }
        end
      end
      
      execution = service.execute_node(ai_node, run, { input: 'test' })
      
      expect(execution.status).to eq('completed')
      expect(execution.retry_count).to eq(2)
      expect(execution.output_data['content']).to eq('Success after retry')
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

    it 'validates node connections' do
      # Create workflow with disconnected nodes
      disconnected_workflow = create(:ai_workflow, account: account)
      create(:ai_workflow_node, :start, ai_workflow: disconnected_workflow)
      create(:ai_workflow_node, :ai_agent, ai_workflow: disconnected_workflow)
      create(:ai_workflow_node, :end, ai_workflow: disconnected_workflow)
      # No edges connecting the nodes
      
      disconnected_service = described_class.new(disconnected_workflow)
      result = disconnected_service.validate_workflow_structure
      
      expect(result[:valid]).to be false
      expect(result[:errors]).to include(match(/disconnected nodes/i))
    end

    it 'detects circular dependencies' do
      # Create workflow with circular reference
      circular_workflow = create(:ai_workflow, account: account)
      node1 = create(:ai_workflow_node, :ai_agent, ai_workflow: circular_workflow)
      node2 = create(:ai_workflow_node, :transform, ai_workflow: circular_workflow)
      
      create(:ai_workflow_edge, ai_workflow: circular_workflow, source_node: node1, target_node: node2)
      create(:ai_workflow_edge, ai_workflow: circular_workflow, source_node: node2, target_node: node1)
      
      circular_service = described_class.new(circular_workflow)
      result = circular_service.validate_workflow_structure
      
      expect(result[:valid]).to be false
      expect(result[:errors]).to include(match(/circular dependency/i))
    end

    it 'validates required node configurations' do
      incomplete_workflow = create(:ai_workflow, account: account)
      incomplete_node = create(:ai_workflow_node, :ai_agent, 
                              ai_workflow: incomplete_workflow,
                              configuration: {}) # Missing required config
      
      incomplete_service = described_class.new(incomplete_workflow)
      result = incomplete_service.validate_workflow_structure
      
      expect(result[:valid]).to be false
      expect(result[:errors]).to include(match(/configuration/i))
    end

    it 'returns valid for properly structured workflows' do
      result = service.validate_workflow_structure
      
      expect(result[:valid]).to be true
      expect(result[:errors]).to be_empty
    end
  end

  describe '#calculate_execution_path' do
    it 'calculates linear execution path' do
      path = service.calculate_execution_path
      
      expect(path).to be_an(Array)
      expect(path.first.node_type).to eq('start')
      expect(path.last.node_type).to eq('end')
    end

    it 'handles conditional branching in path calculation' do
      condition_workflow = create(:ai_workflow, :with_conditional_branch, account: account)
      condition_service = described_class.new(condition_workflow)
      
      true_path = condition_service.calculate_execution_path(condition_result: true)
      false_path = condition_service.calculate_execution_path(condition_result: false)
      
      expect(true_path).not_to eq(false_path)
    end

    it 'expands loop iterations in path' do
      loop_workflow = create(:ai_workflow, :with_loop, account: account)
      loop_service = described_class.new(loop_workflow)
      
      path = loop_service.calculate_execution_path(loop_iterations: 3)
      
      # Should include multiple iterations of loop body
      loop_nodes = path.select { |node| node.node_type == 'loop' }
      expect(loop_nodes.count).to be >= 3
    end
  end

  describe '#pause_execution' do
    let(:run) { create(:ai_workflow_run, :running, ai_workflow: workflow) }

    it 'pauses running workflow execution' do
      service.pause_execution(run)
      
      expect(run.reload.status).to eq('paused')
      expect(run.paused_at).to be_present
    end

    it 'creates pause checkpoint for resumption' do
      service.pause_execution(run)
      
      expect(run.checkpoint_data).to be_present
      expect(run.checkpoint_data['execution_state']).to be_present
    end

    it 'cannot pause completed workflows' do
      completed_run = create(:ai_workflow_run, :completed, ai_workflow: workflow)
      
      expect {
        service.pause_execution(completed_run)
      }.to raise_error(StandardError, /cannot pause/i)
    end
  end

  describe '#resume_execution' do
    let(:paused_run) { create(:ai_workflow_run, status: 'paused', 
                             checkpoint_data: { 
                               execution_state: 'node_completed',
                               current_node_id: workflow.nodes.first.id
                             }) }

    it 'resumes paused workflow execution' do
      service.resume_execution(paused_run)
      
      expect(paused_run.reload.status).to eq('running')
      expect(paused_run.resumed_at).to be_present
    end

    it 'restores execution context from checkpoint' do
      allow(service).to receive(:execute_from_checkpoint)
      
      service.resume_execution(paused_run)
      
      expect(service).to have_received(:execute_from_checkpoint)
        .with(hash_including(execution_state: 'node_completed'))
    end

    it 'cannot resume non-paused workflows' do
      running_run = create(:ai_workflow_run, :running, ai_workflow: workflow)
      
      expect {
        service.resume_execution(running_run)
      }.to raise_error(StandardError, /not paused/i)
    end
  end

  describe '#cancel_execution' do
    let(:run) { create(:ai_workflow_run, :running, ai_workflow: workflow) }

    it 'cancels running workflow execution' do
      service.cancel_execution(run)
      
      expect(run.reload.status).to eq('cancelled')
      expect(run.completed_at).to be_present
    end

    it 'stops all active node executions' do
      # Create running node executions
      create_list(:ai_workflow_node_execution, 3, :running, ai_workflow_run: run)
      
      service.cancel_execution(run)
      
      run.node_executions.each do |execution|
        expect(execution.reload.status).to eq('cancelled')
      end
    end

    it 'logs cancellation reason' do
      expect {
        service.cancel_execution(run, reason: 'User requested cancellation')
      }.to change { AiWorkflowExecutionLog.count }.by(1)
      
      log = AiWorkflowExecutionLog.last
      expect(log.message).to include('cancelled')
      expect(log.log_data['reason']).to eq('User requested cancellation')
    end
  end

  describe '#execution_statistics' do
    let(:run) { create(:ai_workflow_run, :completed, ai_workflow: workflow) }

    before do
      create_list(:ai_workflow_node_execution, 3, :completed, 
                 ai_workflow_run: run, cost: 0.25, tokens_consumed: 100)
      create_list(:ai_workflow_node_execution, 1, :failed,
                 ai_workflow_run: run, cost: 0.05, tokens_consumed: 50)
    end

    it 'calculates comprehensive execution statistics' do
      stats = service.execution_statistics(run)
      
      expect(stats[:total_nodes]).to eq(4)
      expect(stats[:completed_nodes]).to eq(3)
      expect(stats[:failed_nodes]).to eq(1)
      expect(stats[:success_rate]).to eq(0.75)
      expect(stats[:total_cost]).to eq(0.80)
      expect(stats[:total_tokens]).to eq(350)
    end

    it 'includes performance metrics' do
      stats = service.execution_statistics(run, include_performance: true)
      
      expect(stats[:average_node_execution_time]).to be_present
      expect(stats[:execution_efficiency_score]).to be_present
      expect(stats[:cost_per_token]).to be_present
    end
  end

  describe 'error handling and recovery' do
    it 'handles provider unavailability gracefully' do
      ai_provider.update!(is_active: false)
      
      run = service.execute_workflow(input_variables: { test: 'data' })
      
      expect(run.reload.status).to eq('failed')
      expect(run.error_message).to include('provider not available')
    end

    it 'implements circuit breaker for failing providers' do
      # Mock repeated failures
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
        .and_raise(StandardError, 'Provider unavailable')
      
      # Execute multiple workflows to trigger circuit breaker
      5.times { service.execute_workflow(input_variables: { test: 'data' }) }
      
      # Should open circuit breaker
      expect(service.circuit_breaker_open?).to be true
    end

    it 'handles memory pressure during large workflows' do
      # Create workflow with many nodes
      large_workflow = create(:ai_workflow, account: account)
      100.times { create(:ai_workflow_node, :ai_agent, ai_workflow: large_workflow) }
      
      large_service = described_class.new(large_workflow)
      
      expect {
        large_service.execute_workflow(input_variables: { test: 'data' })
      }.not_to raise_error
    end

    it 'recovers from temporary database connection issues' do
      # Mock database connection failure
      allow(ActiveRecord::Base).to receive(:connection)
        .and_raise(ActiveRecord::ConnectionNotEstablished).once
        .then.call_original
      
      expect {
        service.execute_workflow(input_variables: { test: 'data' })
      }.not_to raise_error
    end
  end

  describe 'performance optimization' do
    it 'caches workflow structure for repeated executions' do
      # First execution should build cache
      service.execute_workflow(input_variables: { test: 'data' })

      # Second execution should use cache
      expect(service).to receive(:load_cached_workflow_structure)
      service.execute_workflow(input_variables: { test: 'data2' })
    end

    it 'parallelizes independent node executions' do
      parallel_workflow = create(:ai_workflow, :with_parallel_execution, account: account)
      parallel_service = described_class.new(parallel_workflow)

      start_time = Time.current
      run = parallel_service.execute_workflow(input_variables: { test: 'data' })
      execution_time = Time.current - start_time

      # Parallel execution should be faster than sequential
      expect(execution_time).to be < 5.seconds
      expect(run.node_executions.count).to be > 1
    end

    it 'implements smart batching for API calls' do
      # Create workflow with multiple AI agent nodes
      batch_workflow = create(:ai_workflow, account: account)
      5.times { create(:ai_workflow_node, :ai_agent, ai_workflow: batch_workflow) }

      batch_service = described_class.new(batch_workflow)

      # Should batch compatible API calls
      expect_any_instance_of(AiProviderClientService).to receive(:batch_completion)
        .at_least(:once)

      batch_service.execute_workflow(input_variables: { test: 'data' })
    end
  end

  describe 'load balancing and provider selection' do
    let(:user) { create(:user, account: account) }
    let(:agent) { create(:ai_agent, account: account) }
    let(:provider1) { create(:ai_provider, account: account, name: 'OpenAI') }
    let(:provider2) { create(:ai_provider, account: account, name: 'Anthropic') }
    let(:provider3) { create(:ai_provider, account: account, name: 'Local Ollama') }
    let(:orchestration_service) { described_class.new(nil, account: account, user: user) }

    before do
      # Set up providers with different load characteristics
      allow(orchestration_service).to receive(:calculate_provider_current_load)
        .with(provider1).and_return(2)
      allow(orchestration_service).to receive(:calculate_provider_current_load)
        .with(provider2).and_return(8)
      allow(orchestration_service).to receive(:calculate_provider_current_load)
        .with(provider3).and_return(1)

      allow(orchestration_service).to receive(:calculate_provider_success_rate)
        .with(provider1).and_return(95.0)
      allow(orchestration_service).to receive(:calculate_provider_success_rate)
        .with(provider2).and_return(98.0)
      allow(orchestration_service).to receive(:calculate_provider_success_rate)
        .with(provider3).and_return(88.0)

      allow(orchestration_service).to receive(:calculate_provider_avg_response_time)
        .with(provider1).and_return(1200)
      allow(orchestration_service).to receive(:calculate_provider_avg_response_time)
        .with(provider2).and_return(800)
      allow(orchestration_service).to receive(:calculate_provider_avg_response_time)
        .with(provider3).and_return(2000)

      # Mock agent compatibility
      allow(agent).to receive(:compatible_providers).and_return([provider1, provider2, provider3])
    end

    describe '#execute_agent_with_orchestration' do
      it 'selects optimal provider based on multi-factor scoring' do
        execution = orchestration_service.execute_agent_with_orchestration(
          agent, { prompt: 'Test execution' }
        )

        # Should select provider2 (Anthropic) due to high success rate and low response time
        expect(execution.ai_provider).to eq(provider2)
        expect(execution.status).to eq('queued')
        expect(execution.metadata['selected_provider']).to eq('Anthropic')
      end

      it 'enforces resource limits during provider selection' do
        # Mock account at limit
        allow(account).to receive_message_chain(:ai_agent_executions, :where, :count).and_return(10)
        allow(account).to receive_message_chain(:subscription, :ai_execution_limit).and_return(10)

        expect {
          orchestration_service.execute_agent_with_orchestration(agent, { prompt: 'Test' })
        }.to raise_error(described_class::ResourceLimitError, /concurrent execution limit/)
      end

      it 'enforces provider-specific limits' do
        # Mock provider at capacity
        allow(provider1).to receive_message_chain(:ai_agent_executions, :where, :count).and_return(10)
        provider1.metadata = { 'max_concurrent' => 10 }

        allow(orchestration_service).to receive(:select_optimal_provider).and_return(provider1)

        expect {
          orchestration_service.execute_agent_with_orchestration(agent, { prompt: 'Test' })
        }.to raise_error(described_class::ResourceLimitError, /Provider.*concurrent execution limit/)
      end

      it 'calculates execution priority correctly' do
        # Premium account user
        allow(account).to receive_message_chain(:subscription, :premium?).and_return(true)
        agent.update!(agent_type: 'real_time')

        execution = orchestration_service.execute_agent_with_orchestration(
          agent, { prompt: 'Test' }, workflow_context: workflow
        )

        # Should have high priority (premium + real_time + workflow = 5 + 2 + 1 + 1 = 9)
        expect(execution.metadata['execution_priority']).to be >= 8
      end

      it 'updates orchestration metrics after execution' do
        expect(Rails.cache).to receive(:increment).with("orchestration:executions:#{account.id}", 1)
        expect(Rails.cache).to receive(:increment).with(/orchestration:provider_usage/, 1)
        expect(Rails.cache).to receive(:write).with(/orchestration:last_activity/, anything, anything)

        orchestration_service.execute_agent_with_orchestration(agent, { prompt: 'Test' })
      end
    end

    describe '#balance_load_across_providers' do
      it 'calculates accurate load metrics for each provider' do
        load_metrics = orchestration_service.balance_load_across_providers

        expect(load_metrics).to be_an(Array)
        expect(load_metrics.length).to eq(3)

        provider1_metrics = load_metrics.find { |m| m[:provider] == provider1 }
        expect(provider1_metrics[:current_load]).to eq(2)
        expect(provider1_metrics[:utilization]).to eq(20.0) # 2/10 * 100
        expect(provider1_metrics[:success_rate]).to eq(95.0)
      end

      it 'identifies providers at capacity' do
        allow(orchestration_service).to receive(:calculate_provider_current_load)
          .with(provider2).and_return(10)
        provider2.metadata = { 'max_concurrent' => 10 }

        load_metrics = orchestration_service.balance_load_across_providers

        provider2_metrics = load_metrics.find { |m| m[:provider] == provider2 }
        expect(provider2_metrics[:utilization]).to eq(100.0)
        expect(provider2_metrics[:status]).to eq('at_capacity')
      end

      it 'triggers rebalancing when utilization is uneven' do
        expect(orchestration_service).to receive(:rebalance_executions_if_needed)

        orchestration_service.balance_load_across_providers
      end
    end

    describe '#predict_and_scale_resources' do
      it 'analyzes usage patterns and predicts future load' do
        allow(orchestration_service).to receive(:analyze_usage_patterns)
          .and_return(
            peak_hours: [9, 10, 11, 14, 15, 16],
            avg_executions_per_hour: 25,
            growth_trend: 1.15
          )

        scaling_recommendations = orchestration_service.predict_and_scale_resources

        expect(scaling_recommendations[:immediate_actions]).to be_an(Array)
        expect(scaling_recommendations[:short_term_scaling]).to be_a(Hash)
        expect(scaling_recommendations[:long_term_planning]).to be_a(Hash)
      end

      it 'applies auto-scaling when enabled' do
        allow(orchestration_service).to receive(:auto_scaling_enabled?).and_return(true)
        allow(orchestration_service).to receive(:analyze_usage_patterns).and_return({})
        allow(orchestration_service).to receive(:predict_future_load).and_return({})
        allow(orchestration_service).to receive(:generate_immediate_actions)
          .and_return(['scale_up_provider_1', 'enable_provider_fallback'])

        expect(orchestration_service).to receive(:apply_auto_scaling)
          .with(['scale_up_provider_1', 'enable_provider_fallback'])

        orchestration_service.predict_and_scale_resources
      end
    end

    describe '#optimize_execution_parameters' do
      it 'analyzes historical performance to recommend optimizations' do
        allow(orchestration_service).to receive(:analyze_historical_performance)
          .with(agent)
          .and_return(
            avg_response_time: { provider1.id => 1200, provider2.id => 800 },
            success_rates: { provider1.id => 95.0, provider2.id => 98.0 },
            cost_efficiency: { provider1.id => 0.002, provider2.id => 0.003 }
          )

        optimizations = orchestration_service.optimize_execution_parameters(
          agent, { prompt: 'Test optimization' }
        )

        expect(optimizations[:provider_preferences]).to include(provider2.id)
        expect(optimizations[:resource_allocation]).to be_a(Hash)
        expect(optimizations[:execution_settings]).to be_a(Hash)
        expect(optimizations[:cost_optimization]).to be_a(Hash)
      end

      it 'recommends cost-optimized providers when requested' do
        optimizations = orchestration_service.optimize_execution_parameters(
          agent, { prompt: 'Test' }, optimize_for_cost: true
        )

        expect(optimizations[:cost_optimization]).to include(:cost_factor)
      end
    end
  end

  describe 'real-time monitoring and broadcasting' do
    let(:user) { create(:user, account: account) }
    let(:orchestration_service) { described_class.new(workflow, account: account, user: user) }
    let(:workflow_execution) { create(:ai_workflow_execution, account: account, user: user) }

    before do
      # Mock ActionCable broadcasting
      allow(ActionCable.server).to receive(:broadcast)
    end

    describe '#monitor_executions' do
      before do
        create_list(:ai_agent_execution, 3, :queued, account: account)
        create_list(:ai_agent_execution, 2, :processing, account: account)
        create_list(:ai_agent_execution, 1, :completed, account: account)
      end

      it 'provides comprehensive monitoring metrics' do
        metrics = orchestration_service.monitor_executions

        expect(metrics[:total_active]).to eq(5)
        expect(metrics[:by_status]).to include('queued' => 3, 'processing' => 2)
        expect(metrics[:resource_usage]).to be_a(Hash)
        expect(metrics[:performance_metrics]).to be_a(Hash)
      end

      it 'checks for stuck executions and resource constraints' do
        expect(orchestration_service).to receive(:check_for_stuck_executions)
        expect(orchestration_service).to receive(:check_resource_constraints)

        orchestration_service.monitor_executions
      end

      it 'groups metrics by provider for load analysis' do
        metrics = orchestration_service.monitor_executions

        expect(metrics[:by_provider]).to be_a(Hash)
      end
    end

    describe 'workflow broadcasting' do
      it 'broadcasts workflow progress updates' do
        expect(ActionCable.server).to receive(:broadcast)
          .with("ai_orchestration_#{account.id}", hash_including(
            type: 'workflow_progress',
            workflow_id: workflow_execution.id
          ))

        orchestration_service.send(:broadcast_workflow_update, workflow_execution, {
          type: 'workflow_progress',
          message: 'Processing step 1/3'
        })
      end

      it 'broadcasts to both account and user channels' do
        expect(ActionCable.server).to receive(:broadcast)
          .with("ai_orchestration_#{account.id}", anything)
        expect(ActionCable.server).to receive(:broadcast)
          .with("ai_orchestration_user_#{user.id}", anything)

        orchestration_service.send(:broadcast_workflow_update, workflow_execution)
      end

      it 'includes comprehensive status information' do
        workflow_execution.update!(
          status: 'running',
          metadata: { 'progress_percentage' => 45 }
        )

        expect(ActionCable.server).to receive(:broadcast) do |channel, data|
          expect(data[:status]).to eq('running')
          expect(data[:progress]).to eq(45)
          expect(data[:metadata]).to include('progress_percentage' => 45)
          expect(data[:timestamp]).to be_present
        end

        orchestration_service.send(:broadcast_workflow_update, workflow_execution)
      end

      it 'handles broadcasting errors gracefully' do
        allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, 'Broadcast failed')

        expect {
          orchestration_service.send(:broadcast_workflow_update, workflow_execution)
        }.not_to raise_error
      end
    end

    describe '#broadcast_agent_status' do
      let(:agent) { create(:ai_agent, account: account) }

      it 'broadcasts agent status updates' do
        status_data = {
          current_executions: 2,
          success_rate: 95.0,
          avg_response_time: 1200
        }

        expect(ActionCable.server).to receive(:broadcast)
          .with("ai_orchestration_#{account.id}", hash_including(
            type: 'agent_status_update',
            agent_id: agent.id,
            status: status_data
          ))

        orchestration_service.send(:broadcast_agent_status, agent, status_data)
      end
    end

    describe '#broadcast_system_metrics' do
      before do
        allow_any_instance_of(AiAnalyticsInsightsService).to receive(:real_time_metrics)
          .and_return({
            active_executions: 5,
            success_rate: 94.5,
            avg_response_time: 1150,
            provider_health: 'good'
          })
      end

      it 'broadcasts system-wide metrics' do
        expect(ActionCable.server).to receive(:broadcast)
          .with("ai_orchestration_#{account.id}", hash_including(
            type: 'system_metrics_update',
            metrics: hash_including(:active_executions, :success_rate)
          ))

        orchestration_service.send(:broadcast_system_metrics)
      end

      it 'handles analytics service failures gracefully' do
        allow_any_instance_of(AiAnalyticsInsightsService).to receive(:real_time_metrics)
          .and_raise(StandardError, 'Analytics unavailable')

        expect {
          orchestration_service.send(:broadcast_system_metrics)
        }.not_to raise_error
      end
    end

    describe '#get_agent_status' do
      let(:agent) { create(:ai_agent, account: account) }

      before do
        create_list(:ai_agent_execution, 2, :processing, ai_agent: agent, account: account)
        create_list(:ai_agent_execution, 3, :completed, ai_agent: agent, account: account,
                   created_at: 30.minutes.ago, duration_ms: 1500)
      end

      it 'provides detailed agent status information' do
        status = orchestration_service.send(:get_agent_status, agent.id, account.id)

        expect(status[:agent_id]).to eq(agent.id)
        expect(status[:current_executions]).to eq(2)
        expect(status[:status]).to eq('active')
        expect(status[:recent_success_rate]).to be_present
        expect(status[:avg_response_time]).to eq(1500)
      end

      it 'returns nil for unauthorized account access' do
        other_account = create(:account)
        status = orchestration_service.send(:get_agent_status, agent.id, other_account.id)

        expect(status).to be_nil
      end

      it 'calculates accurate success rates for recent executions' do
        # Add some failed executions
        create_list(:ai_agent_execution, 1, :failed, ai_agent: agent, account: account,
                   created_at: 45.minutes.ago)

        status = orchestration_service.send(:get_agent_status, agent.id, account.id)

        expect(status[:recent_success_rate]).to eq(75.0) # 3 success out of 4 total
      end
    end
  end

  describe 'advanced workflow orchestration' do
    let(:user) { create(:user, account: account) }
    let(:orchestration_service) { described_class.new(workflow, account: account, user: user) }

    describe '#orchestrate_workflow' do
      let(:workflow_config) do
        {
          'name' => 'Test Multi-Agent Workflow',
          'execution_order' => 'sequential',
          'agents' => [
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Analyze this data' } },
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Generate summary' } }
          ]
        }
      end

      before do
        allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
          .and_return({
            success: true,
            data: {
              choices: [{ message: { content: 'AI response' } }],
              usage: { prompt_tokens: 100, completion_tokens: 150, total_tokens: 250 },
              model: 'gpt-4'
            },
            provider: 'OpenAI'
          })
      end

      it 'validates workflow configuration before execution' do
        invalid_config = { 'name' => 'Invalid' } # Missing required fields

        expect {
          orchestration_service.orchestrate_workflow(invalid_config)
        }.to raise_error(described_class::OrchestrationError, /Missing required workflow/)
      end

      it 'creates workflow execution record with proper metadata' do
        execution = orchestration_service.orchestrate_workflow(workflow_config)

        expect(execution).to be_an(AiWorkflowExecution)
        expect(execution.name).to eq('Test Multi-Agent Workflow')
        expect(execution.configuration).to eq(workflow_config)
        expect(execution.account).to eq(account)
        expect(execution.user).to eq(user)
      end

      it 'broadcasts workflow status updates during execution' do
        expect(AiExecutionStatusChannel).to receive(:broadcast_workflow_status).at_least(:twice)

        orchestration_service.orchestrate_workflow(workflow_config)
      end

      it 'handles workflow execution failures with proper error reporting' do
        allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
          .and_raise(StandardError, 'Provider failure')

        expect {
          orchestration_service.orchestrate_workflow(workflow_config)
        }.to raise_error(described_class::OrchestrationError, /Workflow execution failed/)
      end
    end

    describe 'sequential workflow execution' do
      let(:sequential_config) do
        {
          'name' => 'Sequential Test',
          'execution_order' => 'sequential',
          'agents' => [
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Step 1' } },
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Step 2: {{previous_output}}' } },
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Step 3: Final summary' } }
          ]
        }
      end

      it 'executes agents in correct sequential order' do
        execution_order = []
        allow(orchestration_service).to receive(:execute_agent_with_orchestration) do |agent, input, options|
          execution_order << options[:step_index]
          double('execution', id: SecureRandom.uuid, reload: double(output_data: { result: 'completed' }))
        end

        orchestration_service.send(:execute_sequential_workflow,
          create(:ai_workflow_execution), sequential_config)

        expect(execution_order).to eq([0, 1, 2])
      end

      it 'waits for each step completion before proceeding' do
        expect(orchestration_service).to receive(:wait_for_execution_completion).exactly(3).times

        orchestration_service.send(:execute_sequential_workflow,
          create(:ai_workflow_execution), sequential_config)
      end

      it 'propagates output data between sequential steps' do
        step_inputs = []
        allow(orchestration_service).to receive(:execute_agent_with_orchestration) do |agent, input|
          step_inputs << input
          double('execution', id: SecureRandom.uuid, reload: double(output_data: { result: "Step #{step_inputs.length} output" }))
        end

        orchestration_service.send(:execute_sequential_workflow,
          create(:ai_workflow_execution), sequential_config)

        expect(step_inputs[1]).to include(previous_results: anything)
      end

      it 'tracks progress percentage during execution' do
        workflow_execution = create(:ai_workflow_execution)

        allow(orchestration_service).to receive(:execute_agent_with_orchestration) do
          double('execution', id: SecureRandom.uuid, reload: double(output_data: {}))
        end

        orchestration_service.send(:execute_sequential_workflow, workflow_execution, sequential_config)

        workflow_execution.reload
        expect(workflow_execution.metadata['progress_percentage']).to eq(100)
        expect(workflow_execution.metadata['completed_steps']).to eq(3)
      end
    end

    describe 'parallel workflow execution' do
      let(:parallel_config) do
        {
          'name' => 'Parallel Test',
          'execution_order' => 'parallel',
          'agents' => [
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Parallel task 1' } },
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Parallel task 2' } },
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Parallel task 3' } }
          ]
        }
      end

      it 'starts all agents simultaneously' do
        start_times = []
        allow(orchestration_service).to receive(:execute_agent_with_orchestration) do
          start_times << Time.current
          double('execution', id: SecureRandom.uuid, reload: double(output_data: {}), ai_agent: double(id: 1))
        end

        orchestration_service.send(:execute_parallel_workflow,
          create(:ai_workflow_execution), parallel_config)

        # All executions should start within a short time window
        time_spread = start_times.max - start_times.min
        expect(time_spread).to be < 1.second
      end

      it 'waits for all executions to complete' do
        executions = Array.new(3) { double('execution', reload: double(output_data: {}), ai_agent: double(id: 1)) }

        allow(orchestration_service).to receive(:execute_agent_with_orchestration)
          .and_return(*executions)

        expect(orchestration_service).to receive(:wait_for_all_executions_completion)
          .with(executions)

        orchestration_service.send(:execute_parallel_workflow,
          create(:ai_workflow_execution), parallel_config)
      end

      it 'collects results from all parallel executions' do
        results = orchestration_service.send(:execute_parallel_workflow,
          create(:ai_workflow_execution), parallel_config)

        expect(results.length).to eq(3)
        results.each do |result|
          expect(result).to include(:agent_id, :execution_id, :result)
        end
      end
    end

    describe 'conditional workflow execution' do
      let(:conditional_config) do
        {
          'name' => 'Conditional Test',
          'execution_order' => 'conditional',
          'condition' => { 'expression' => 'input.score > 0.8' },
          'agents' => [
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Success path' } }
          ],
          'fallback_agents' => [
            { 'id' => ai_provider.id, 'input' => { 'prompt' => 'Fallback path' } }
          ]
        }
      end

      it 'evaluates workflow conditions correctly' do
        # Test condition met
        allow(orchestration_service).to receive(:evaluate_workflow_condition)
          .and_return(true)

        results = orchestration_service.send(:execute_conditional_workflow,
          create(:ai_workflow_execution), conditional_config)

        expect(results.length).to eq(1) # Should execute main agents
      end

      it 'executes fallback agents when condition fails' do
        allow(orchestration_service).to receive(:evaluate_workflow_condition)
          .and_return(false)

        results = orchestration_service.send(:execute_conditional_workflow,
          create(:ai_workflow_execution), conditional_config)

        expect(results.length).to eq(1) # Should execute fallback agents
      end

      it 'records condition evaluation results in metadata' do
        workflow_execution = create(:ai_workflow_execution)

        allow(orchestration_service).to receive(:evaluate_workflow_condition)
          .and_return(true)

        orchestration_service.send(:execute_conditional_workflow, workflow_execution, conditional_config)

        workflow_execution.reload
        expect(workflow_execution.metadata['condition_met']).to be true
      end
    end
  end
end