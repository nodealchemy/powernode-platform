# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Conversations', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['ai.conversations.read']) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: ['ai.conversations.read', 'ai.conversations.create']) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: ['ai.conversations.read', 'ai.conversations.update']) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: ['ai.conversations.read', 'ai.conversations.delete']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/ai/conversations' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_conversation, 3, account: account, user: user_with_read_permission)
    end

    context 'with ai.conversations.read permission' do
      it 'returns list of conversations' do
        get '/api/v1/ai/conversations', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['conversations']).to be_an(Array)
        expect(data['conversations'].length).to eq(3)
      end

      it 'includes conversation details' do
        get '/api/v1/ai/conversations', headers: headers, as: :json

        data = json_response_data
        first_conversation = data['conversations'].first

        expect(first_conversation).to include('id', 'title', 'status', 'message_count')
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/conversations', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        create(:ai_conversation, :archived, account: account, user: user_with_read_permission)

        get '/api/v1/ai/conversations?status=archived', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        statuses = data['conversations'].map { |c| c['status'] }
        expect(statuses.uniq).to eq(['archived'])
      end

      it 'filters by agent_id' do
        agent = create(:ai_agent, account: account)
        create(:ai_conversation, account: account, user: user_with_read_permission, agent: agent)

        get "/api/v1/ai/conversations?agent_id=#{agent.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        # The response includes ai_agent object, not agent_id directly
        agent_ids = data['conversations'].map { |c| c['ai_agent']&.[]('id') }.compact
        expect(agent_ids.uniq).to eq([agent.id])
      end

      it 'searches by title' do
        create(:ai_conversation, title: 'Unique Search Conversation', account: account, user: user_with_read_permission)

        get '/api/v1/ai/conversations?search=Unique+Search', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['conversations'].length).to eq(1)
        expect(data['conversations'].first['title']).to include('Unique Search')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/conversations', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/conversations', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/conversations/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:conversation) { create(:ai_conversation, account: account, user: user_with_read_permission) }

    context 'with ai.conversations.read permission' do
      it 'returns conversation details' do
        get "/api/v1/ai/conversations/#{conversation.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['conversation']).to include(
          'id' => conversation.id,
          'title' => conversation.title,
          'status' => conversation.status
        )
      end

      it 'includes agent information' do
        get "/api/v1/ai/conversations/#{conversation.id}", headers: headers, as: :json

        data = json_response_data
        expect(data['conversation']).to have_key('ai_agent')
      end

      it 'includes token and cost metrics' do
        get "/api/v1/ai/conversations/#{conversation.id}", headers: headers, as: :json

        data = json_response_data
        expect(data['conversation']).to include('total_tokens', 'total_cost')
      end
    end

    context 'when conversation does not exist' do
      it 'returns not found error' do
        get '/api/v1/ai/conversations/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when accessing other account conversation' do
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account) }
      let(:other_conversation) { create(:ai_conversation, account: other_account, user: other_user) }

      it 'returns not found error' do
        get "/api/v1/ai/conversations/#{other_conversation.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/agents/:agent_id/conversations' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:agent) { create(:ai_agent, account: account) }

    before do
      # Stub provider availability check for conversation creation tests
      allow(ProviderAvailabilityService).to receive(:validate_agent_provider!).and_return(true)
    end

    context 'with ai.conversations.create permission' do
      let(:valid_params) do
        {
          conversation: {
            title: 'New Test Conversation'
          }
        }
      end

      it 'creates a new conversation' do
        expect {
          post "/api/v1/ai/agents/#{agent.id}/conversations", params: valid_params, headers: headers, as: :json
        }.to change(Ai::Conversation, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['conversation']['title']).to eq('New Test Conversation')
      end

      it 'sets current user as owner' do
        post "/api/v1/ai/agents/#{agent.id}/conversations", params: valid_params, headers: headers, as: :json

        data = json_response_data
        expect(data['conversation']['user']['id']).to eq(user_with_create_permission.id)
      end

      it 'sets initial status as active' do
        post "/api/v1/ai/agents/#{agent.id}/conversations", params: valid_params, headers: headers, as: :json

        data = json_response_data
        expect(data['conversation']['status']).to eq('active')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post "/api/v1/ai/agents/#{agent.id}/conversations",
             params: { conversation: { title: 'Test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/ai/conversations/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:conversation) { create(:ai_conversation, account: account, user: user_with_update_permission) }

    context 'with ai.conversations.update permission' do
      it 'updates conversation successfully' do
        put "/api/v1/ai/conversations/#{conversation.id}",
            params: { conversation: { title: 'Updated Title' } },
            headers: headers,
            as: :json

        expect_success_response

        conversation.reload
        expect(conversation.title).to eq('Updated Title')
      end
    end
  end

  describe 'DELETE /api/v1/ai/conversations/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:conversation) { create(:ai_conversation, account: account, user: user_with_delete_permission) }

    context 'with ai.conversations.delete permission' do
      it 'deletes conversation successfully' do
        conversation_id = conversation.id

        delete "/api/v1/ai/conversations/#{conversation_id}", headers: headers, as: :json

        expect_success_response
        expect(Ai::Conversation.find_by(id: conversation_id)).to be_nil
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        delete "/api/v1/ai/conversations/#{conversation.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/conversations/:id/archive' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:conversation) { create(:ai_conversation, account: account, user: user_with_update_permission, status: 'active') }

    context 'with ai.conversations.update permission' do
      it 'archives the conversation' do
        post "/api/v1/ai/conversations/#{conversation.id}/archive", headers: headers, as: :json

        expect_success_response

        conversation.reload
        expect(conversation.status).to eq('archived')
      end
    end
  end

  describe 'POST /api/v1/ai/conversations/:id/unarchive' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:conversation) { create(:ai_conversation, :archived, account: account, user: user_with_update_permission) }

    context 'with ai.conversations.update permission' do
      it 'unarchives the conversation' do
        post "/api/v1/ai/conversations/#{conversation.id}/unarchive", headers: headers, as: :json

        expect_success_response

        conversation.reload
        # Controller sets status to 'completed' when unarchiving
        expect(conversation.status).to eq('completed')
      end
    end
  end

  describe 'POST /api/v1/ai/conversations/:id/duplicate' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:conversation) { create(:ai_conversation, account: account, user: user_with_create_permission, title: 'Original Conversation') }

    context 'with ai.conversations.create permission' do
      it 'creates a duplicate of the conversation' do
        post "/api/v1/ai/conversations/#{conversation.id}/duplicate", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['conversation']['title']).to include('Original Conversation')
      end
    end
  end

  describe 'GET /api/v1/ai/conversations/:id/stats' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:conversation) { create(:ai_conversation, :with_messages, account: account, user: user_with_read_permission) }

    context 'with ai.conversations.read permission' do
      it 'returns conversation statistics' do
        get "/api/v1/ai/conversations/#{conversation.id}/stats", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['stats']).to have_key('message_count')
        expect(data['stats']).to have_key('token_usage')
      end
    end
  end
end
