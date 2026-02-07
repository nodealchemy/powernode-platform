# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::CommunityAgents', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.create', 'ai.agents.update', 'ai.agents.delete']) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['ai.agents.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:other_headers) { auth_headers_for(other_user) }

  # Helper to create a community agent with required associations
  let(:create_community_agent) do
    ->(attrs = {}) {
      agent = create(:ai_agent, account: attrs.delete(:owner_account) || account)
      defaults = {
        owner_account: account,
        agent: agent,
        status: 'active',
        published_at: Time.current
      }
      create(:community_agent, defaults.merge(attrs))
    }
  end

  describe 'GET /api/v1/ai/community/agents' do
    before do
      3.times { create_community_agent.call }
    end

    context 'with authentication' do
      it 'returns list of published community agents' do
        get '/api/v1/ai/community/agents', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/community/agents', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by category' do
        create_community_agent.call(category: 'analysis')

        get '/api/v1/ai/community/agents?category=analysis', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        categories = data['items'].map { |a| a['category'] }
        expect(categories.uniq).to eq(['analysis'])
      end

      it 'filters by verified status' do
        create_community_agent.call(verified: true)

        get '/api/v1/ai/community/agents?verified=true', headers: headers, as: :json

        expect_success_response
      end

      it 'searches by query' do
        create_community_agent.call(name: 'Unique Search Bot')

        get '/api/v1/ai/community/agents?query=Unique%20Search', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        names = data['items'].map { |a| a['name'] }
        expect(names).to include('Unique Search Bot')
      end

      it 'sorts by popular' do
        get '/api/v1/ai/community/agents?sort=popular', headers: headers, as: :json

        expect_success_response
      end

      it 'sorts by rating' do
        get '/api/v1/ai/community/agents?sort=rating', headers: headers, as: :json

        expect_success_response
      end

      it 'sorts by recent' do
        get '/api/v1/ai/community/agents?sort=recent', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/community/agents', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/community/agents/:id' do
    let(:community_agent) { create_community_agent.call }

    context 'with authentication' do
      it 'returns agent details' do
        get "/api/v1/ai/community/agents/#{community_agent.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['agent']).to include('id' => community_agent.id)
      end
    end

    context 'when agent does not exist' do
      it 'returns not found error' do
        get '/api/v1/ai/community/agents/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/ai/community/agents/#{community_agent.id}", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/ai/community/agents' do
    let(:agent) { create(:ai_agent, account: account) }

    context 'with valid params' do
      let(:valid_params) do
        {
          agent: {
            name: 'New Community Agent',
            description: 'A published community agent for testing',
            endpoint_url: 'https://agent.example.com/.well-known/agent.json',
            category: 'automation',
            visibility: 'public',
            agent_id: agent.id
          }
        }
      end

      it 'creates a new community agent' do
        expect {
          post '/api/v1/ai/community/agents', params: valid_params, headers: headers, as: :json
        }.to change(CommunityAgent, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['agent']).to be_present
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/ai/community/agents',
             params: { agent: { name: 'Test' } },
             as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PUT /api/v1/ai/community/agents/:id' do
    let(:community_agent) { create_community_agent.call }

    context 'when owner updates their own agent' do
      it 'updates the agent successfully' do
        put "/api/v1/ai/community/agents/#{community_agent.id}",
            params: { agent: { description: 'Updated description for agent' } },
            headers: headers,
            as: :json

        expect_success_response
      end
    end

    context 'when non-owner tries to update' do
      it 'returns forbidden error' do
        put "/api/v1/ai/community/agents/#{community_agent.id}",
            params: { agent: { description: 'Unauthorized update' } },
            headers: other_headers,
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/ai/community/agents/:id' do
    let(:community_agent) { create_community_agent.call }

    context 'when owner deletes their own agent' do
      it 'deletes the agent successfully' do
        agent_id = community_agent.id

        delete "/api/v1/ai/community/agents/#{agent_id}", headers: headers, as: :json

        expect_success_response
        expect(CommunityAgent.find_by(id: agent_id)).to be_nil
      end
    end

    context 'when non-owner tries to delete' do
      it 'returns forbidden error' do
        delete "/api/v1/ai/community/agents/#{community_agent.id}",
               headers: other_headers,
               as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/community/agents/:id/publish' do
    let(:community_agent) { create_community_agent.call(status: 'pending', published_at: nil) }

    context 'when owner publishes their own agent' do
      it 'publishes the agent' do
        post "/api/v1/ai/community/agents/#{community_agent.id}/publish",
             headers: headers,
             as: :json

        expect_success_response

        community_agent.reload
        expect(community_agent.status).to eq('active')
        expect(community_agent.published_at).not_to be_nil
      end
    end

    context 'when non-owner tries to publish' do
      it 'returns forbidden error' do
        post "/api/v1/ai/community/agents/#{community_agent.id}/publish",
             headers: other_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/community/agents/:id/unpublish' do
    let(:community_agent) { create_community_agent.call }

    context 'when owner unpublishes their own agent' do
      it 'unpublishes the agent' do
        post "/api/v1/ai/community/agents/#{community_agent.id}/unpublish",
             headers: headers,
             as: :json

        expect_success_response

        community_agent.reload
        expect(community_agent.published_at).to be_nil
        expect(community_agent.visibility).to eq('private')
      end
    end

    context 'when non-owner tries to unpublish' do
      it 'returns forbidden error' do
        post "/api/v1/ai/community/agents/#{community_agent.id}/unpublish",
             headers: other_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/community/agents/:id/rate' do
    let(:community_agent) { create_community_agent.call }

    context 'with valid rating params' do
      it 'rates the agent' do
        post "/api/v1/ai/community/agents/#{community_agent.id}/rate",
             params: { rating: { score: 5, review: 'Excellent agent!' } },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('rating')
        expect(data).to have_key('agent')
      end
    end
  end

  describe 'POST /api/v1/ai/community/agents/:id/report' do
    let(:community_agent) { create_community_agent.call }

    context 'with valid report params' do
      it 'submits a report' do
        post "/api/v1/ai/community/agents/#{community_agent.id}/report",
             params: { report: { reason: 'spam', description: 'This agent is spam' } },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to include('Report submitted')
      end
    end
  end

  describe 'GET /api/v1/ai/community/agents/my_agents' do
    before do
      2.times { create_community_agent.call }
      # Agent from another account
      other_agent = create(:ai_agent, account: other_account)
      create(:community_agent, owner_account: other_account, agent: other_agent,
             status: 'active', published_at: Time.current)
    end

    context 'with authentication' do
      it 'returns only agents owned by current account' do
        get '/api/v1/ai/community/agents/my_agents', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(2)
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/community/agents/my_agents', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end
    end
  end

  describe 'GET /api/v1/ai/community/agents/categories' do
    before do
      create_community_agent.call(category: 'automation')
      create_community_agent.call(category: 'analysis')
    end

    context 'with authentication' do
      it 'returns available categories' do
        get '/api/v1/ai/community/agents/categories', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['categories']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/ai/community/agents/skills' do
    before do
      create_community_agent.call
    end

    context 'with authentication' do
      it 'returns available skills' do
        get '/api/v1/ai/community/agents/skills', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['skills']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/community/agents/discover' do
    context 'with valid task description' do
      it 'discovers agents based on task description' do
        allow(A2a::Skills::CommunitySkills).to receive(:discover_agents).and_return(
          agents: [],
          query_analyzed: 'test analysis'
        )

        post '/api/v1/ai/community/agents/discover',
             params: { task_description: 'I need an agent for code analysis' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('agents')
      end
    end

    context 'without task description' do
      it 'returns error' do
        post '/api/v1/ai/community/agents/discover',
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # Account isolation tests
  describe 'account isolation' do
    let(:own_agent) { create_community_agent.call }
    let(:other_agent) do
      agent = create(:ai_agent, account: other_account)
      create(:community_agent, owner_account: other_account, agent: agent,
             status: 'active', published_at: Time.current)
    end

    it 'cannot update agents owned by another account' do
      put "/api/v1/ai/community/agents/#{other_agent.id}",
          params: { agent: { description: 'Hack attempt' } },
          headers: headers,
          as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'cannot delete agents owned by another account' do
      delete "/api/v1/ai/community/agents/#{other_agent.id}",
             headers: headers,
             as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'cannot publish agents owned by another account' do
      post "/api/v1/ai/community/agents/#{other_agent.id}/publish",
           headers: headers,
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
