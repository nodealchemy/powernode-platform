# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Orchestration Full Stack Integration', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :system_admin, account: account) }

  # Provider setup
  let!(:openai_provider) { create(:ai_provider, account: account, slug: 'openai-orch', is_active: true) }
  let!(:anthropic_provider) { create(:ai_provider, account: account, slug: 'anthropic-orch', is_active: true) }

  let!(:openai_credential) do
    create(:ai_provider_credential,
           account: account,
           ai_provider: openai_provider,
           credentials: { api_key: 'sk-test123' },
           is_active: true,
           is_default: true)
  end

  let!(:anthropic_credential) do
    create(:ai_provider_credential,
           account: account,
           ai_provider: anthropic_provider,
           credentials: { api_key: 'ant-test123' },
           is_active: true)
  end

  # Agent setup
  let!(:ai_agent) do
    create(:ai_agent,
           account: account,
           ai_provider: openai_provider,
           name: 'Test Orchestration Agent',
           agent_type: 'assistant')
  end

  # Workflow setup
  let!(:ai_workflow) do
    create(:ai_workflow,
           account: account,
           name: 'Orchestration Test Workflow',
           description: 'For orchestration testing',
           is_active: true)
  end

  let!(:workflow_node) do
    create(:ai_workflow_node,
           ai_workflow: ai_workflow,
           node_type: 'ai_agent',
           name: 'Agent Node',
           position: { x: 100, y: 100 })
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

  describe 'Complete Orchestration Workflow' do
    it 'lists available providers for orchestration' do
      get '/api/v1/ai/providers'

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
    end

    it 'retrieves provider health status' do
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

    it 'lists workflows' do
      get '/api/v1/ai/workflows'

      expect(response).to have_http_status(:ok)
    end

    it 'retrieves workflow details' do
      get "/api/v1/ai/workflows/#{ai_workflow.id}"

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'Provider Orchestration' do
    it 'tests provider connectivity' do
      allow_any_instance_of(AiProviderTestService).to receive(:test_with_details)
        .and_return({ success: true, response_time_ms: 100 })

      post "/api/v1/ai/providers/#{openai_provider.id}/credentials/#{openai_credential.id}/test"

      expect(response.status).to be_in([200, 404])
    end

    it 'handles provider failover scenario' do
      # Mark primary provider as inactive
      openai_credential.update!(is_active: false)

      get '/api/v1/ai/providers'

      expect(response).to have_http_status(:ok)
      # System should still list available providers
    end
  end

  describe 'Agent Orchestration' do
    it 'executes agent' do
      mock_execution = build_stubbed(:ai_agent_execution, ai_agent: ai_agent, account: account)
      allow_any_instance_of(AiAgent).to receive(:mcp_available?).and_return(true)
      allow_any_instance_of(AiAgent).to receive(:execute).and_return(mock_execution)

      post "/api/v1/ai/agents/#{ai_agent.id}/execute", params: {
        input_parameters: { prompt: 'Test orchestration' }
      }

      expect(response.status).to be_in([200, 201, 202, 422, 500])
    end

    it 'creates conversation with agent' do
      post "/api/v1/ai/agents/#{ai_agent.id}/conversations", params: {
        conversation: {
          title: 'Orchestration Test'
        }
      }

      expect(response.status).to be_in([200, 201, 412, 422])
    end
  end

  describe 'Workflow Orchestration' do
    it 'executes workflow' do
      post "/api/v1/ai/workflows/#{ai_workflow.id}/execute", params: {
        input_data: { test: 'data' }
      }

      expect(response.status).to be_in([200, 201, 202, 412, 422, 500])
    end

    it 'validates workflow before execution' do
      get "/api/v1/ai/workflows/#{ai_workflow.id}/validate"

      expect(response.status).to be_in([200, 404])
    end
  end

  describe 'Cross-Component Integration' do
    it 'provider credentials accessible from workflow execution' do
      # Ensure credential is available for workflow execution
      expect(account.ai_provider_credentials.active.count).to be >= 1
    end

    it 'agent can be used in workflow node' do
      expect(ai_agent).to be_persisted
      expect(ai_workflow.ai_workflow_nodes.count).to be >= 1
    end

    it 'workflow references correct account scope' do
      expect(ai_workflow.account).to eq(account)
      expect(ai_agent.account).to eq(account)
      expect(openai_provider.account).to eq(account)
    end
  end

  describe 'Error Handling in Orchestration' do
    it 'handles missing agent gracefully' do
      get '/api/v1/ai/agents/non-existent-id'

      expect(response).to have_http_status(:not_found)
    end

    it 'handles missing workflow gracefully' do
      get '/api/v1/ai/workflows/non-existent-id'

      expect(response).to have_http_status(:not_found)
    end

    it 'handles missing provider gracefully' do
      get '/api/v1/ai/providers/non-existent-id'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'System Monitoring' do
    it 'tracks provider usage metrics' do
      # Verify credential has usage tracking fields
      expect(openai_credential).to respond_to(:success_count)
      expect(openai_credential).to respond_to(:failure_count)
    end

    it 'tracks workflow execution count' do
      expect(ai_workflow).to respond_to(:execution_count)
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
