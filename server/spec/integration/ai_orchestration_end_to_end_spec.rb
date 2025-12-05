# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Orchestration End-to-End Integration', type: :integration do
  include AiOrchestrationHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [
    'ai.monitor', 'ai.agents.read', 'ai.agents.create', 'ai.workflows.read',
    'ai.workflows.create', 'ai.workflows.update', 'ai.workflows.execute',
    'ai.providers.read', 'ai.providers.create', 'ai.providers.test'
  ]) }

  before do
    mock_action_cable_broadcasting
    mock_external_apis
    clear_sidekiq_jobs
  end

  describe 'complete user journey: provider setup → agent creation → workflow execution' do
    it 'simulates real user workflow from frontend to completion' do
      # Step 1: User creates AI provider (simulating frontend form submission)
      provider_params = {
        ai_provider: {
          name: 'OpenAI Production',
          provider_type: 'openai',
          base_url: 'https://api.openai.com/v1',
          api_key: 'sk-test-key-123',
          model_config: {
            default_model: 'gpt-4',
            max_tokens: 4000,
            temperature: 0.7
          },
          rate_limits: {
            requests_per_minute: 100,
            tokens_per_minute: 150000
          }
        }
      }

      post '/api/v1/ai/providers', params: provider_params, headers: auth_headers(user)
      expect(response).to have_http_status(:created)

      provider_response = JSON.parse(response.body)
      expect(provider_response['success']).to be true
      created_provider_id = provider_response['data']['id']

      # Step 2: Test provider connection (simulating frontend test button)
      post "/api/v1/ai/providers/#{created_provider_id}/test", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)

      test_response = JSON.parse(response.body)
      expect(test_response['data']['status']).to eq('healthy')
      expect(test_response['data']['response_time_ms']).to be > 0

      # Step 3: Create AI agent using the provider
      agent_params = {
        ai_agent: {
          name: 'Content Analyzer Agent',
          description: 'Analyzes content for quality and sentiment',
          ai_provider_id: created_provider_id,
          agent_type: 'content_analysis',
          system_prompt: 'You are an expert content analyzer. Analyze the given content for quality, sentiment, and key insights.',
          configuration: {
            model: 'gpt-4',
            max_tokens: 1000,
            temperature: 0.3,
            response_format: 'json'
          }
        }
      }

      post '/api/v1/ai/agents', params: agent_params, headers: auth_headers(user)
      expect(response).to have_http_status(:created)

      agent_response = JSON.parse(response.body)
      expect(agent_response['success']).to be true
      created_agent_id = agent_response['data']['id']

      # Step 4: Create comprehensive workflow using the agent
      workflow_params = {
        workflow: {
          name: 'Content Processing Pipeline',
          description: 'Analyzes content, checks quality, and generates summary',
          trigger_type: 'api',
          timeout_seconds: 300
        },
        nodes: [
          {
            node_id: 'start-1',
            node_type: 'start_node',
            name: 'Start Processing',
            position_x: 100,
            position_y: 200,
            configuration: {}
          },
          {
            node_id: 'analyzer-1',
            node_type: 'ai_agent',
            name: 'Content Analysis',
            position_x: 300,
            position_y: 200,
            configuration: {
              agent_id: created_agent_id,
              prompt_template: 'Analyze this content for quality and sentiment: {{content}}',
              output_schema: {
                type: 'object',
                properties: {
                  quality_score: { type: 'number' },
                  sentiment: { type: 'string' },
                  key_points: { type: 'array' }
                }
              }
            }
          },
          {
            node_id: 'quality-check-1',
            node_type: 'condition',
            name: 'Quality Gate',
            position_x: 500,
            position_y: 200,
            configuration: {
              condition_expression: 'parseFloat(result.quality_score) >= 0.7',
              condition_type: 'javascript'
            }
          },
          {
            node_id: 'summarizer-1',
            node_type: 'ai_agent',
            name: 'Summary Generator',
            position_x: 700,
            position_y: 150,
            configuration: {
              agent_id: created_agent_id,
              prompt_template: 'Create a concise summary of this analysis: {{analyzer_result}}'
            }
          },
          {
            node_id: 'improvement-1',
            node_type: 'ai_agent',
            name: 'Improvement Suggestions',
            position_x: 700,
            position_y: 250,
            configuration: {
              agent_id: created_agent_id,
              prompt_template: 'Suggest improvements for this low-quality content: {{content}}'
            }
          },
          {
            node_id: 'webhook-success-1',
            node_type: 'webhook',
            name: 'Success Notification',
            position_x: 900,
            position_y: 150,
            configuration: {
              url: 'https://hooks.example.com/success',
              method: 'POST',
              headers: { 'Content-Type' => 'application/json' },
              body_template: '{"status": "success", "summary": "{{summary}}"}'
            }
          },
          {
            node_id: 'webhook-improvement-1',
            node_type: 'webhook',
            name: 'Improvement Notification',
            position_x: 900,
            position_y: 250,
            configuration: {
              url: 'https://hooks.example.com/improvement',
              method: 'POST',
              headers: { 'Content-Type' => 'application/json' },
              body_template: '{"status": "needs_improvement", "suggestions": "{{suggestions}}"}'
            }
          }
        ],
        edges: [
          { edge_id: 'e1', source_node_id: 'start-1', target_node_id: 'analyzer-1' },
          { edge_id: 'e2', source_node_id: 'analyzer-1', target_node_id: 'quality-check-1' },
          { edge_id: 'e3', source_node_id: 'quality-check-1', target_node_id: 'summarizer-1', condition: 'true' },
          { edge_id: 'e4', source_node_id: 'quality-check-1', target_node_id: 'improvement-1', condition: 'false' },
          { edge_id: 'e5', source_node_id: 'summarizer-1', target_node_id: 'webhook-success-1' },
          { edge_id: 'e6', source_node_id: 'improvement-1', target_node_id: 'webhook-improvement-1' }
        ]
      }

      post '/api/v1/ai/workflows', params: workflow_params, headers: auth_headers(user)
      expect(response).to have_http_status(:created)

      workflow_response = JSON.parse(response.body)
      expect(workflow_response['success']).to be true
      created_workflow_id = workflow_response['data']['id']

      # Step 5: Execute workflow with high-quality content (should trigger success path)
      execution_params = {
        input_variables: {
          content: 'This is a well-written article about artificial intelligence. It provides clear explanations, uses proper grammar, and offers valuable insights into the future of AI technology. The content is structured logically and includes relevant examples.'
        }
      }

      post "/api/v1/ai/workflows/#{created_workflow_id}/execute",
           params: execution_params,
           headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      execution_response = JSON.parse(response.body)
      expect(execution_response['success']).to be true

      high_quality_run_id = execution_response['data']['run_id']

      # Step 6: Monitor execution progress via WebSocket simulation
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_execution_#{high_quality_run_id}",
        hash_including(
          type: 'execution_started',
          workflow_id: created_workflow_id,
          status: 'running'
        )
      )

      # Step 7: Simulate background job execution
      high_quality_run = AiWorkflowRun.find_by(run_id: high_quality_run_id)
      simulate_successful_execution(high_quality_run, quality_score: 0.85)

      # Step 8: Verify high-quality path was taken
      expect(high_quality_run.reload.status).to eq('completed')
      expect(high_quality_run.result['path_taken']).to eq('high_quality')
      expect(high_quality_run.result['nodes_executed']).to include('summarizer-1', 'webhook-success-1')

      # Step 9: Execute same workflow with low-quality content (should trigger improvement path)
      low_quality_execution_params = {
        input_variables: {
          content: 'bad content here. no structure. poor grammar mistakes everywhere. not helpful at all.'
        }
      }

      post "/api/v1/ai/workflows/#{created_workflow_id}/execute",
           params: low_quality_execution_params,
           headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      low_quality_execution_response = JSON.parse(response.body)
      low_quality_run_id = low_quality_execution_response['data']['run_id']

      # Step 10: Simulate low-quality execution
      low_quality_run = AiWorkflowRun.find_by(run_id: low_quality_run_id)
      simulate_successful_execution(low_quality_run, quality_score: 0.45)

      # Step 11: Verify low-quality path was taken
      expect(low_quality_run.reload.status).to eq('completed')
      expect(low_quality_run.result['path_taken']).to eq('needs_improvement')
      expect(low_quality_run.result['nodes_executed']).to include('improvement-1', 'webhook-improvement-1')

      # Step 12: Get workflow analytics (simulating frontend dashboard)
      get "/api/v1/ai/workflows/#{created_workflow_id}/analytics", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)

      analytics = JSON.parse(response.body)['data']
      expect(analytics['total_executions']).to eq(2)
      expect(analytics['success_rate']).to eq(100.0)
      expect(analytics['average_execution_time']).to be > 0
      expect(analytics['path_distribution']['high_quality']).to eq(1)
      expect(analytics['path_distribution']['needs_improvement']).to eq(1)

      # Step 13: Get real-time monitoring data (simulating frontend activity feed)
      get '/api/v1/ai/orchestration/recent_activities', headers: auth_headers(user)
      expect(response).to have_http_status(:ok)

      activities = JSON.parse(response.body)['data']
      expect(activities.length).to be >= 2

      # Should include both workflow executions
      execution_activities = activities.select { |a| a['type'] == 'workflow_completed' }
      expect(execution_activities.length).to eq(2)

      # Step 14: Test collaborative features (simulating second user)
      collaborator = create(:user, account: account, permissions: ['ai.workflows.update'])

      # Collaborator views workflow
      get "/api/v1/ai/workflows/#{created_workflow_id}", headers: auth_headers(collaborator)
      expect(response).to have_http_status(:ok)

      # Collaborator adds a new node
      new_node_params = {
        node: {
          node_id: 'validator-1',
          node_type: 'ai_agent',
          name: 'Content Validator',
          position_x: 400,
          position_y: 300,
          configuration: {
            agent_id: created_agent_id,
            prompt_template: 'Validate this content for accuracy: {{content}}'
          }
        }
      }

      post "/api/v1/ai/workflows/#{created_workflow_id}/nodes",
           params: new_node_params,
           headers: auth_headers(collaborator)

      expect(response).to have_http_status(:created)

      # Verify collaborative update broadcast
      expect(ActionCable.server).to have_received(:broadcast).with(
        "ai_workflow_orchestration_#{account.id}",
        hash_including(
          type: 'node_added',
          workflow_id: created_workflow_id,
          updated_by: hash_including(id: collaborator.id)
        )
      )

      # Step 15: Test error handling (simulating provider failure)
      # Temporarily disable provider
      patch "/api/v1/ai/providers/#{created_provider_id}",
            params: { ai_provider: { is_active: false } },
            headers: auth_headers(user)

      expect(response).to have_http_status(:ok)

      # Try to execute workflow with disabled provider
      post "/api/v1/ai/workflows/#{created_workflow_id}/execute",
           params: execution_params,
           headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_content)
      error_response = JSON.parse(response.body)
      expect(error_response['error']).to include('provider not available')

      # Step 16: Verify system monitoring captured the failure
      get '/api/v1/ai/orchestration/dashboard_stats', headers: auth_headers(user)
      expect(response).to have_http_status(:ok)

      stats = JSON.parse(response.body)['data']
      expect(stats['failed_executions']).to be >= 1
      expect(stats['provider_issues']).to be >= 1
    end
  end

  describe 'multi-tenant isolation and security' do
    let(:account_a) { create(:account) }
    let(:account_b) { create(:account) }
    let(:user_a) { create(:user, account: account_a, permissions: ['ai.workflows.read']) }
    let(:user_b) { create(:user, account: account_b, permissions: ['ai.workflows.read']) }

    it 'ensures complete tenant isolation across all AI orchestration features' do
      # Create workflows in different accounts
      workflow_a = create(:ai_workflow, account: account_a)
      workflow_b = create(:ai_workflow, account: account_b)

      # User A should only see their workflow
      get '/api/v1/ai/workflows', headers: auth_headers(user_a)
      expect(response).to have_http_status(:ok)

      workflows_response = JSON.parse(response.body)['data']
      workflow_ids = workflows_response.map { |w| w['id'] }
      expect(workflow_ids).to include(workflow_a.id)
      expect(workflow_ids).not_to include(workflow_b.id)

      # User A should not be able to access User B's workflow
      get "/api/v1/ai/workflows/#{workflow_b.id}", headers: auth_headers(user_a)
      expect(response).to have_http_status(:not_found)

      # WebSocket channels should be isolated
      expect {
        get "/api/v1/ai/workflows/#{workflow_b.id}/subscribe", headers: auth_headers(user_a)
      }.not_to change { ActionCable.server.connections.count }

      # Orchestration stats should be tenant-specific
      get '/api/v1/ai/orchestration/dashboard_stats', headers: auth_headers(user_a)
      expect(response).to have_http_status(:ok)

      stats_a = JSON.parse(response.body)['data']

      get '/api/v1/ai/orchestration/dashboard_stats', headers: auth_headers(user_b)
      expect(response).to have_http_status(:ok)

      stats_b = JSON.parse(response.body)['data']

      # Stats should be completely isolated
      expect(stats_a['account_id']).to eq(account_a.id)
      expect(stats_b['account_id']).to eq(account_b.id)
      expect(stats_a['total_workflows']).not_to eq(stats_b['total_workflows'])
    end
  end

  private

  def simulate_successful_execution(workflow_run, quality_score: 0.8)
    workflow_run.update!(
      status: 'running',
      started_at: Time.current
    )

    # Simulate node executions
    analyzer_result = {
      quality_score: quality_score,
      sentiment: quality_score > 0.7 ? 'positive' : 'neutral',
      key_points: ['Point 1', 'Point 2', 'Point 3']
    }

    path_taken = quality_score >= 0.7 ? 'high_quality' : 'needs_improvement'
    nodes_executed = ['start-1', 'analyzer-1', 'quality-check-1']

    if quality_score >= 0.7
      nodes_executed.concat(['summarizer-1', 'webhook-success-1'])
    else
      nodes_executed.concat(['improvement-1', 'webhook-improvement-1'])
    end

    workflow_run.update!(
      status: 'completed',
      ended_at: Time.current,
      result: {
        analyzer_result: analyzer_result,
        path_taken: path_taken,
        nodes_executed: nodes_executed,
        total_cost: 0.25,
        execution_time_ms: 12000
      }
    )

    # Broadcast completion
    ActionCable.server.broadcast(
      "ai_workflow_execution_#{workflow_run.run_id}",
      {
        type: 'execution_completed',
        status: 'completed',
        result: workflow_run.result
      }
    )
  end

  def mock_external_apis
    # Mock OpenAI API responses
    allow_any_instance_of(AiProviderClientService).to receive(:test_connection)
      .and_return({
        status: 'healthy',
        response_time_ms: 150,
        model_available: true
      })

    allow_any_instance_of(AiProviderClientService).to receive(:execute_request)
      .and_return(mock_ai_provider_response(
        content: '{"quality_score": 0.85, "sentiment": "positive", "key_points": ["Clear structure", "Good grammar", "Valuable insights"]}'
      ))

    # Mock webhook calls
    allow(Net::HTTP).to receive(:post).and_return(
      instance_double(Net::HTTPResponse, code: '200', body: '{"status": "received"}')
    )
  end

  def clear_sidekiq_jobs
    Sidekiq::Worker.clear_all
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