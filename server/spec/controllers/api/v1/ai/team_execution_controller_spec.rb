# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::TeamExecutionController", type: :request do
  let(:account) { create(:account) }
  let(:auth_user) { user_with_permissions('ai.teams.manage', 'ai.teams.execute', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data - use the new teams scope routes: /api/v1/ai/teams/...
  let!(:team) { create(:ai_agent_team, account: account) }
  let!(:execution) { create(:ai_team_execution, account: account, agent_team: team, status: 'running') }

  # Service mocks - these services are instantiated in before_action
  let(:mock_crud_service) { instance_double(::Ai::Teams::CrudService) }
  let(:mock_execution_service) { instance_double(::Ai::Teams::ExecutionService) }
  let(:mock_analytics_service) { instance_double(::Ai::Teams::AnalyticsService) }

  before do
    allow(::Ai::Teams::CrudService).to receive(:new).and_return(mock_crud_service)
    allow(::Ai::Teams::ExecutionService).to receive(:new).and_return(mock_execution_service)
    allow(::Ai::Teams::AnalyticsService).to receive(:new).and_return(mock_analytics_service)
  end

  # =========================================================================
  # SHOW EXECUTION
  # =========================================================================
  describe "GET /api/v1/ai/teams/executions/:id" do
    let(:path) { "/api/v1/ai/teams/executions/#{execution.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_execution_service).to receive(:get_execution).with(execution.id.to_s).and_return(execution)

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # PAUSE EXECUTION
  # =========================================================================
  describe "POST /api/v1/ai/teams/executions/:id/pause" do
    let(:path) { "/api/v1/ai/teams/executions/#{execution.id}/pause" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      paused_execution = execution.dup
      paused_execution.status = 'paused'
      allow(mock_execution_service).to receive(:get_execution).with(execution.id.to_s).and_return(execution)
      allow(mock_execution_service).to receive(:pause_execution).with(execution.id).and_return(paused_execution)

      post path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # RESUME EXECUTION
  # =========================================================================
  describe "POST /api/v1/ai/teams/executions/:id/resume" do
    let(:path) { "/api/v1/ai/teams/executions/#{execution.id}/resume" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      resumed_execution = execution.dup
      resumed_execution.status = 'running'
      allow(mock_execution_service).to receive(:get_execution).with(execution.id.to_s).and_return(execution)
      allow(mock_execution_service).to receive(:resume_execution).with(execution.id).and_return(resumed_execution)

      post path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CANCEL EXECUTION
  # =========================================================================
  describe "POST /api/v1/ai/teams/executions/:id/cancel" do
    let(:path) { "/api/v1/ai/teams/executions/#{execution.id}/cancel" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      cancelled_execution = execution.dup
      cancelled_execution.status = 'cancelled'
      allow(mock_execution_service).to receive(:get_execution).with(execution.id.to_s).and_return(execution)
      allow(mock_execution_service).to receive(:cancel_execution).with(execution.id, reason: nil).and_return(cancelled_execution)

      post path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # COMPLETE EXECUTION
  # =========================================================================
  describe "POST /api/v1/ai/teams/executions/:id/complete" do
    let(:path) { "/api/v1/ai/teams/executions/#{execution.id}/complete" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      completed_execution = execution.dup
      completed_execution.status = 'completed'
      allow(mock_execution_service).to receive(:get_execution).with(execution.id.to_s).and_return(execution)
      allow(mock_execution_service).to receive(:complete_execution).with(execution.id, {}).and_return(completed_execution)

      post path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # EXECUTION DETAILS
  # =========================================================================
  describe "GET /api/v1/ai/teams/executions/:id/details" do
    let(:path) { "/api/v1/ai/teams/executions/#{execution.id}/details" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_execution_service).to receive(:get_execution).with(execution.id.to_s).and_return(execution)
      allow(mock_analytics_service).to receive(:get_execution_details).with(execution.id).and_return({
        execution_id: execution.id, status: 'running', tasks: [], messages: []
      })

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # LIST MESSAGES
  # =========================================================================
  describe "GET /api/v1/ai/teams/executions/:execution_id/messages" do
    let(:path) { "/api/v1/ai/teams/executions/#{execution.id}/messages" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_execution_service).to receive(:get_execution).with(execution.id.to_s).and_return(execution)
      allow(mock_execution_service).to receive(:get_messages).and_return([])

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end
end
