# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::AgentContainers', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:user_with_execute) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.execute']) }
  let(:user_with_delete) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.delete']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  let(:template) { create(:devops_container_template, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:container_instance) do
    create(:devops_container_instance, :pending, account: account, template: template,
           input_parameters: { 'agent_id' => agent.id, 'conversation_id' => 'conv-123' })
  end

  let(:deployment_service) { instance_double(Ai::ContainerAgentDeploymentService) }
  let(:bridge_service) { instance_double(Ai::ContainerChatBridgeService) }

  before do
    allow(Ai::ContainerAgentDeploymentService).to receive(:new).and_return(deployment_service)
    allow(Ai::ContainerChatBridgeService).to receive(:new).and_return(bridge_service)
  end

  # =========================================================================
  # GET /api/v1/ai/agent_containers/:id
  # =========================================================================
  describe 'GET /api/v1/ai/agent_containers/:id' do
    context 'with ai.agents.read permission' do
      let(:headers) { auth_headers_for(user_with_read) }

      it 'returns container details' do
        get "/api/v1/ai/agent_containers/#{container_instance.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['container']).to include('id' => container_instance.id, 'status' => 'pending')
      end

      it 'includes serialized fields' do
        get "/api/v1/ai/agent_containers/#{container_instance.id}", headers: headers, as: :json

        data = json_response_data
        container = data['container']
        expect(container).to include('execution_id', 'image', 'agent_id', 'conversation_id', 'created_at')
        expect(container).to have_key('resource_usage')
      end
    end

    context 'when container does not exist' do
      let(:headers) { auth_headers_for(user_with_read) }

      it 'returns not found' do
        get '/api/v1/ai/agent_containers/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when accessing another account container' do
      let(:other_account) { create(:account) }
      let(:other_template) { create(:devops_container_template, account: other_account) }
      let(:other_container) { create(:devops_container_instance, account: other_account, template: other_template) }
      let(:headers) { auth_headers_for(user_with_read) }

      it 'returns not found' do
        get "/api/v1/ai/agent_containers/#{other_container.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden' do
        get "/api/v1/ai/agent_containers/#{container_instance.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get "/api/v1/ai/agent_containers/#{container_instance.id}", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  # =========================================================================
  # GET /api/v1/ai/agent_containers/:id/status
  # =========================================================================
  describe 'GET /api/v1/ai/agent_containers/:id/status' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:status_data) { { state: 'running', uptime: 120, healthy: true } }

    before do
      allow(deployment_service).to receive(:get_session_status).and_return(status_data)
    end

    context 'with ai.agents.read permission' do
      it 'returns status data' do
        get "/api/v1/ai/agent_containers/#{container_instance.id}/status", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['status']).to include('state' => 'running', 'healthy' => true)
      end
    end

    context 'when container does not exist' do
      it 'returns not found' do
        get '/api/v1/ai/agent_containers/nonexistent-id/status', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden' do
        get "/api/v1/ai/agent_containers/#{container_instance.id}/status", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =========================================================================
  # POST /api/v1/ai/agent_containers/:id/launch
  # =========================================================================
  describe 'POST /api/v1/ai/agent_containers/:id/launch' do
    let(:headers) { auth_headers_for(user_with_execute) }

    context 'with ai.agents.execute permission' do
      before do
        allow(deployment_service).to receive(:deploy_agent_session).and_return(container_instance)
      end

      it 'launches the container successfully' do
        post "/api/v1/ai/agent_containers/#{container_instance.id}/launch", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['container']).to include('id' => container_instance.id)
        expect(json_response['message']).to eq('Container deployment initiated')
      end

      it 'calls deploy_agent_session with correct arguments' do
        expect(deployment_service).to receive(:deploy_agent_session).with(
          agent: agent,
          conversation_id: 'conv-123',
          user: user_with_execute
        ).and_return(container_instance)

        post "/api/v1/ai/agent_containers/#{container_instance.id}/launch", headers: headers, as: :json
      end
    end

    context 'when container is already active' do
      let(:active_container) do
        create(:devops_container_instance, :running, account: account, template: template,
               input_parameters: { 'agent_id' => agent.id, 'conversation_id' => 'conv-456' })
      end

      it 'returns conflict error' do
        post "/api/v1/ai/agent_containers/#{active_container.id}/launch", headers: headers, as: :json

        expect(response).to have_http_status(:conflict)
      end
    end

    context 'when agent_id is missing from input_parameters' do
      let(:no_agent_container) do
        create(:devops_container_instance, :pending, account: account, template: template,
               input_parameters: { 'conversation_id' => 'conv-789' })
      end

      it 'returns not found for agent' do
        post "/api/v1/ai/agent_containers/#{no_agent_container.id}/launch", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when agent does not exist' do
      let(:bad_agent_container) do
        create(:devops_container_instance, :pending, account: account, template: template,
               input_parameters: { 'agent_id' => 'nonexistent-agent-id', 'conversation_id' => 'conv-000' })
      end

      it 'returns not found' do
        post "/api/v1/ai/agent_containers/#{bad_agent_container.id}/launch", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when deployment fails' do
      before do
        allow(deployment_service).to receive(:deploy_agent_session)
          .and_raise(Ai::ContainerAgentDeploymentService::DeploymentError, 'Docker daemon unreachable')
      end

      it 'returns unprocessable content with deployment error' do
        post "/api/v1/ai/agent_containers/#{container_instance.id}/launch", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read) }

      it 'returns forbidden' do
        post "/api/v1/ai/agent_containers/#{container_instance.id}/launch", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =========================================================================
  # DELETE /api/v1/ai/agent_containers/:id
  # =========================================================================
  describe 'DELETE /api/v1/ai/agent_containers/:id' do
    let(:headers) { auth_headers_for(user_with_delete) }

    context 'with ai.agents.delete permission' do
      before do
        allow(deployment_service).to receive(:terminate_agent_session).and_return(true)
      end

      it 'terminates the container successfully' do
        delete "/api/v1/ai/agent_containers/#{container_instance.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(json_response['message']).to eq('Container terminated successfully')
        expect(data['container']).to include('id' => container_instance.id)
      end

      it 'passes reason parameter' do
        expect(deployment_service).to receive(:terminate_agent_session).with(
          container_instance: container_instance,
          reason: 'User requested shutdown'
        ).and_return(true)

        delete "/api/v1/ai/agent_containers/#{container_instance.id}",
               params: { reason: 'User requested shutdown' }, headers: headers, as: :json
      end

      it 'uses default reason when none provided' do
        expect(deployment_service).to receive(:terminate_agent_session).with(
          container_instance: container_instance,
          reason: 'Terminated by user'
        ).and_return(true)

        delete "/api/v1/ai/agent_containers/#{container_instance.id}", headers: headers, as: :json
      end
    end

    context 'when termination fails' do
      before do
        allow(deployment_service).to receive(:terminate_agent_session).and_return(false)
      end

      it 'returns unprocessable content' do
        delete "/api/v1/ai/agent_containers/#{container_instance.id}", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when container does not exist' do
      it 'returns not found' do
        delete '/api/v1/ai/agent_containers/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read) }

      it 'returns forbidden' do
        delete "/api/v1/ai/agent_containers/#{container_instance.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =========================================================================
  # POST /api/v1/ai/agent_containers/callback
  # =========================================================================
  describe 'POST /api/v1/ai/agent_containers/callback' do
    let(:headers) { auth_headers_for(user_with_execute) }
    let(:callback_params) do
      {
        conversation_id: 'conv-123',
        content: 'Agent response text',
        message_type: 'text',
        execution_id: 'exec-abc',
        metadata: { tool: 'code_review' }
      }
    end

    context 'with ai.agents.execute permission' do
      before do
        allow(bridge_service).to receive(:handle_container_response)
          .and_return({ success: true, message_id: 'msg-456' })
      end

      it 'processes callback successfully' do
        post '/api/v1/ai/agent_containers/callback', params: callback_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(json_response['message']).to eq('received')
        expect(data['message_id']).to eq('msg-456')
      end

      it 'passes correct params to bridge service' do
        expect(bridge_service).to receive(:handle_container_response).with(
          conversation_id: 'conv-123',
          response: hash_including(content: 'Agent response text', message_type: 'text', execution_id: 'exec-abc')
        ).and_return({ success: true, message_id: 'msg-456' })

        post '/api/v1/ai/agent_containers/callback', params: callback_params, headers: headers, as: :json
      end
    end

    context 'when bridge service returns failure' do
      before do
        allow(bridge_service).to receive(:handle_container_response)
          .and_return({ success: false, error: 'Conversation not found' })
      end

      it 'returns unprocessable content' do
        post '/api/v1/ai/agent_containers/callback', params: callback_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when bridge service raises an exception' do
      before do
        allow(bridge_service).to receive(:handle_container_response)
          .and_raise(StandardError, 'Unexpected error')
      end

      it 'returns internal server error' do
        post '/api/v1/ai/agent_containers/callback', params: callback_params, headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read) }

      it 'returns forbidden' do
        post '/api/v1/ai/agent_containers/callback', params: callback_params, headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
