# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::TeamsController", type: :request do
  let(:account) { create(:account) }
  let(:auth_user) { user_with_permissions('ai.teams.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  let!(:team) { create(:ai_agent_team, account: account) }

  # Service mocks
  let(:mock_crud_service) { instance_double(::Ai::Teams::CrudService) }
  let(:mock_analytics_service) { instance_double(::Ai::Teams::AnalyticsService) }

  before do
    allow(::Ai::Teams::CrudService).to receive(:new).and_return(mock_crud_service)
    allow(::Ai::Teams::AnalyticsService).to receive(:new).and_return(mock_analytics_service)
  end

  # =========================================================================
  # INDEX
  # =========================================================================
  describe "GET /api/v1/ai/teams" do
    let(:path) { "/api/v1/ai/teams" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      teams = [team]
      allow(teams).to receive(:respond_to?).and_call_original
      allow(teams).to receive(:respond_to?).with(:total_count).and_return(false)
      allow(mock_crud_service).to receive(:list_teams).and_return(teams)

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('teams')
    end
  end

  # =========================================================================
  # SHOW
  # =========================================================================
  describe "GET /api/v1/ai/teams/:id" do
    let(:path) { "/api/v1/ai/teams/#{team.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_crud_service).to receive(:get_team).and_return(team)

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('name')
    end
  end

  # =========================================================================
  # CREATE
  # =========================================================================
  describe "POST /api/v1/ai/teams" do
    let(:path) { "/api/v1/ai/teams" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 201 when team created' do
      new_team = create(:ai_agent_team, account: account)
      allow(mock_crud_service).to receive(:create_team).and_return(new_team)

      post path, params: { name: "New Team", description: "A test team" },
                 headers: auth_headers_for(auth_user),
                 as: :json
      expect(response).to have_http_status(:created)
    end

    it 'returns 201 when creating from template' do
      template = create(:ai_team_template, account: account)
      new_team = create(:ai_agent_team, account: account)
      allow(mock_crud_service).to receive(:create_team_from_template).and_return(new_team)

      post path, params: { template_id: template.id, name: "From Template" },
                 headers: auth_headers_for(auth_user),
                 as: :json
      expect(response).to have_http_status(:created)
    end
  end

  # =========================================================================
  # UPDATE
  # =========================================================================
  describe "PATCH /api/v1/ai/teams/:id" do
    let(:path) { "/api/v1/ai/teams/#{team.id}" }

    it 'returns 401 when unauthenticated' do
      patch path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when team updated' do
      allow(mock_crud_service).to receive(:get_team).and_return(team)
      allow(mock_crud_service).to receive(:update_team).and_return(team)

      patch path, params: { name: "Updated Team" },
                  headers: auth_headers_for(auth_user),
                  as: :json
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # DESTROY
  # =========================================================================
  describe "DELETE /api/v1/ai/teams/:id" do
    let(:path) { "/api/v1/ai/teams/#{team.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when team deleted' do
      allow(mock_crud_service).to receive(:get_team).and_return(team)
      allow(mock_crud_service).to receive(:delete_team).and_return(true)

      delete path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # ANALYTICS
  # =========================================================================
  describe "GET /api/v1/ai/teams/:team_id/analytics" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/analytics" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success with analytics data' do
      allow(mock_crud_service).to receive(:get_team).and_return(team)
      allow(mock_analytics_service).to receive(:get_team_analytics).and_return({
        total_executions: 10, success_rate: 0.85
      })

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # COMPOSITION HEALTH
  # =========================================================================
  describe "GET /api/v1/ai/teams/:team_id/composition_health" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/composition_health" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success with health data' do
      allow(mock_crud_service).to receive(:get_team).and_return(team)
      allow(mock_crud_service).to receive(:composition_health).and_return({
        score: 0.8, recommendations: []
      })

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # UPDATE REVIEW CONFIG
  # =========================================================================
  describe "PUT /api/v1/ai/teams/:team_id/review_config" do
    let(:path) { "/api/v1/ai/teams/#{team.id}/review_config" }

    it 'returns 401 when unauthenticated' do
      put path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when review config updated' do
      allow(mock_crud_service).to receive(:get_team).and_return(team)
      allow(mock_crud_service).to receive(:configure_team_review).and_return(team)

      put path, params: { auto_review_enabled: true, review_mode: "blocking" },
                headers: auth_headers_for(auth_user),
                as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
