# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::ContainerSandboxesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:create_user) { create(:user, account: account, permissions: ['ai.agents.create']) }
  let(:delete_user) { create(:user, account: account, permissions: ['ai.agents.delete']) }
  let(:execute_user) { create(:user, account: account, permissions: ['ai.agents.execute']) }
  let(:agent) { create(:ai_agent, account: account) }

  let(:sandbox_instance) do
    create(:devops_container_instance, :running,
      account: account,
      input_parameters: { "sandbox_mode" => "true", "agent_id" => agent.id, "agent_name" => agent.name }
    )
  end

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  describe 'GET #index' do
    before { sandbox_instance }

    context 'with valid permissions' do
      before { sign_in read_user }

      it 'returns sandbox list' do
        get :index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to be_an(Array)
      end

      it 'filters by status' do
        get :index, params: { status: 'running' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :index

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #stats' do
    context 'with valid permissions' do
      before { sign_in read_user }

      it 'returns sandbox statistics' do
        get :stats

        json = JSON.parse(response.body) rescue nil
        expect(response).to have_http_status(:success), "Expected success but got #{response.status}: #{json || response.body}"
        expect(json['success']).to be true
        expect(json['data']).to include('total', 'running', 'paused', 'completed', 'failed')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :stats

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #show' do
    context 'with valid permissions' do
      before { sign_in read_user }

      it 'returns sandbox details' do
        get :show, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['id']).to eq(sandbox_instance.id)
      end

      it 'returns not found for missing sandbox' do
        get :show, params: { id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :show, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #create' do
    context 'with valid permissions' do
      before do
        sign_in create_user
        allow_any_instance_of(Ai::Runtime::SandboxManagerService).to receive(:create_sandbox).and_return(sandbox_instance)
      end

      it 'creates a sandbox' do
        post :create, params: { agent_id: agent.id, image_name: 'test', image_tag: 'latest' }

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'returns not found for invalid agent' do
        post :create, params: { agent_id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :create, params: { agent_id: agent.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'with valid permissions' do
      before do
        sign_in delete_user
        allow_any_instance_of(Ai::Runtime::SandboxManagerService).to receive(:destroy_sandbox).and_return(true)
      end

      it 'destroys the sandbox' do
        delete :destroy, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        delete :destroy, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #pause' do
    context 'with valid permissions' do
      before do
        sign_in execute_user
        allow_any_instance_of(Ai::Runtime::SandboxManagerService).to receive(:pause_sandbox).and_return({ success: true })
      end

      it 'pauses the sandbox' do
        post :pause, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :pause, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #resume' do
    context 'with valid permissions' do
      before do
        sign_in execute_user
        allow_any_instance_of(Ai::Runtime::SandboxManagerService).to receive(:resume_sandbox).and_return({ success: true })
      end

      it 'resumes the sandbox' do
        post :resume, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :resume, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #metrics' do
    context 'with valid permissions' do
      before do
        sign_in read_user
        allow_any_instance_of(Ai::Runtime::SandboxManagerService).to receive(:get_metrics).and_return({
          cpu_usage: 15.2, memory_usage_mb: 256, network_io: { rx: 100, tx: 50 }
        })
      end

      it 'returns sandbox metrics' do
        get :metrics, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :metrics, params: { id: sandbox_instance.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
