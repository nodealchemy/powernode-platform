# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::A2aTasksController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.execute']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let(:from_agent) { create(:ai_agent, account: account, creator: user) }
  let(:to_agent) { create(:ai_agent, account: account, creator: user) }
  let!(:task) do
    create(:ai_a2a_task,
           account: account,
           from_agent: from_agent,
           to_agent: to_agent,
           status: 'pending')
  end

  let(:a2a_service) { instance_double(Ai::A2a::Service) }

  before do
    sign_in_as_user(user)
    allow(Ai::A2a::Service).to receive(:new).and_return(a2a_service)
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
    context 'without any permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for index' do
        get :index
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for create' do
        post :create, params: { text: 'Hello' }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in_as_user(read_only_user) }

      it 'allows index access' do
        get :index
        expect(response).to have_http_status(:ok)
      end

      it 'returns 403 for cancel without execute permission' do
        post :cancel, params: { task_id: task.task_id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # INDEX
  # ============================================================================

  describe 'GET #index' do
    it 'returns tasks for current account' do
      get :index
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['items']).to be_an(Array)
    end

    it 'filters by status' do
      create(:ai_a2a_task, :active, account: account, from_agent: from_agent, to_agent: to_agent)

      get :index, params: { status: 'active' }
      expect(response).to have_http_status(:ok)
      statuses = json_response['data']['items'].map { |t| t['status'] }
      expect(statuses).to all(eq('active'))
    end

    it 'does not return tasks from other accounts' do
      other_account = create(:account)
      other_agent = create(:ai_agent, account: other_account)
      create(:ai_a2a_task, account: other_account, from_agent: other_agent, to_agent: other_agent)

      get :index
      task_ids = json_response['data']['items'].map { |t| t['task_id'] || t['id'] }
      expect(task_ids.size).to eq(1)
    end
  end

  # ============================================================================
  # SHOW
  # ============================================================================

  describe 'GET #show' do
    it 'returns task details' do
      get :show, params: { task_id: task.task_id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['task']).to be_present
    end

    it 'returns 404 for non-existent task' do
      get :show, params: { task_id: 'nonexistent-uuid' }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # CREATE
  # ============================================================================

  describe 'POST #create' do
    let(:agent_card) { create(:ai_agent_card, account: account, agent: to_agent) }
    let(:new_task) { create(:ai_a2a_task, account: account, from_agent: from_agent, to_agent: to_agent) }

    it 'creates a new task' do
      allow(a2a_service).to receive(:submit_task).and_return(new_task)

      post :create, params: {
        to_agent_card_id: agent_card.id,
        text: 'Analyze this data',
        from_agent_id: from_agent.id
      }
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end

    it 'returns error on service failure' do
      error = Ai::A2a::Service::A2aError.new('Agent not available')
      allow(error).to receive(:code).and_return('AGENT_UNAVAILABLE')
      allow(a2a_service).to receive(:submit_task).and_raise(error)

      post :create, params: {
        to_agent_card_id: agent_card.id,
        text: 'Test'
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # CANCEL
  # ============================================================================

  describe 'POST #cancel' do
    it 'cancels a task' do
      allow(a2a_service).to receive(:cancel_task).and_return({ status: 'cancelled' })

      post :cancel, params: { task_id: task.task_id, reason: 'No longer needed' }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns error when cancel fails' do
      error = Ai::A2a::Service::A2aError.new('Cannot cancel completed task')
      allow(error).to receive(:code).and_return('INVALID_STATE')
      allow(a2a_service).to receive(:cancel_task).and_raise(error)

      post :cancel, params: { task_id: task.task_id }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # ARTIFACTS
  # ============================================================================

  describe 'GET #artifacts' do
    it 'returns task artifacts' do
      get :artifacts, params: { task_id: task.task_id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to have_key('artifacts')
    end
  end
end
