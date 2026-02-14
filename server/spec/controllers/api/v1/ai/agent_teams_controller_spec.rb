# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::AgentTeamsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/agent_teams" }

  # Users with specific permissions
  let(:manage_user) { user_with_permissions('ai.teams.manage', account: account) }
  let(:execute_user) { user_with_permissions('ai.teams.manage', 'ai.teams.execute', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:team) { create(:ai_agent_team, account: account) }

  # =========================================================================
  # INDEX (ai.teams.manage)
  # =========================================================================
  describe "GET /api/v1/ai/agent_teams" do
    let(:path) { base_path }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.teams.manage permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.teams.manage permission' do
      get path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
    end
  end

  # =========================================================================
  # SHOW (ai.teams.manage)
  # =========================================================================
  describe "GET /api/v1/ai/agent_teams/:id" do
    let(:path) { "#{base_path}/#{team.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.teams.manage permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.teams.manage permission' do
      get path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE (ai.teams.manage)
  # =========================================================================
  describe "POST /api/v1/ai/agent_teams" do
    let(:path) { base_path }
    let(:valid_params) do
      {
        name: "New Agent Team",
        description: "A test team",
        team_type: "hierarchical",
        coordination_strategy: "manager_led"
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.teams.manage permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a team when user has ai.teams.manage permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UPDATE (ai.teams.manage)
  # =========================================================================
  describe "PATCH /api/v1/ai/agent_teams/:id" do
    let(:path) { "#{base_path}/#{team.id}" }
    let(:update_params) { { name: "Updated Team Name" } }

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.teams.manage permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.teams.manage permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # DESTROY (ai.teams.manage)
  # =========================================================================
  describe "DELETE /api/v1/ai/agent_teams/:id" do
    let(:path) { "#{base_path}/#{team.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.teams.manage permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.teams.manage permission' do
      delete path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # EXECUTE (ai.teams.execute)
  # =========================================================================
  describe "POST /api/v1/ai/agent_teams/:id/execute" do
    let(:path) { "#{base_path}/#{team.id}/execute" }
    let(:execute_params) { { input: { task: "Test task" } } }

    it 'returns 401 when unauthenticated' do
      post path, params: execute_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.teams.execute permission' do
      post path, params: execute_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.teams.execute permission' do
      # Stub the async job to avoid actually enqueuing
      allow(::Ai::AgentTeamExecutionJob).to receive(:perform_async).and_return("fake-job-id")

      post path, params: execute_params.to_json, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # AUTONOMY_CONFIG (ai.teams.manage)
  # =========================================================================
  describe "GET /api/v1/ai/agent_teams/:id/autonomy_config" do
    let(:path) { "#{base_path}/#{team.id}/autonomy_config" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.teams.manage permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.teams.manage permission' do
      get path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
    end
  end
end
