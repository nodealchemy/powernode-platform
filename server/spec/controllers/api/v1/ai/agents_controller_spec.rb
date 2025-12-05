# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AgentsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.create', 'ai.agents.update', 'ai.agents.delete', 'ai.agents.execute']) }
  let(:admin_user) { create(:user, :system_admin, account: account) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:other_account_user) { create(:user) }

  let(:ai_provider) { create(:ai_provider, :openai, account: account, is_active: true) }
  let(:ai_credential) { create(:ai_provider_credential, account: account, ai_provider: ai_provider) }

  let!(:agent) do
    create(:ai_agent,
           account: account,
           creator: user,
           name: 'Test Agent',
           agent_type: 'assistant',
           status: 'active',
           ai_provider: ai_provider)
  end

  let!(:other_account_agent) do
    create(:ai_agent,
           account: other_account_user.account,
           creator: other_account_user)
  end

  before do
    sign_in_as_user(user)
  end

  describe 'GET #index' do
    let!(:agent2) { create(:ai_agent, account: account, creator: user, name: 'Agent 2') }
    let!(:agent3) { create(:ai_agent, account: account, creator: user, name: 'Agent 3', status: 'inactive') }

    context 'with valid permissions' do
      it 'returns all agents for current account' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true

        agent_ids = json_response['data']['items'].map { |a| a['id'] }
        expect(agent_ids).to include(agent.id, agent2.id, agent3.id)
        expect(agent_ids).not_to include(other_account_agent.id)
      end

      it 'includes pagination metadata' do
        create_list(:ai_agent, 15, account: account, creator: user)

        get :index, params: { per_page: 10, page: 2 }

        expect(response).to have_http_status(:ok)
        pagination = json_response['data']['pagination']
        expect(pagination['current_page']).to eq(2)
        expect(pagination['total_pages']).to be >= 2
      end

      it 'filters by agent_type' do
        create(:ai_agent, account: account, creator: user, agent_type: 'code_assistant')

        get :index, params: { agent_type: 'assistant' }

        agent_types = json_response['data']['items'].map { |a| a['agent_type'] }
        expect(agent_types).to all(eq('assistant'))
      end

      it 'filters by status' do
        get :index, params: { status: 'active' }

        statuses = json_response['data']['items'].map { |a| a['status'] }
        expect(statuses).to all(eq('active'))
      end

      it 'supports search functionality' do
        searchable_agent = create(:ai_agent, account: account, creator: user, name: 'Searchable Special Agent')

        get :index, params: { search: 'Searchable' }

        agent_names = json_response['data']['items'].map { |a| a['name'] }
        expect(agent_names).to include('Searchable Special Agent')
      end

      it 'includes agent metadata in response' do
        get :index

        first_agent = json_response['data']['items'].first
        expect(first_agent).to include(
          'id',
          'name',
          'description',
          'agent_type',
          'status',
          'created_at',
          'updated_at',
          'created_by',
          'ai_provider',
          'execution_stats'
        )
      end
    end

    context 'without proper permissions' do
      let(:user_without_permissions) { create(:user, account: account, permissions: []) }

      before do
        sign_in_as_user(user_without_permissions)
      end

      it 'denies access without read permissions' do
        get :index

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #show' do
    context 'with valid agent' do
      it 'returns detailed agent information' do
        get :show, params: { id: agent.id }

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true

        agent_data = json_response['data']['agent']
        expect(agent_data['id']).to eq(agent.id)
        expect(agent_data).to include(
          'name',
          'description',
          'agent_type',
          'status',
          'created_at',
          'updated_at',
          'created_by',
          'ai_provider',
          'execution_stats',
          'detailed_stats'
        )
      end

      it 'includes MCP capabilities' do
        agent.update!(mcp_capabilities: ['tool_use', 'function_calling'])

        get :show, params: { id: agent.id }

        agent_data = json_response['data']['agent']
        expect(agent_data['mcp_capabilities']).to contain_exactly('tool_use', 'function_calling')
      end
    end

    context 'with invalid agent' do
      it 'returns 404 for non-existent agent' do
        get :show, params: { id: 'non-existent-id' }

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to eq('Agent not found')
      end

      it 'returns 404 for other account agent' do
        get :show, params: { id: other_account_agent.id }

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to eq('Agent not found')
      end
    end
  end

  describe 'POST #create' do
    let(:valid_agent_params) do
      {
        agent: {
          name: 'New Test Agent',
          description: 'An agent for testing',
          agent_type: 'assistant',
          ai_provider_id: ai_provider.id,
          mcp_capabilities: ['tool_use'],
          is_public: false
        }
      }
    end

    context 'with valid parameters' do
      it 'creates new agent' do
        expect {
          post :create, params: valid_agent_params
        }.to change { AiAgent.count }.by(1)

        expect(response).to have_http_status(:created)
        expect(json_response['success']).to be true

        created_agent = AiAgent.last
        expect(created_agent.name).to eq('New Test Agent')
        expect(created_agent.account).to eq(account)
        expect(created_agent.creator).to eq(user)
        expect(created_agent.status).to eq('inactive')
      end

      it 'sets default status to inactive' do
        post :create, params: valid_agent_params

        created_agent = AiAgent.last
        expect(created_agent.status).to eq('inactive')
      end

      it 'creates audit log entry' do
        expect {
          post :create, params: valid_agent_params
        }.to change { AuditLog.count }.by_at_least(1)

        audit_log = AuditLog.where(resource_type: 'AiAgent', action: 'created').last
        expect(audit_log).to be_present
      end
    end

    context 'with invalid parameters' do
      it 'returns validation errors for missing name' do
        invalid_params = valid_agent_params.deep_dup
        invalid_params[:agent][:name] = ''

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['details']['errors'].join(' ')).to include('Name')
      end

      it 'returns validation errors for invalid provider' do
        invalid_params = valid_agent_params.deep_dup
        invalid_params[:agent][:ai_provider_id] = 'invalid-id'

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without create permissions' do
      before do
        sign_in_as_user(read_only_user)
      end

      it 'denies access without create permissions' do
        post :create, params: valid_agent_params

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH #update' do
    let(:update_params) do
      {
        id: agent.id,
        agent: {
          name: 'Updated Agent Name',
          description: 'Updated description'
        }
      }
    end

    context 'with valid parameters' do
      it 'updates agent' do
        patch :update, params: update_params

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true

        agent.reload
        expect(agent.name).to eq('Updated Agent Name')
        expect(agent.description).to eq('Updated description')
      end

      it 'creates audit log entry' do
        expect {
          patch :update, params: update_params
        }.to change { AuditLog.count }.by_at_least(1)

        audit_log = AuditLog.where(resource_type: 'AiAgent', action: 'updated').last
        expect(audit_log).to be_present
      end
    end

    context 'with other account agent' do
      it 'returns 404 for other account agent' do
        patch :update, params: {
          id: other_account_agent.id,
          agent: { name: 'Hacked' }
        }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'with valid agent' do
      it 'deletes agent' do
        agent_id = agent.id

        delete :destroy, params: { id: agent_id }

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(AiAgent.exists?(agent_id)).to be false
      end

      it 'creates audit log entry' do
        expect {
          delete :destroy, params: { id: agent.id }
        }.to change { AuditLog.count }.by_at_least(1)

        audit_log = AuditLog.where(resource_type: 'AiAgent', action: 'deleted').last
        expect(audit_log).to be_present
      end
    end

    context 'without delete permissions' do
      before do
        sign_in_as_user(read_only_user)
      end

      it 'denies access without delete permissions' do
        delete :destroy, params: { id: agent.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #execute' do
    let(:execution_params) do
      {
        id: agent.id,
        input_parameters: {
          message: 'Hello, AI!'
        }
      }
    end

    context 'with valid agent' do
      before do
        allow_any_instance_of(AiAgent).to receive(:execute).and_return(
          create(:ai_agent_execution, ai_agent: agent, user: user, status: 'running')
        )
      end

      it 'creates agent execution' do
        post :execute, params: execution_params

        expect(response).to have_http_status(:created)
        expect(json_response['success']).to be true
        expect(json_response['data']).to include('execution', 'agent')
      end

      it 'creates audit log entry' do
        expect {
          post :execute, params: execution_params
        }.to change { AuditLog.count }.by_at_least(1)

        # Execute creates an AiAgentExecution record which triggers audit log
        audit_log = AuditLog.where(resource_type: 'AiAgentExecution', action: 'created').last
        expect(audit_log).to be_present
      end
    end

    context 'with agent not ready for execution' do
      before do
        agent.update!(status: 'inactive')
        allow_any_instance_of(AiAgent).to receive(:mcp_available?).and_return(false)
      end

      it 'returns error when agent not available' do
        post :execute, params: execution_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to include('cannot be executed')
      end
    end
  end

  describe 'POST #clone' do
    it 'clones agent for current account' do
      expect_any_instance_of(AiAgent).to receive(:clone_for_account)
        .with(account, user)
        .and_return(create(:ai_agent, account: account, creator: user))

      post :clone, params: { id: agent.id }

      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
      expect(json_response['data']).to include('agent')
    end
  end

  describe 'POST #test' do
    let(:test_params) do
      {
        id: agent.id,
        test_input: { message: 'Test message' }
      }
    end

    it 'runs test execution without persisting' do
      expect_any_instance_of(AiAgent).to receive(:test_execution)
        .with({ message: 'Test message' }, user)
        .and_return({ success: true, output: 'Test response' })

      post :test, params: test_params

      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']).to include('test_result')
    end
  end

  describe 'GET #validate' do
    it 'validates agent configuration' do
      allow_any_instance_of(AiAgent).to receive(:validate_configuration)
        .and_return({ valid: true })

      get :validate, params: { id: agent.id }

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['valid']).to be true
    end

    it 'returns validation errors' do
      allow_any_instance_of(AiAgent).to receive(:validate_configuration)
        .and_return({
          valid: false,
          errors: ['Missing system prompt'],
          warnings: ['High temperature setting']
        })

      get :validate, params: { id: agent.id }

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['valid']).to be false
      expect(json_response['data']['errors']).to include('Missing system prompt')
      expect(json_response['data']['warnings']).to include('High temperature setting')
    end
  end

  describe 'POST #pause' do
    before { agent.update!(status: 'active') }

    it 'pauses active agent' do
      post :pause, params: { id: agent.id }

      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      agent.reload
      expect(agent.status).to eq('paused')
    end

    it 'returns error when agent not active' do
      agent.update!(status: 'inactive')

      post :pause, params: { id: agent.id }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['error']).to include('must be active')
    end
  end

  describe 'POST #resume' do
    before { agent.update!(status: 'paused') }

    it 'resumes paused agent' do
      post :resume, params: { id: agent.id }

      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      agent.reload
      expect(agent.status).to eq('active')
    end
  end

  describe 'POST #archive' do
    it 'archives agent' do
      post :archive, params: { id: agent.id }

      expect(response).to have_http_status(:ok)
      agent.reload
      expect(agent.status).to eq('archived')
    end
  end

  describe 'GET #stats' do
    let!(:execution1) { create(:ai_agent_execution, ai_agent: agent, status: 'completed', cost_usd: 0.01) }
    let!(:execution2) { create(:ai_agent_execution, ai_agent: agent, status: 'failed', error_message: 'Test error') }

    it 'returns agent statistics' do
      get :stats, params: { id: agent.id }

      expect(response).to have_http_status(:ok)
      stats = json_response['data']['stats']
      expect(stats).to include(
        'total_executions',
        'successful_executions',
        'failed_executions',
        'running_executions',
        'total_cost',
        'success_rate'
      )
      expect(stats['total_executions']).to eq(2)
      expect(stats['successful_executions']).to eq(1)
      expect(stats['failed_executions']).to eq(1)
    end
  end

  describe 'GET #analytics' do
    before do
      create_list(:ai_agent_execution, 5, ai_agent: agent, created_at: 2.days.ago)
    end

    it 'returns agent analytics' do
      get :analytics, params: { id: agent.id, date_range: 7 }

      expect(response).to have_http_status(:ok)
      analytics = json_response['data']['analytics']
      expect(analytics).to include(
        'executions_over_time',
        'status_distribution',
        'average_cost_per_day',
        'performance_metrics'
      )
    end
  end

  describe 'GET #my_agents' do
    let!(:my_agent) { create(:ai_agent, account: account, creator: user) }
    let!(:other_user_agent) { create(:ai_agent, account: account, creator: admin_user) }

    it 'returns only current user agents' do
      get :my_agents

      expect(response).to have_http_status(:ok)
      agent_creators = json_response['data']['items'].map { |a| a['created_by']['id'] }
      expect(agent_creators).to all(eq(user.id))
    end
  end

  describe 'GET #public_agents' do
    let!(:public_agent) { create(:ai_agent, account: account, creator: user, is_public: true) }
    let!(:private_agent) { create(:ai_agent, account: account, creator: user, is_public: false) }

    it 'returns only public agents' do
      get :public_agents

      expect(response).to have_http_status(:ok)
      agent_ids = json_response['data']['items'].map { |a| a['id'] }
      expect(agent_ids).to include(public_agent.id)
      expect(agent_ids).not_to include(private_agent.id)
    end
  end

  describe 'GET #agent_types' do
    it 'returns available agent types' do
      get :agent_types

      expect(response).to have_http_status(:ok)
      agent_types = json_response['data']['agent_types']
      expect(agent_types).to be_an(Array)
      expect(agent_types.first).to include('value', 'label', 'description')
    end
  end

  describe 'GET #statistics' do
    before do
      create_list(:ai_agent, 5, account: account, creator: user, status: 'active')
      create(:ai_agent, account: account, creator: user, status: 'paused')
    end

    it 'returns account-wide agent statistics' do
      get :statistics

      expect(response).to have_http_status(:ok)
      stats = json_response['data']['statistics']
      expect(stats).to include(
        'total_agents',
        'active_agents',
        'paused_agents',
        'total_executions',
        'agents_by_type'
      )
    end
  end

  describe 'nested executions' do
    let!(:execution) { create(:ai_agent_execution, ai_agent: agent, user: user) }

    describe 'GET #executions_index' do
      it 'returns executions for specific agent' do
        get :executions_index, params: { agent_id: agent.id }

        expect(response).to have_http_status(:ok)
        execution_ids = json_response['data']['items'].map { |e| e['execution_id'] }
        expect(execution_ids).to include(execution.execution_id)
      end
    end

    describe 'GET #execution_show' do
      it 'returns detailed execution information' do
        get :execution_show, params: { agent_id: agent.id, execution_id: execution.execution_id }

        expect(response).to have_http_status(:ok)
        execution_data = json_response['data']['execution']
        expect(execution_data['execution_id']).to eq(execution.execution_id)
      end
    end

    describe 'POST #execution_cancel' do
      before do
        execution.update!(status: 'running')
        allow_any_instance_of(AiAgentExecution).to receive(:cancel_execution!)
      end

      it 'cancels running execution' do
        post :execution_cancel, params: { agent_id: agent.id, execution_id: execution.execution_id, reason: 'Test cancellation' }

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
      end
    end

    describe 'POST #execution_retry' do
      before do
        execution.update!(status: 'failed', error_message: 'Previous failure')
        allow_any_instance_of(AiAgent).to receive(:execute).and_return(
          create(:ai_agent_execution, ai_agent: agent, user: user)
        )
      end

      it 'retries failed execution' do
        post :execution_retry, params: { agent_id: agent.id, execution_id: execution.execution_id }

        expect(response).to have_http_status(:created)
        expect(json_response['success']).to be true
      end
    end

    describe 'GET #execution_logs' do
      it 'returns execution logs' do
        get :execution_logs, params: { agent_id: agent.id, execution_id: execution.execution_id }

        expect(response).to have_http_status(:ok)
        expect(json_response['data']).to include('logs', 'execution_id')
      end
    end
  end
end
