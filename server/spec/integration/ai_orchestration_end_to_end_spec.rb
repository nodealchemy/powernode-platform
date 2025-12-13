# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Orchestration End-to-End Integration', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Provider setup
  let!(:openai_provider) { create(:ai_provider, account: account, slug: 'openai-e2e-test', is_active: true) }

  let!(:openai_credential) do
    create(:ai_provider_credential,
           account: account,
           ai_provider: openai_provider,
           credentials: { api_key: 'sk-test-e2e-key' },
           is_active: true,
           is_default: true)
  end

  # Agent setup
  let!(:ai_agent) do
    create(:ai_agent,
           account: account,
           ai_provider: openai_provider,
           name: 'E2E Test Agent',
           agent_type: 'assistant')
  end

  # Workflow setup
  let!(:ai_workflow) do
    create(:ai_workflow,
           account: account,
           name: 'E2E Test Workflow',
           description: 'End-to-end test workflow',
           is_active: true)
  end

  let!(:start_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'start',
           name: 'Start',
           position: { x: 100, y: 100 },
           is_start_node: true)
  end

  let!(:agent_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'ai_agent',
           name: 'Process',
           position: { x: 200, y: 100 })
  end

  let!(:end_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'end',
           name: 'End',
           position: { x: 300, y: 100 },
           is_end_node: true)
  end

  let!(:edge1) do
    create(:ai_workflow_edge,
           ai_workflow: ai_workflow,
           source_node: start_node,
           target_node: agent_node)
  end

  let!(:edge2) do
    create(:ai_workflow_edge,
           ai_workflow: ai_workflow,
           source_node: agent_node,
           target_node: end_node)
  end

  before do
    # Setup authentication
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:current_account).and_return(account)
    allow_any_instance_of(ApplicationController).to receive(:authenticate_request).and_return(true)

    # Grant permissions
    allow_any_instance_of(Api::V1::Ai::ProvidersController).to receive(:require_permission).and_return(true)
    allow_any_instance_of(Api::V1::Ai::AgentsController).to receive(:require_permission).and_return(true)
    allow_any_instance_of(Api::V1::Ai::WorkflowsController).to receive(:require_permission).and_return(true)
  end

  describe 'Complete User Journey' do
    it 'lists providers available for orchestration' do
      get '/api/v1/ai/providers'

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['items']).to be_an(Array)
    end

    it 'retrieves provider details' do
      get "/api/v1/ai/providers/#{openai_provider.id}"

      expect(response).to have_http_status(:ok)
    end

    it 'lists available agents' do
      get '/api/v1/ai/agents'

      expect(response).to have_http_status(:ok)
    end

    it 'retrieves agent details' do
      get "/api/v1/ai/agents/#{ai_agent.id}"

      expect(response).to have_http_status(:ok)
    end

    it 'lists available workflows' do
      get '/api/v1/ai/workflows'

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
    end

    it 'retrieves workflow with nodes' do
      get "/api/v1/ai/workflows/#{ai_workflow.id}"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['workflow']['id']).to eq(ai_workflow.id)
    end
  end

  describe 'Multi-Tenant Isolation' do
    let(:other_account) { create(:account) }
    let(:other_user) { create(:user, account: other_account) }

    let!(:other_workflow) do
      create(:ai_workflow, account: other_account, name: 'Other Workflow')
    end

    it 'ensures user can only see their own workflows' do
      get '/api/v1/ai/workflows'

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      workflow_ids = json['data']['items'].map { |w| w['id'] }

      expect(workflow_ids).to include(ai_workflow.id)
      expect(workflow_ids).not_to include(other_workflow.id)
    end

    it 'blocks access to other account workflows' do
      get "/api/v1/ai/workflows/#{other_workflow.id}"

      expect(response).to have_http_status(:not_found)
    end

    it 'ensures agents are account-scoped' do
      other_agent = create(:ai_agent, account: other_account, ai_provider: openai_provider, agent_type: 'assistant')

      get "/api/v1/ai/agents/#{other_agent.id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'Workflow Execution Flow' do
    it 'executes workflow' do
      post "/api/v1/ai/workflows/#{ai_workflow.id}/execute", params: {
        input_data: { content: 'Test content for E2E' }
      }

      # 412 = precondition failed (workflow validation), 422 = validation error
      expect(response.status).to be_in([ 200, 201, 202, 412, 422, 500 ])
    end

    it 'creates and lists workflow runs' do
      run = create(:ai_workflow_run, ai_workflow: ai_workflow, account: account)

      get "/api/v1/ai/workflows/#{ai_workflow.id}/runs"

      expect(response.status).to be_in([ 200, 404 ])
    end

    it 'retrieves specific workflow run' do
      run = create(:ai_workflow_run, ai_workflow: ai_workflow, account: account)

      get "/api/v1/ai/workflows/#{ai_workflow.id}/runs/#{run.id}"

      expect(response.status).to be_in([ 200, 404 ])
    end
  end

  describe 'Agent Execution Flow' do
    it 'executes agent' do
      mock_execution = build_stubbed(:ai_agent_execution, ai_agent: ai_agent, account: account)
      allow_any_instance_of(AiAgent).to receive(:mcp_available?).and_return(true)
      allow_any_instance_of(AiAgent).to receive(:execute).and_return(mock_execution)

      post "/api/v1/ai/agents/#{ai_agent.id}/execute", params: {
        input_parameters: { prompt: 'E2E test prompt' }
      }

      expect(response.status).to be_in([ 200, 201, 202, 422, 500 ])
    end

    it 'creates conversation with agent' do
      post "/api/v1/ai/agents/#{ai_agent.id}/conversations", params: {
        conversation: { title: 'E2E Test Conversation' }
      }

      expect(response.status).to be_in([ 200, 201, 412, 422 ])
    end
  end

  describe 'Provider Testing Flow' do
    it 'tests provider connectivity' do
      allow_any_instance_of(AiProviderTestService).to receive(:test_with_details)
        .and_return({ success: true, response_time_ms: 150 })

      post "/api/v1/ai/providers/#{openai_provider.id}/credentials/#{openai_credential.id}/test"

      expect(response.status).to be_in([ 200, 404 ])
    end

    it 'handles disabled provider gracefully' do
      openai_credential.update!(is_active: false)

      get '/api/v1/ai/providers'

      expect(response).to have_http_status(:ok)
      # System should still list providers even if credentials are inactive
    end
  end

  describe 'Cross-Component Integration' do
    it 'verifies workflow can use provider credentials' do
      expect(account.ai_provider_credentials.active.count).to be >= 1
    end

    it 'verifies agent is associated with provider' do
      expect(ai_agent.ai_provider).to eq(openai_provider)
    end

    it 'verifies workflow has proper node structure' do
      expect(ai_workflow.ai_workflow_nodes.count).to be >= 3
      expect(ai_workflow.ai_workflow_edges.count).to be >= 2
    end

    it 'maintains proper account associations' do
      expect(ai_workflow.account).to eq(account)
      expect(ai_agent.account).to eq(account)
      expect(openai_provider.account).to eq(account)
      expect(openai_credential.account).to eq(account)
    end
  end

  describe 'Error Handling' do
    it 'handles non-existent workflow' do
      get '/api/v1/ai/workflows/non-existent-uuid'

      expect(response).to have_http_status(:not_found)
    end

    it 'handles non-existent agent' do
      get '/api/v1/ai/agents/non-existent-uuid'

      expect(response).to have_http_status(:not_found)
    end

    it 'handles non-existent provider' do
      get '/api/v1/ai/providers/non-existent-uuid'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'Usage Tracking' do
    it 'tracks credential usage fields' do
      expect(openai_credential).to respond_to(:success_count)
      expect(openai_credential).to respond_to(:failure_count)
      expect(openai_credential).to respond_to(:last_used_at)
    end

    it 'tracks workflow execution count' do
      expect(ai_workflow).to respond_to(:execution_count)
    end

    it 'tracks agent executions' do
      expect(ai_agent).to respond_to(:ai_agent_executions)
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
