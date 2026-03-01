# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AgentContainersController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:execute_user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.execute']) }
  let(:delete_user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.delete']) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:container_instance) do
    create(:devops_container_instance, :running, account: account, input_parameters: {
      'agent_id' => agent.id,
      'agent_name' => agent.name,
      'conversation_id' => SecureRandom.uuid,
      'cluster_name' => 'default',
      'template_name' => 'ai-agent',
      'chat_enabled' => true
    })
  end

  let(:deployment_service) { instance_double(Ai::ContainerAgentDeploymentService) }
  let(:bridge_service) { instance_double(Ai::ContainerChatBridgeService) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    allow(Ai::ContainerAgentDeploymentService).to receive(:new).and_return(deployment_service)
    allow(Ai::ContainerChatBridgeService).to receive(:new).and_return(bridge_service)
  end

  # ===========================================================================
  # AUTHENTICATION
  # ===========================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      get :show, params: { id: SecureRandom.uuid }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # GET #show
  # ===========================================================================

  describe 'GET #show' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns container details' do
        get :show, params: { id: container_instance.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['container']['id']).to eq(container_instance.id)
        expect(json_response['data']['container']['status']).to eq('running')
      end

      it 'returns not found for missing container' do
        get :show, params: { id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :show, params: { id: container_instance.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # GET #status
  # ===========================================================================

  describe 'GET #status' do
    context 'with ai.agents.read permission' do
      before { sign_in read_user }

      it 'returns container status' do
        allow(deployment_service).to receive(:get_session_status).and_return({
          running: true, health: 'healthy', uptime_seconds: 300
        })

        get :status, params: { id: container_instance.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['status']).to be_a(Hash)
      end

      it 'returns not found for missing container' do
        get :status, params: { id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :status, params: { id: container_instance.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #launch
  # ===========================================================================

  describe 'POST #launch' do
    context 'with ai.agents.execute permission' do
      before { sign_in execute_user }

      it 'returns conflict when container is already running' do
        post :launch, params: { id: container_instance.id }

        expect(response).to have_http_status(:conflict)
      end

      it 'launches a stopped container' do
        stopped_container = create(:devops_container_instance, :completed, account: account,
          input_parameters: {
            'agent_id' => agent.id,
            'agent_name' => agent.name,
            'conversation_id' => SecureRandom.uuid
          })

        new_instance = create(:devops_container_instance, :running, account: account)
        allow(deployment_service).to receive(:deploy_agent_session).and_return(new_instance)

        post :launch, params: { id: stopped_container.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['message']).to eq('Container deployment initiated')
        expect(json_response['data']['container']).to be_present
      end

      it 'returns not found for missing container' do
        post :launch, params: { id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :launch, params: { id: container_instance.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # DELETE #destroy
  # ===========================================================================

  describe 'DELETE #destroy' do
    context 'with ai.agents.delete permission' do
      before { sign_in delete_user }

      it 'terminates a running container' do
        allow(deployment_service).to receive(:terminate_agent_session).and_return(true)

        delete :destroy, params: { id: container_instance.id, reason: 'Testing' }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['message']).to eq('Container terminated successfully')
        expect(json_response['data']['container']).to be_present
      end

      it 'returns error when termination fails' do
        allow(deployment_service).to receive(:terminate_agent_session).and_return(false)

        delete :destroy, params: { id: container_instance.id }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns not found for missing container' do
        delete :destroy, params: { id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        delete :destroy, params: { id: container_instance.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ===========================================================================
  # POST #callback
  # ===========================================================================

  describe 'POST #callback' do
    context 'with ai.agents.execute permission' do
      before { sign_in execute_user }

      it 'processes callback on success' do
        allow(bridge_service).to receive(:handle_container_response).and_return({
          success: true,
          message_id: 'msg-123'
        })

        post :callback, params: {
          conversation_id: SecureRandom.uuid,
          content: 'Agent response text',
          message_type: 'text'
        }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['message']).to eq('received')
        expect(json_response['data']['message_id']).to eq('msg-123')
      end

      it 'returns error on failure' do
        allow(bridge_service).to receive(:handle_container_response).and_return({
          success: false,
          error: 'Invalid conversation'
        })

        post :callback, params: {
          conversation_id: SecureRandom.uuid,
          content: 'test'
        }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :callback, params: { conversation_id: SecureRandom.uuid, content: 'test' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
