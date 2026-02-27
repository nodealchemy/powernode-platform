# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AgentTeamExecutionsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:auth_user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.execute']) }
  let(:team) { create(:ai_agent_team, account: account) }

  let!(:execution) do
    create(:ai_team_execution, :running, account: account, agent_team: team, triggered_by: auth_user)
  end

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    # The controller calls audit_log which is not defined in the AuditLogging concern
    # (it defines log_audit_event instead). Define it as a no-op to prevent NoMethodError.
    unless Api::V1::Ai::AgentTeamExecutionsController.method_defined?(:audit_log)
      Api::V1::Ai::AgentTeamExecutionsController.define_method(:audit_log) { |*_args, **_kwargs| nil }
    end
  end

  # ===========================================================================
  # AUTHENTICATION
  # ===========================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      get :index, params: { agent_team_id: team.id }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # GET #index
  # ===========================================================================

  describe 'GET #index' do
    context 'when authenticated' do
      before { sign_in auth_user }

      it 'returns executions list' do
        get :index, params: { agent_team_id: team.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']).to be_an(Array)
        expect(json_response['data'].length).to eq(1)
        expect(json_response['data'].first['execution_id']).to eq(execution.execution_id)
      end

      it 'filters by status' do
        create(:ai_team_execution, :completed, account: account, agent_team: team)

        get :index, params: { agent_team_id: team.id, status: 'completed' }

        expect(response).to have_http_status(:success)
        json_response['data'].each do |exec|
          expect(exec['status']).to eq('completed')
        end
      end

      it 'paginates results' do
        get :index, params: { agent_team_id: team.id, page: 1, per_page: 1 }

        expect(response).to have_http_status(:success)
        expect(json_response['meta']['per_page']).to eq(1)
      end

      it 'returns not found for missing team' do
        get :index, params: { agent_team_id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ===========================================================================
  # GET #show
  # ===========================================================================

  describe 'GET #show' do
    context 'when authenticated' do
      before { sign_in auth_user }

      it 'returns execution details' do
        get :show, params: { agent_team_id: team.id, id: execution.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['execution_id']).to eq(execution.execution_id)
        expect(json_response['data']).to include('input_context', 'output_result', 'tasks', 'messages')
      end

      it 'returns not found for missing execution' do
        get :show, params: { agent_team_id: team.id, id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ===========================================================================
  # POST #cancel
  # ===========================================================================

  describe 'POST #cancel' do
    context 'when authenticated' do
      before { sign_in auth_user }

      it 'cancels an active execution' do
        post :cancel, params: { agent_team_id: team.id, id: execution.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['status']).to eq('cancel_requested')
        expect(execution.reload.control_signal).to eq('cancel')
      end

      it 'returns error for non-active execution' do
        completed_exec = create(:ai_team_execution, :completed, account: account, agent_team: team)

        post :cancel, params: { agent_team_id: team.id, id: completed_exec.id }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns not found for missing execution' do
        post :cancel, params: { agent_team_id: team.id, id: SecureRandom.uuid }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ===========================================================================
  # POST #pause
  # ===========================================================================

  describe 'POST #pause' do
    context 'when authenticated' do
      before { sign_in auth_user }

      it 'pauses a running execution' do
        post :pause, params: { agent_team_id: team.id, id: execution.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['status']).to eq('pause_requested')
        expect(execution.reload.control_signal).to eq('pause')
      end

      it 'returns error for non-running execution' do
        pending_exec = create(:ai_team_execution, account: account, agent_team: team, status: 'pending')

        post :pause, params: { agent_team_id: team.id, id: pending_exec.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # ===========================================================================
  # POST #resume
  # ===========================================================================

  describe 'POST #resume' do
    context 'when authenticated' do
      before { sign_in auth_user }

      it 'resumes a paused execution' do
        execution.update!(control_signal: 'pause')

        post :resume, params: { agent_team_id: team.id, id: execution.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['status']).to eq('resume_requested')
        expect(execution.reload.control_signal).to be_nil
      end

      it 'returns error when not paused' do
        post :resume, params: { agent_team_id: team.id, id: execution.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # ===========================================================================
  # POST #retry_execution
  # ===========================================================================

  describe 'POST #retry_execution' do
    context 'when authenticated' do
      before { sign_in auth_user }

      it 'retries a finished execution' do
        failed_exec = create(:ai_team_execution, :failed, account: account, agent_team: team)

        allow(WorkerJobService).to receive(:enqueue_ai_team_execution)

        post :retry_execution, params: { agent_team_id: team.id, id: failed_exec.id }

        expect(response).to have_http_status(:success)
        expect(json_response['success']).to be true
        expect(json_response['data']['status']).to eq('retry_queued')
      end

      it 'returns error for non-finished execution' do
        post :retry_execution, params: { agent_team_id: team.id, id: execution.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
