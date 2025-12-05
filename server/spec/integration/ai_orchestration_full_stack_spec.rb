# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Orchestration Full Stack Integration', type: :integration do
  include AiOrchestrationHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [
    'ai.monitor', 'ai.agents.read', 'ai.workflows.read', 'ai.workflows.create',
    'ai.workflows.update', 'ai.workflows.execute', 'ai.providers.read',
    'ai.providers.test', 'ai.conversations.read', 'ai.conversations.create'
  ]) }
  let(:openai_provider) { create(:ai_provider, account: account, provider_type: 'openai', is_active: true) }
  let(:anthropic_provider) { create(:ai_provider, account: account, provider_type: 'anthropic', is_active: true) }
  let(:ai_agent) { create(:ai_agent, account: account, ai_provider: openai_provider) }

  before do
    mock_action_cable_broadcasting
    mock_ai_provider_responses
    allow(AiWorkflowExecutionJob).to receive(:perform_async).and_call_original
    allow(AiWorkflowNodeExecutionJob).to receive(:perform_async).and_call_original
  end

  describe 'complete workflow execution lifecycle' do
    it 'executes workflow from creation to completion with real-time monitoring' do
      # Step 1: Create workflow via API
      workflow_params = {
        workflow: {
          name: 'Integration Test Workflow',
          description: 'End-to-end testing workflow',
          trigger_type: 'manual'
        },
        nodes: [
          {
            node_id: 'start-1',
            node_type: 'start_node',
            name: 'Start Process',
            position_x: 100,
            position_y: 100,
            configuration: {}
          },
          {
            node_id: 'agent-1',
            node_type: 'ai_agent',
            name: 'Content Analysis',
            position_x: 300,
            position_y: 100,
            configuration: {
              agent_id: ai_agent.id,
              prompt_template: 'Analyze this content: {{input_text}}',
              max_tokens: 500
            }
          },
          {
            node_id: 'condition-1',
            node_type: 'condition',
            name: 'Quality Check',
            position_x: 500,
            position_y: 100,
            configuration: {
              condition_expression: 'result.quality_score > 0.8',
              condition_type: 'javascript'
            }
          },
          {
            node_id: 'webhook-1',
            node_type: 'webhook',
            name: 'Success Notification',
            position_x: 700,
            position_y: 50,
            configuration: {
              url: 'https://api.example.com/webhook',
              method: 'POST',
              headers: { 'Content-Type' => 'application/json' }
            }
          },
          {
            node_id: 'transform-1',
            node_type: 'transform',
            name: 'Retry Processing',
            position_x: 700,
            position_y: 150,
            configuration: {
              transformation_type: 'javascript',
              transformation_code: 'result.retry_count = (result.retry_count || 0) + 1; result;'
            }
          }
        ],
        edges: [
          { edge_id: 'e1', source_node_id: 'start-1', target_node_id: 'agent-1' },
          { edge_id: 'e2', source_node_id: 'agent-1', target_node_id: 'condition-1' },
          { edge_id: 'e3', source_node_id: 'condition-1', target_node_id: 'webhook-1', condition: 'true' },
          { edge_id: 'e4', source_node_id: 'condition-1', target_node_id: 'transform-1', condition: 'false' }
        ]
      }

      post '/api/v1/ai/workflows', params: workflow_params, headers: auth_headers(user)
      expect(response).to have_http_status(:created)

      workflow_response = JSON.parse(response.body)
      expect(workflow_response['success']).to be true
      created_workflow_id = workflow_response['data']['id']

      # Step 2: Verify workflow creation triggered monitoring events
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_monitoring_#{account.id}",
        hash_including(
          type: 'workflow_created',
          workflow_id: created_workflow_id
        )
      )

      # Step 3: Execute workflow via API
      execution_params = {
        input_variables: {
          input_text: 'This is a sample text for analysis and processing'
        }
      }

      post "/api/v1/ai/workflows/#{created_workflow_id}/execute",
           params: execution_params,
           headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      execution_response = JSON.parse(response.body)
      expect(execution_response['success']).to be true

      workflow_run_id = execution_response['data']['run_id']

      # Step 4: Verify execution started broadcast
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_execution_#{workflow_run_id}",
        hash_including(
          type: 'execution_started',
          status: 'running'
        )
      )

      # Step 5: Simulate background job processing
      workflow_run = AiWorkflowRun.find_by(run_id: workflow_run_id)
      expect(workflow_run).to be_present
      expect(workflow_run.status).to eq('running')

      # Mock the orchestration service execution
      mock_orchestration_execution(workflow_run)

      # Step 6: Verify node execution broadcasts
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_execution_#{workflow_run_id}",
        hash_including(
          type: 'node_started',
          node_id: 'start-1'
        )
      )

      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_execution_#{workflow_run_id}",
        hash_including(
          type: 'node_completed',
          node_id: 'start-1',
          status: 'completed'
        )
      )

      # Step 7: Verify final workflow status via API
      get "/api/v1/ai/workflows/#{created_workflow_id}/runs/#{workflow_run_id}",
          headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      final_status = JSON.parse(response.body)
      expect(final_status['data']['status']).to eq('completed')
      expect(final_status['data']['completed_at']).to be_present

      # Step 8: Verify monitoring dashboard stats updated
      get '/api/v1/ai/orchestration/dashboard_stats', headers: auth_headers(user)
      expect(response).to have_http_status(:ok)

      stats = JSON.parse(response.body)['data']
      expect(stats['total_executions']).to be > 0
      expect(stats['successful_executions']).to be > 0
    end
  end

  describe 'provider failover and load balancing integration' do
    it 'handles provider failures with automatic failover' do
      # Create multiple providers
      stable_provider = create(:ai_provider,
        account: account,
        provider_type: 'anthropic',
        is_active: true,
        health_status: 'healthy'
      )

      failing_provider = create(:ai_provider,
        account: account,
        provider_type: 'openai',
        is_active: true,
        health_status: 'degraded'
      )

      agent_with_failing_provider = create(:ai_agent,
        account: account,
        ai_provider: failing_provider
      )

      # Create workflow with agent using failing provider
      workflow = create_comprehensive_workflow(account, {
        nodes: [
          {
            node_id: 'agent-failing',
            node_type: 'ai_agent',
            configuration: { agent_id: agent_with_failing_provider.id }
          }
        ]
      })

      # Mock provider failure
      allow_any_instance_of(AiProviderClientService).to receive(:execute_request)
        .with(failing_provider, anything)
        .and_raise(StandardError, 'Provider timeout')

      # Mock successful fallback
      allow_any_instance_of(AiProviderClientService).to receive(:execute_request)
        .with(stable_provider, anything)
        .and_return(mock_ai_provider_response)

      # Execute workflow
      post "/api/v1/ai/workflows/#{workflow.id}/execute",
           params: { input_variables: { test: 'data' } },
           headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      execution_response = JSON.parse(response.body)
      workflow_run_id = execution_response['data']['run_id']

      # Verify failover broadcast was sent
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_orchestration_#{account.id}",
        hash_including(
          type: 'provider_failover',
          failed_provider_id: failing_provider.id,
          fallback_provider_id: stable_provider.id
        )
      )

      # Verify execution still completed successfully
      workflow_run = AiWorkflowRun.find_by(run_id: workflow_run_id)
      mock_orchestration_execution(workflow_run)

      expect(workflow_run.reload.status).to eq('completed')
    end
  end

  describe 'real-time collaboration and monitoring' do
    let(:user_a) { create(:user, account: account, permissions: ['ai.workflows.update']) }
    let(:user_b) { create(:user, account: account, permissions: ['ai.workflows.update']) }
    let(:workflow) { create(:ai_workflow, account: account, created_by_user: user_a) }

    it 'broadcasts collaborative workflow editing in real-time' do
      # User A makes changes to workflow
      patch "/api/v1/ai/workflows/#{workflow.id}",
            params: {
              workflow: { name: 'Collaboratively Updated Workflow' },
              updated_by: user_a.id
            },
            headers: auth_headers(user_a)

      expect(response).to have_http_status(:ok)

      # Verify collaborative update broadcast
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_orchestration_#{account.id}",
        hash_including(
          type: 'workflow_collaborative_update',
          workflow_id: workflow.id,
          updated_by: hash_including(id: user_a.id),
          action: 'updated'
        )
      )

      # User B adds a node
      post "/api/v1/ai/workflows/#{workflow.id}/nodes",
           params: {
             node: {
               node_id: 'new-node-1',
               node_type: 'ai_agent',
               name: 'New Processing Node',
               position_x: 400,
               position_y: 200,
               configuration: { agent_id: ai_agent.id }
             },
             updated_by: user_b.id
           },
           headers: auth_headers(user_b)

      expect(response).to have_http_status(:created)

      # Verify node addition broadcast
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_orchestration_#{account.id}",
        hash_including(
          type: 'node_added',
          workflow_id: workflow.id,
          node: hash_including(node_id: 'new-node-1'),
          updated_by: hash_including(id: user_b.id)
        )
      )
    end

    it 'handles concurrent editing with conflict resolution' do
      # Simulate concurrent edits
      original_version = workflow.version

      # User A updates workflow name
      patch "/api/v1/ai/workflows/#{workflow.id}",
            params: {
              workflow: { name: 'Version A Update' },
              version: original_version
            },
            headers: auth_headers(user_a)

      expect(response).to have_http_status(:ok)

      # User B tries to update description with stale version
      patch "/api/v1/ai/workflows/#{workflow.id}",
            params: {
              workflow: { description: 'Version B Update' },
              version: original_version
            },
            headers: auth_headers(user_b)

      expect(response).to have_http_status(:conflict)
      conflict_response = JSON.parse(response.body)
      expect(conflict_response['error']).to include('version conflict')

      # Verify conflict broadcast
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_orchestration_#{account.id}",
        hash_including(
          type: 'workflow_conflict',
          workflow_id: workflow.id,
          conflicting_user: hash_including(id: user_b.id)
        )
      )
    end
  end

  describe 'system monitoring and alerting integration' do
    it 'monitors system health and broadcasts alerts' do
      # Simulate high resource usage with UnifiedMonitoringService
      monitoring_service = instance_double(UnifiedMonitoringService)
      allow(UnifiedMonitoringService).to receive(:new).and_return(monitoring_service)
      allow(monitoring_service).to receive(:get_system_overview).and_return({
        status: 'degraded',
        cpu_usage: 95,
        memory_usage: 88,
        active_executions: 150,
        queue_depth: 500
      })

      # Trigger monitoring check
      get '/api/v1/ai/orchestration/system_health', headers: auth_headers(user)
      expect(response).to have_http_status(:ok)

      health_data = JSON.parse(response.body)['data']
      expect(health_data['status']).to eq('warning')
      expect(health_data['alerts']).to include(
        hash_including(
          level: 'warning',
          message: 'High CPU usage detected'
        )
      )

      # Verify system alert broadcast
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_monitoring_#{account.id}",
        hash_including(
          type: 'system_alert',
          alert: hash_including(
            level: 'warning',
            message: 'High resource usage detected'
          )
        )
      )
    end

    it 'monitors cost thresholds and sends alerts' do
      # Simulate cost threshold breach
      allow(AiCostOptimizationService).to receive(:daily_cost_for_account)
        .with(account).and_return(125.50)

      allow(account).to receive(:daily_cost_limit).and_return(100.00)

      # Trigger cost monitoring
      get '/api/v1/ai/orchestration/cost_monitoring', headers: auth_headers(user)
      expect(response).to have_http_status(:ok)

      cost_data = JSON.parse(response.body)['data']
      expect(cost_data['overage_percentage']).to eq(25.5)
      expect(cost_data['alert_level']).to eq('warning')

      # Verify cost alert broadcast
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_monitoring_#{account.id}",
        hash_including(
          type: 'cost_alert',
          cost_data: hash_including(
            current_cost: 125.50,
            threshold: 100.00,
            overage_percentage: 25.5
          )
        )
      )
    end
  end

  describe 'error handling and recovery across components' do
    it 'handles workflow execution errors with proper cleanup and notifications' do
      # Create workflow with intentionally failing configuration
      faulty_workflow = create(:ai_workflow,
        account: account,
        created_by_user: user,
        status: 'active'
      )

      faulty_node = create(:ai_workflow_node,
        ai_workflow: faulty_workflow,
        node_id: 'faulty-node',
        node_type: 'ai_agent',
        configuration: { agent_id: 'non-existent-agent-id' }
      )

      # Execute faulty workflow
      post "/api/v1/ai/workflows/#{faulty_workflow.id}/execute",
           params: { input_variables: {} },
           headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      execution_response = JSON.parse(response.body)
      workflow_run_id = execution_response['data']['run_id']

      # Mock error during execution
      workflow_run = AiWorkflowRun.find_by(run_id: workflow_run_id)
      allow_any_instance_of(Mcp::WorkflowOrchestrator).to receive(:execute)
        .and_raise(StandardError, 'Agent not found')

      # Trigger error handling
      expect {
        AiWorkflowExecutionJob.new.perform(workflow_run.id)
      }.not_to raise_error

      # Verify error broadcast
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_execution_#{workflow_run_id}",
        hash_including(
          type: 'execution_failed',
          error: 'Agent not found',
          status: 'failed'
        )
      )

      # Verify workflow run marked as failed
      expect(workflow_run.reload.status).to eq('failed')
      expect(workflow_run.error_message).to eq('Agent not found')

      # Verify cleanup occurred
      expect(workflow_run.ended_at).to be_present
    end

    it 'recovers from temporary WebSocket connection issues' do
      # Simulate WebSocket disconnection
      allow(ActionCable.server).to receive(:broadcast)
        .and_raise(Redis::ConnectionError, 'Connection lost')

      workflow = create_comprehensive_workflow(account)

      # Execute workflow despite WebSocket issues
      post "/api/v1/ai/workflows/#{workflow.id}/execute",
           params: { input_variables: {} },
           headers: auth_headers(user)

      expect(response).to have_http_status(:ok)

      # Verify execution continues despite broadcast failure
      execution_response = JSON.parse(response.body)
      expect(execution_response['success']).to be true
      expect(execution_response['data']['run_id']).to be_present

      # Reset WebSocket and verify recovery
      allow(ActionCable.server).to receive(:broadcast).and_call_original

      # Subsequent operations should work normally
      get "/api/v1/ai/workflows/#{workflow.id}/status", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
    end
  end

  private

  def mock_orchestration_execution(workflow_run)
    # Mock successful workflow execution
    workflow_run.update!(
      status: 'completed',
      started_at: 1.minute.ago,
      ended_at: Time.current,
      result: {
        output: 'Workflow completed successfully',
        nodes_executed: workflow_run.ai_workflow.ai_workflow_nodes.count,
        total_cost: 0.15,
        execution_time_ms: 45000
      }
    )

    # Create node executions
    workflow_run.ai_workflow.ai_workflow_nodes.each do |node|
      create(:ai_workflow_node_execution,
        ai_workflow_run: workflow_run,
        ai_workflow_node: node,
        status: 'completed',
        started_at: 1.minute.ago,
        ended_at: 30.seconds.ago,
        result: { output: "Node #{node.node_id} completed" }
      )
    end
  end

  def mock_ai_provider_responses
    allow_any_instance_of(AiProviderClientService).to receive(:execute_request)
      .and_return(mock_ai_provider_response)
  end

  def auth_headers(user)
    token = JWT.encode(
      { user_id: user.id, exp: 1.hour.from_now.to_i },
      Rails.application.credentials.secret_key_base,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end
end