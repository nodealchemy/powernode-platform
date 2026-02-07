# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::AgentCards', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: [ 'ai.agents.read' ]) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: [ 'ai.agents.read', 'ai.agents.create' ]) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: [ 'ai.agents.read', 'ai.agents.update' ]) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: [ 'ai.agents.read', 'ai.agents.delete' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/ai/agent_cards' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_agent_card, 3, :published, account: account)
    end

    context 'with ai.agents.read permission' do
      it 'returns list of agent cards' do
        get '/api/v1/ai/agent_cards', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
      end

      it 'includes card details' do
        get '/api/v1/ai/agent_cards', headers: headers, as: :json

        data = json_response_data
        first_card = data['items'].first

        expect(first_card).to include('id', 'name', 'status', 'visibility')
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/agent_cards', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by visibility' do
        create(:ai_agent_card, :public, :published, account: account)

        get '/api/v1/ai/agent_cards?visibility=public',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        visibilities = data['items'].map { |c| c['visibility'] }
        expect(visibilities.uniq).to eq([ 'public' ])
      end

      it 'filters by status' do
        create(:ai_agent_card, :deprecated, account: account)

        get '/api/v1/ai/agent_cards?status=deprecated',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        statuses = data['items'].map { |c| c['status'] }
        expect(statuses.uniq).to eq([ 'deprecated' ])
      end

      it 'searches by name' do
        create(:ai_agent_card, :published, name: 'Unique Search Card', account: account)

        get '/api/v1/ai/agent_cards?query=Unique%20Search',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        expect(data['items'].length).to eq(1)
        expect(data['items'].first['name']).to include('Unique Search')
      end

      it 'filters by skill capability' do
        create(:ai_agent_card, :published, account: account, capabilities: {
          'skills' => [ { 'id' => 'summarize', 'name' => 'Summarize' } ]
        })

        get '/api/v1/ai/agent_cards?skill=summarize',
            headers: headers,
            as: :json

        expect_success_response
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/agent_cards', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/agent_cards/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:agent_card) { create(:ai_agent_card, :published, account: account) }

    it 'returns agent card details' do
      get "/api/v1/ai/agent_cards/#{agent_card.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data

      expect(data['agent_card']['id']).to eq(agent_card.id)
      expect(data['agent_card']['name']).to eq(agent_card.name)
    end

    it 'returns 404 for non-existent card' do
      get '/api/v1/ai/agent_cards/non-existent-id', headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/ai/agent_cards/:id/a2a' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:agent_card) { create(:ai_agent_card, :published, :with_multiple_skills, account: account) }

    it 'returns A2A-compliant JSON' do
      get "/api/v1/ai/agent_cards/#{agent_card.id}/a2a", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json).to include('name', 'version', 'skills')
    end
  end

  describe 'POST /api/v1/ai/agent_cards' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:agent) { create(:ai_agent, account: account) }
    let(:valid_params) do
      {
        agent_card: {
          name: 'New Agent Card',
          description: 'A test agent card',
          visibility: 'private',
          ai_agent_id: agent.id,
          capabilities: {
            'skills' => [ { 'id' => 'test', 'name' => 'Test Skill' } ]
          }
        }
      }
    end

    context 'with valid params' do
      it 'creates a new agent card' do
        expect {
          post '/api/v1/ai/agent_cards', headers: headers, params: valid_params, as: :json
        }.to change { Ai::AgentCard.count }.by(1)

        expect(response).to have_http_status(:created)
      end

      it 'returns the created card' do
        post '/api/v1/ai/agent_cards', headers: headers, params: valid_params, as: :json

        data = json_response_data
        expect(data['agent_card']['name']).to eq('New Agent Card')
      end
    end

    context 'with invalid params' do
      it 'returns validation errors for missing name' do
        post '/api/v1/ai/agent_cards',
             headers: headers,
             params: { agent_card: { description: 'No name' } },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns validation errors for duplicate name in account' do
        create(:ai_agent_card, name: 'Duplicate Name', account: account)

        post '/api/v1/ai/agent_cards',
             headers: headers,
             params: { agent_card: { name: 'Duplicate Name' } },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/ai/agent_cards', headers: headers, params: valid_params, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/ai/agent_cards/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:agent_card) { create(:ai_agent_card, account: account) }

    it 'updates the agent card' do
      patch "/api/v1/ai/agent_cards/#{agent_card.id}",
            headers: headers,
            params: { agent_card: { description: 'Updated description' } },
            as: :json

      expect_success_response
      expect(agent_card.reload.description).to eq('Updated description')
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        patch "/api/v1/ai/agent_cards/#{agent_card.id}",
              headers: headers,
              params: { agent_card: { description: 'Updated' } },
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/ai/agent_cards/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let!(:agent_card) { create(:ai_agent_card, account: account) }

    it 'deletes the agent card' do
      expect {
        delete "/api/v1/ai/agent_cards/#{agent_card.id}", headers: headers, as: :json
      }.to change { Ai::AgentCard.count }.by(-1)

      expect_success_response
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        delete "/api/v1/ai/agent_cards/#{agent_card.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/agent_cards/:id/publish' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:agent_card) { create(:ai_agent_card, status: 'inactive', account: account) }

    it 'publishes the agent card' do
      post "/api/v1/ai/agent_cards/#{agent_card.id}/publish", headers: headers, as: :json

      expect_success_response
      expect(agent_card.reload.status).to eq('active')
    end
  end

  describe 'POST /api/v1/ai/agent_cards/:id/deprecate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:agent_card) { create(:ai_agent_card, :published, account: account) }

    it 'deprecates the agent card' do
      post "/api/v1/ai/agent_cards/#{agent_card.id}/deprecate",
           headers: headers,
           params: { reason: 'Replaced by newer version' },
           as: :json

      expect_success_response
      expect(agent_card.reload.status).to eq('deprecated')
    end
  end

  describe 'GET /api/v1/ai/agent_cards/discover' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_agent_card, 3, :published, account: account)
    end

    it 'returns discoverable agents' do
      get '/api/v1/ai/agent_cards/discover', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/ai/agent_cards/find_for_task' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create(:ai_agent_card, :published, account: account, capabilities: {
        'skills' => [ { 'id' => 'summarize', 'name' => 'Summarize', 'description' => 'Summarize documents' } ]
      })
    end

    it 'finds agents for task description' do
      post '/api/v1/ai/agent_cards/find_for_task',
           headers: headers,
           params: { description: 'summarize this document' },
           as: :json

      expect_success_response
    end
  end
end
