# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Agents', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.create']) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.update']) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.delete']) }
  let(:user_with_execute_permission) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.execute']) }
  let(:user_with_update_and_execute_permission) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.update', 'ai.agents.execute']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/ai/agents' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_agent, 3, account: account)
    end

    context 'with ai.agents.read permission' do
      it 'returns list of agents' do
        get '/api/v1/ai/agents', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
      end

      it 'includes agent details' do
        get '/api/v1/ai/agents', headers: headers, as: :json

        data = json_response_data
        first_agent = data['items'].first

        expect(first_agent).to include('id', 'name', 'status', 'agent_type')
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/agents', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        create(:ai_agent, :inactive, account: account)

        get '/api/v1/ai/agents?status=inactive',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        statuses = data['items'].map { |a| a['status'] }
        expect(statuses.uniq).to eq(['inactive'])
      end

      it 'filters by agent_type' do
        create(:ai_agent, :code_assistant, account: account)

        get '/api/v1/ai/agents?agent_type=code_assistant',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        agent_types = data['items'].map { |a| a['agent_type'] }
        expect(agent_types.uniq).to eq(['code_assistant'])
      end

      it 'searches by name' do
        create(:ai_agent, name: 'Unique Search Agent', account: account)

        get '/api/v1/ai/agents?search=Unique%20Search',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        expect(data['items'].length).to eq(1)
        expect(data['items'].first['name']).to include('Unique Search')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/agents', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/agents', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/agents/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:agent) { create(:ai_agent, account: account) }

    context 'with ai.agents.read permission' do
      it 'returns agent details' do
        get "/api/v1/ai/agents/#{agent.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['agent']).to include(
          'id' => agent.id,
          'name' => agent.name,
          'agent_type' => agent.agent_type
        )
      end

      it 'includes provider information' do
        get "/api/v1/ai/agents/#{agent.id}", headers: headers, as: :json

        data = json_response_data
        expect(data['agent']).to have_key('provider')
      end

      it 'includes mcp capabilities' do
        get "/api/v1/ai/agents/#{agent.id}", headers: headers, as: :json

        data = json_response_data
        expect(data['agent']).to have_key('mcp_capabilities')
      end
    end

    context 'when agent does not exist' do
      it 'returns not found error' do
        get '/api/v1/ai/agents/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when accessing other account agent' do
      let(:other_account) { create(:account) }
      let(:other_agent) { create(:ai_agent, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/agents/#{other_agent.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/agents' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:provider) { create(:ai_provider, account: account) }

    context 'with ai.agents.create permission' do
      let(:valid_params) do
        {
          agent: {
            name: 'New Test Agent',
            description: 'A test agent for processing',
            agent_type: 'assistant',
            ai_provider_id: provider.id,
            mcp_capabilities: ['text_generation']
          }
        }
      end

      it 'creates a new agent' do
        expect {
          post '/api/v1/ai/agents', params: valid_params, headers: headers, as: :json
        }.to change(Ai::Agent, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['agent']['name']).to eq('New Test Agent')
      end

      it 'sets current user as creator' do
        post '/api/v1/ai/agents', params: valid_params, headers: headers, as: :json

        data = json_response_data
        expect(data['agent']['created_by']).to include('id' => user_with_create_permission.id)
      end
    end

    context 'with invalid data' do
      it 'returns validation error for blank name' do
        post '/api/v1/ai/agents',
             params: { agent: { name: '' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/ai/agents',
             params: { agent: { name: 'Test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/ai/agents/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:agent) { create(:ai_agent, account: account) }

    context 'with ai.agents.update permission' do
      it 'updates agent successfully' do
        put "/api/v1/ai/agents/#{agent.id}",
            params: { agent: { description: 'Updated description' } },
            headers: headers,
            as: :json

        expect_success_response

        agent.reload
        expect(agent.description).to eq('Updated description')
      end

      it 'updates agent name' do
        put "/api/v1/ai/agents/#{agent.id}",
            params: { agent: { name: 'Updated Name' } },
            headers: headers,
            as: :json

        expect_success_response

        agent.reload
        expect(agent.name).to eq('Updated Name')
      end
    end
  end

  describe 'DELETE /api/v1/ai/agents/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:agent) { create(:ai_agent, account: account) }

    context 'with ai.agents.delete permission' do
      it 'deletes agent successfully' do
        agent_id = agent.id

        delete "/api/v1/ai/agents/#{agent_id}", headers: headers, as: :json

        expect_success_response
        expect(Ai::Agent.find_by(id: agent_id)).to be_nil
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        delete "/api/v1/ai/agents/#{agent.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:id/clone' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let!(:agent) { create(:ai_agent, account: account, name: 'Original Agent') }

    context 'with ai.agents.create permission' do
      it 'creates a clone of the agent' do
        expect {
          post "/api/v1/ai/agents/#{agent.id}/clone", headers: headers, as: :json
        }.to change(Ai::Agent, :count).by(1)

        expect_success_response
        data = json_response_data

        expect(data['agent']['name']).to include('Original Agent')
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:id/pause' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:agent) { create(:ai_agent, account: account, status: 'active') }

    context 'with ai.agents.execute permission' do
      it 'pauses the agent' do
        post "/api/v1/ai/agents/#{agent.id}/pause", headers: headers, as: :json

        expect_success_response

        agent.reload
        expect(agent.status).to eq('paused')
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:id/resume' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:agent) { create(:ai_agent, account: account, status: 'paused') }

    context 'with ai.agents.execute permission' do
      it 'resumes the agent' do
        post "/api/v1/ai/agents/#{agent.id}/resume", headers: headers, as: :json

        expect_success_response

        agent.reload
        expect(agent.status).to eq('active')
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:id/archive' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:agent) { create(:ai_agent, account: account) }

    context 'with ai.agents.execute permission' do
      it 'archives the agent' do
        post "/api/v1/ai/agents/#{agent.id}/archive", headers: headers, as: :json

        expect_success_response

        agent.reload
        expect(agent.status).to eq('archived')
      end
    end
  end

  describe 'GET /api/v1/ai/agents/:id/stats' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:agent) { create(:ai_agent, account: account) }

    context 'with ai.agents.read permission' do
      it 'returns agent statistics' do
        get "/api/v1/ai/agents/#{agent.id}/stats", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('stats')
        expect(data['stats']).to have_key('total_executions')
      end
    end
  end

  describe 'GET /api/v1/ai/agents/my_agents' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_agent, 2, account: account, creator: user_with_read_permission)
      create(:ai_agent, account: account) # Created by someone else
    end

    context 'with ai.agents.read permission' do
      it 'returns only agents created by current user' do
        get '/api/v1/ai/agents/my_agents', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items'].length).to eq(2)
        creator_ids = data['items'].map { |a| a['created_by']&.dig('id') }
        expect(creator_ids.uniq).to eq([user_with_read_permission.id])
      end
    end
  end

  describe 'GET /api/v1/ai/agents/agent_types' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    context 'with ai.agents.read permission' do
      it 'returns available agent types' do
        get '/api/v1/ai/agents/agent_types', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['agent_types']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/ai/agents/statistics' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_agent, 3, account: account)
    end

    context 'with ai.agents.read permission' do
      it 'returns overall agent statistics' do
        get '/api/v1/ai/agents/statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['statistics']).to have_key('total_agents')
      end
    end
  end
end
