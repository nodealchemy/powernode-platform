# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AgentCardsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.create', 'ai.agents.update', 'ai.agents.delete']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let(:agent) { create(:ai_agent, account: account, creator: user) }
  let!(:agent_card) { create(:ai_agent_card, account: account, agent: agent, visibility: 'private') }
  let!(:public_card) { create(:ai_agent_card, :public, account: account, agent: agent) }

  before do
    sign_in_as_user(user)
  end

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :index
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # AUTHORIZATION
  # ============================================================================

  describe 'authorization' do
    context 'without permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for index' do
        get :index
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for create' do
        post :create, params: { agent_card: { name: 'Test', ai_agent_id: agent.id } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for update' do
        patch :update, params: { id: agent_card.id, agent_card: { name: 'Updated' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for destroy' do
        delete :destroy, params: { id: agent_card.id }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in_as_user(read_only_user) }

      it 'allows index access' do
        get :index
        expect(response).to have_http_status(:ok)
      end

      it 'allows show access' do
        get :show, params: { id: agent_card.id }
        expect(response).to have_http_status(:ok)
      end

      it 'returns 403 for create' do
        post :create, params: { agent_card: { name: 'Test', ai_agent_id: agent.id } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # INDEX
  # ============================================================================

  describe 'GET #index' do
    it 'returns agent cards' do
      get :index
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['items']).to be_an(Array)
    end

    it 'filters by query with ILIKE sanitization' do
      create(:ai_agent_card, account: account, agent: agent, name: 'Searchable Card')

      get :index, params: { query: 'Searchable' }
      expect(response).to have_http_status(:ok)
      names = json_response['data']['items'].map { |c| c['name'] }
      expect(names).to include('Searchable Card')
    end

    it 'safely handles SQL special characters in query' do
      get :index, params: { query: "%_test'--" }
      expect(response).to have_http_status(:ok)
    end

    it 'filters by status' do
      get :index, params: { status: 'active' }
      expect(response).to have_http_status(:ok)
    end

    it 'filters by visibility' do
      get :index, params: { visibility: 'public' }
      expect(response).to have_http_status(:ok)
    end

    it 'does not return cards from other accounts' do
      other_account = create(:account)
      other_agent = create(:ai_agent, account: other_account)
      create(:ai_agent_card, account: other_account, agent: other_agent, visibility: 'private')

      get :index
      card_ids = json_response['data']['items'].map { |c| c['id'] }
      expect(card_ids).to all(satisfy { |id| [agent_card.id, public_card.id].include?(id) || Ai::AgentCard.find(id).account_id == account.id })
    end
  end

  # ============================================================================
  # SHOW
  # ============================================================================

  describe 'GET #show' do
    it 'returns agent card details' do
      get :show, params: { id: agent_card.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['agent_card']).to be_present
    end

    it 'returns 404 for non-existent card' do
      get :show, params: { id: 'nonexistent-id' }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # A2A
  # ============================================================================

  describe 'GET #a2a' do
    it 'returns A2A-compliant JSON' do
      get :a2a, params: { id: agent_card.id }
      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for non-existent card' do
      get :a2a, params: { id: 'nonexistent-id' }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # CREATE
  # ============================================================================

  describe 'POST #create' do
    let(:valid_params) do
      {
        agent_card: {
          ai_agent_id: agent.id,
          name: 'New Agent Card',
          description: 'A test agent card',
          visibility: 'private'
        }
      }
    end

    it 'creates a new agent card' do
      expect {
        post :create, params: valid_params
      }.to change { Ai::AgentCard.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
      expect(json_response['data']['agent_card']).to be_present
    end

    it 'returns validation errors for invalid params' do
      post :create, params: { agent_card: { name: '' } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # UPDATE
  # ============================================================================

  describe 'PATCH #update' do
    it 'updates an agent card' do
      patch :update, params: { id: agent_card.id, agent_card: { name: 'Updated Card' } }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      agent_card.reload
      expect(agent_card.name).to eq('Updated Card')
    end

    it 'returns 404 for non-existent card' do
      patch :update, params: { id: 'nonexistent', agent_card: { name: 'Fail' } }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # DESTROY
  # ============================================================================

  describe 'DELETE #destroy' do
    it 'deletes an agent card' do
      expect {
        delete :destroy, params: { id: agent_card.id }
      }.to change { Ai::AgentCard.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # PUBLISH & DEPRECATE
  # ============================================================================

  describe 'POST #publish' do
    it 'publishes an agent card' do
      allow_any_instance_of(Ai::AgentCard).to receive(:sync_skills_from_agent!).and_return(true)
      allow_any_instance_of(Ai::AgentCard).to receive(:publish!).and_return(true)

      post :publish, params: { id: agent_card.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  describe 'POST #deprecate' do
    it 'deprecates an agent card' do
      allow_any_instance_of(Ai::AgentCard).to receive(:deprecate!).and_return(true)

      post :deprecate, params: { id: agent_card.id, reason: 'No longer maintained' }
      expect(response).to have_http_status(:ok)
    end
  end

  # ============================================================================
  # DISCOVER & FIND FOR TASK
  # ============================================================================

  describe 'GET #discover' do
    let(:a2a_service) { instance_double(Ai::A2a::Service) }

    it 'discovers agents by skill' do
      allow(Ai::A2a::Service).to receive(:new).and_return(a2a_service)
      allow(a2a_service).to receive(:discover_agents).and_return({ agents: [], total: 0 })

      get :discover, params: { skill: 'summarize' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST #find_for_task' do
    let(:a2a_service) { instance_double(Ai::A2a::Service) }

    it 'finds agents for a task description' do
      allow(Ai::A2a::Service).to receive(:new).and_return(a2a_service)
      allow(a2a_service).to receive(:find_agents_for_task).and_return([])

      post :find_for_task, params: { description: 'Summarize this document' }
      expect(response).to have_http_status(:ok)
    end
  end
end
