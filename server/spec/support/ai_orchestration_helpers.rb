# frozen_string_literal: true

module AiOrchestrationHelpers

  # Mock AI provider responses with customizable parameters
  def mock_ai_provider_response(
    content: 'AI generated response',
    prompt_tokens: 100,
    completion_tokens: 150,
    model: 'gpt-4',
    provider: 'OpenAI',
    success: true,
    error: nil
  )
    if success
      {
        success: true,
        data: {
          choices: [{
            message: { content: content },
            finish_reason: 'stop'
          }],
          usage: {
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_tokens: prompt_tokens + completion_tokens
          },
          model: model,
          created: Time.current.to_i
        },
        provider: provider
      }
    else
      {
        success: false,
        error: error || 'AI provider request failed',
        provider: provider
      }
    end
  end

  # Create comprehensive workflow with various node types and configurations
  def create_comprehensive_workflow(account, options = {})
    workflow = create(:ai_workflow, account: account, **options.slice(:name, :description))

    # Create nodes
    start_node = create(:ai_workflow_node, :start_node, ai_workflow: workflow, name: 'Start')

    ai_agent_node = create(:ai_workflow_node, :ai_agent,
      ai_workflow: workflow,
      name: 'AI Analysis',
      configuration: {
        agent_id: create(:ai_agent, account: account).id,
        model: 'gpt-4',
        temperature: 0.7,
        max_tokens: 2000,
        system_prompt: 'You are an AI analyst. Analyze the input data and provide insights.'
      }
    )

    condition_node = create(:ai_workflow_node, :condition,
      ai_workflow: workflow,
      name: 'Quality Check',
      configuration: {
        condition: 'input.confidence_score > 0.8',
        true_path: 'high_quality_path',
        false_path: 'review_path'
      }
    )

    transform_node = create(:ai_workflow_node, :transform,
      ai_workflow: workflow,
      name: 'Data Transform',
      configuration: {
        script: 'output.formatted_data = input.raw_data.toUpperCase();'
      }
    )

    api_call_node = create(:ai_workflow_node, :api_call,
      ai_workflow: workflow,
      name: 'External API',
      configuration: {
        url: 'https://api.example.com/process',
        method: 'POST',
        headers: { 'Content-Type' => 'application/json' },
        timeout: 30
      }
    )

    webhook_node = create(:ai_workflow_node, :webhook,
      ai_workflow: workflow,
      name: 'Notification Webhook',
      configuration: {
        url: 'https://webhook.example.com/notify',
        method: 'POST',
        payload_template: '{"status": "{{status}}", "data": "{{data}}"}'
      }
    )

    end_node = create(:ai_workflow_node, :end_node, ai_workflow: workflow, name: 'End')

    # Create edges to connect nodes
    create(:ai_workflow_edge, ai_workflow: workflow,
           source_node_id: start_node.node_id, target_node_id: ai_agent_node.node_id)
    create(:ai_workflow_edge, ai_workflow: workflow,
           source_node_id: ai_agent_node.node_id, target_node_id: condition_node.node_id)
    create(:ai_workflow_edge, ai_workflow: workflow,
           source_node_id: condition_node.node_id, target_node_id: transform_node.node_id,
           condition_config: { path: 'high_quality_path' })
    create(:ai_workflow_edge, ai_workflow: workflow,
           source_node_id: transform_node.node_id, target_node_id: api_call_node.node_id)
    create(:ai_workflow_edge, ai_workflow: workflow,
           source_node_id: api_call_node.node_id, target_node_id: webhook_node.node_id)
    create(:ai_workflow_edge, ai_workflow: workflow,
           source_node_id: webhook_node.node_id, target_node_id: end_node.node_id)

    workflow.reload
  end

  # Create AI providers with different performance characteristics for load balancing tests
  def create_load_balanced_providers(account)
    {
      high_performance: create(:ai_provider,
        account: account,
        name: 'High Performance Provider',
        metadata: {
          max_concurrent: 20,
          avg_response_time: 800,
          success_rate: 98.5,
          cost_per_token: 0.002
        }
      ),
      medium_performance: create(:ai_provider,
        account: account,
        name: 'Medium Performance Provider',
        metadata: {
          max_concurrent: 10,
          avg_response_time: 1200,
          success_rate: 95.0,
          cost_per_token: 0.0015
        }
      ),
      budget_provider: create(:ai_provider,
        account: account,
        name: 'Budget Provider',
        metadata: {
          max_concurrent: 15,
          avg_response_time: 2000,
          success_rate: 88.0,
          cost_per_token: 0.001
        }
      )
    }
  end

  # Simulate AI agent executions with different statuses and characteristics
  def create_execution_scenarios(account, agent, provider)
    {
      successful_executions: create_list(:ai_agent_execution, 10, :completed,
        account: account, ai_agent: agent, ai_provider: provider,
        duration_ms: rand(800..1500), cost: rand(0.01..0.05),
        tokens_consumed: rand(50..200), tokens_generated: rand(100..300)
      ),
      failed_executions: create_list(:ai_agent_execution, 2, :failed,
        account: account, ai_agent: agent, ai_provider: provider,
        error_message: 'Provider timeout',
        duration_ms: rand(5000..10000)
      ),
      active_executions: create_list(:ai_agent_execution, 3, :processing,
        account: account, ai_agent: agent, ai_provider: provider,
        started_at: rand(1..30).minutes.ago
      ),
      queued_executions: create_list(:ai_agent_execution, 5, :queued,
        account: account, ai_agent: agent, ai_provider: provider
      )
    }
  end

  # Mock ActionCable broadcasting for testing real-time features
  def mock_action_cable_broadcasting
    @broadcast_messages = []
    allow(ActionCable.server).to receive(:broadcast) do |channel, message|
      @broadcast_messages << { channel: channel, message: message }
    end
  end

  # Helper to access captured broadcast messages
  def broadcast_messages
    @broadcast_messages || []
  end

  # Find broadcast messages for specific channel
  def messages_for_channel(channel_pattern)
    broadcast_messages.select { |msg| msg[:channel].match?(channel_pattern) }
  end

  # Verify that specific orchestration events were broadcasted
  def expect_orchestration_broadcast(account_id, event_type, additional_checks = {})
    matching_messages = messages_for_channel(/ai_orchestration_#{account_id}/)
      .select { |msg| msg[:message][:type] == event_type }

    expect(matching_messages).not_to be_empty,
      "Expected broadcast of type '#{event_type}' to account #{account_id}, but none found"

    if additional_checks.any?
      latest_message = matching_messages.last[:message]
      additional_checks.each do |key, expected_value|
        expect(latest_message[key]).to eq(expected_value)
      end
    end
  end

  # Create test workflow configuration for orchestration tests
  def build_workflow_config(execution_order: 'sequential', agents: nil, **options)
    agents ||= [
      { 'id' => create(:ai_agent).id, 'input' => { 'prompt' => 'Analyze data' } },
      { 'id' => create(:ai_agent).id, 'input' => { 'prompt' => 'Generate summary' } }
    ]

    {
      'name' => 'Test Workflow',
      'execution_order' => execution_order,
      'agents' => agents,
      'timeout_minutes' => 30
    }.merge(options.stringify_keys)
  end

  # Simulate performance metrics for provider scoring tests
  def simulate_provider_metrics(provider, metrics = {})
    default_metrics = {
      current_load: 5,
      max_concurrent: 10,
      success_rate: 95.0,
      avg_response_time: 1200,
      cost_efficiency: 0.002
    }

    final_metrics = default_metrics.merge(metrics)

    allow_any_instance_of(AiAgentOrchestrationService)
      .to receive(:calculate_provider_current_load)
      .with(provider)
      .and_return(final_metrics[:current_load])

    allow_any_instance_of(AiAgentOrchestrationService)
      .to receive(:calculate_provider_success_rate)
      .with(provider)
      .and_return(final_metrics[:success_rate])

    allow_any_instance_of(AiAgentOrchestrationService)
      .to receive(:calculate_provider_avg_response_time)
      .with(provider)
      .and_return(final_metrics[:avg_response_time])

    provider.update!(metadata: {
      'max_concurrent' => final_metrics[:max_concurrent],
      'cost_per_token' => final_metrics[:cost_efficiency]
    })
  end

  # Time-based test helper for measuring execution performance
  def measure_execution_time
    start_time = Time.current
    yield
    Time.current - start_time
  end

  # Wait for async operations with timeout
  def wait_for_condition(timeout: 5.seconds, &block)
    deadline = Time.current + timeout
    loop do
      return true if block.call

      if Time.current > deadline
        raise "Condition not met within #{timeout} seconds"
      end

      sleep 0.1
    end
  end

  # Helper for testing circuit breaker functionality
  def trigger_circuit_breaker(service, provider, failure_threshold: 5)
    failure_threshold.times do
      allow_any_instance_of(AiProviderClientService).to receive(:generate_text)
        .and_raise(StandardError, 'Provider unavailable')

      begin
        service.execute_agent_with_orchestration(
          create(:ai_agent), { prompt: 'test' }
        )
      rescue StandardError
        # Expected failures
      end
    end
  end

  # Create workflow run with realistic node executions
  def create_realistic_workflow_run(workflow, status: 'completed')
    run = create(:ai_workflow_run, ai_workflow: workflow, status: status)

    workflow.ai_workflow_nodes.each do |node|
      execution_status = case status
      when 'running'
        node.is_start_node? ? 'completed' : 'pending'
      when 'completed'
        'completed'
      when 'failed'
        node.is_start_node? ? 'completed' : 'failed'
      else
        'pending'
      end

      create(:ai_workflow_node_execution,
        ai_workflow_run: run,
        ai_workflow_node: node,
        node_id: node.node_id,
        node_type: node.node_type,
        status: execution_status,
        input_data: { test: 'input' },
        output_data: execution_status == 'completed' ? { result: 'success' } : {},
        cost: node.node_type == 'ai_agent' ? rand(0.01..0.1) : 0,
        tokens_consumed: node.node_type == 'ai_agent' ? rand(50..200) : 0,
        tokens_generated: node.node_type == 'ai_agent' ? rand(100..300) : 0,
        duration: rand(500..2000)
      )
    end

    run.reload
  end

  # Helper to assert workflow structure validation
  def expect_workflow_validation_error(workflow, error_pattern)
    service = AiAgentOrchestrationService.new(workflow)
    result = service.validate_workflow_structure

    expect(result[:valid]).to be false
    expect(result[:errors].join(' ')).to match(error_pattern)
  end

  # Mock external API calls for testing API nodes
  def mock_external_api_calls
    # Mock successful API responses
    stub_request(:any, /api\.example\.com/)
      .to_return(
        status: 200,
        body: { result: 'success', data: 'processed' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    # Mock webhook deliveries
    stub_request(:post, /webhook\.example\.com/)
      .to_return(status: 200, body: 'OK')
  end

  # Create performance benchmarking data
  def create_performance_benchmarks(account)
    # Create historical execution data for performance analysis
    (1..30).each do |day_offset|
      date = day_offset.days.ago

      # Create varying load throughout the day
      [9, 10, 11, 14, 15, 16].each do |hour| # Peak hours
        create_list(:ai_agent_execution, rand(15..25), :completed,
          account: account,
          created_at: date.change(hour: hour),
          duration_ms: rand(800..1500),
          cost: rand(0.02..0.08)
        )
      end

      # Off-peak hours
      [8, 12, 13, 17, 18].each do |hour|
        create_list(:ai_agent_execution, rand(5..12), :completed,
          account: account,
          created_at: date.change(hour: hour),
          duration_ms: rand(1000..2000),
          cost: rand(0.01..0.05)
        )
      end
    end
  end
end

RSpec.configure do |config|
  config.include AiOrchestrationHelpers, type: :service
  config.include AiOrchestrationHelpers, type: :channel
  config.include AiOrchestrationHelpers, type: :job
  config.include AiOrchestrationHelpers, type: :integration
end