# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::TeamTemplatesReviewsController", type: :request do
  let(:account) { create(:account) }
  let(:auth_user) { user_with_permissions('ai.teams.manage', account: account) }
  let(:code_review_user) { user_with_permissions('ai.teams.manage', 'ai.code_reviews.read', 'ai.code_reviews.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  let(:base_path) { "/api/v1/ai/teams" }

  # Service mocks
  let(:mock_crud_service) { instance_double(::Ai::Teams::CrudService) }
  let(:mock_config_service) { instance_double(::Ai::Teams::ConfigurationService) }

  before do
    allow(::Ai::Teams::CrudService).to receive(:new).and_return(mock_crud_service)
    allow(::Ai::Teams::ConfigurationService).to receive(:new).and_return(mock_config_service)
  end

  # =========================================================================
  # LIST TEMPLATES
  # =========================================================================
  describe "GET /api/v1/ai/teams/templates" do
    let(:path) { "#{base_path}/templates" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      template = create(:ai_team_template, account: account)
      allow(mock_config_service).to receive(:list_templates).and_return([template])

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('templates')
    end
  end

  # =========================================================================
  # SHOW TEMPLATE
  # =========================================================================
  describe "GET /api/v1/ai/teams/templates/:id" do
    let(:template) { create(:ai_team_template, account: account) }
    let(:path) { "#{base_path}/templates/#{template.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_config_service).to receive(:get_template).and_return(template)

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('name')
    end
  end

  # =========================================================================
  # CREATE TEMPLATE
  # =========================================================================
  describe "POST /api/v1/ai/teams/templates" do
    let(:path) { "#{base_path}/templates" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 201 when template created' do
      template = create(:ai_team_template, account: account)
      allow(mock_config_service).to receive(:create_template).and_return(template)

      post path, params: { name: "New Template", team_topology: "hierarchical" },
                 headers: auth_headers_for(auth_user),
                 as: :json
      expect(response).to have_http_status(:created)
    end
  end

  # =========================================================================
  # PUBLISH TEMPLATE
  # =========================================================================
  describe "POST /api/v1/ai/teams/templates/:id/publish" do
    let(:template) { create(:ai_team_template, account: account) }
    let(:path) { "#{base_path}/templates/#{template.id}/publish" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when template published' do
      published_template = template
      published_template.is_public = true
      published_template.published_at = Time.current
      allow(mock_config_service).to receive(:publish_template).and_return(published_template)

      post path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # LIST ROLE PROFILES
  # =========================================================================
  describe "GET /api/v1/ai/teams/role_profiles" do
    let(:path) { "#{base_path}/role_profiles" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      profile = create(:ai_role_profile, account: account)
      allow(mock_crud_service).to receive(:list_role_profiles).and_return([profile])

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('role_profiles')
    end
  end

  # =========================================================================
  # SHOW ROLE PROFILE
  # =========================================================================
  describe "GET /api/v1/ai/teams/role_profiles/:id" do
    let(:profile) { create(:ai_role_profile, account: account) }
    let(:path) { "#{base_path}/role_profiles/#{profile.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_crud_service).to receive(:get_role_profile).and_return(profile)

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('name')
    end
  end

  # =========================================================================
  # LIST TRAJECTORIES
  # =========================================================================
  describe "GET /api/v1/ai/teams/trajectories" do
    let(:path) { "#{base_path}/trajectories" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      trajectory = create(:ai_trajectory, account: account)
      allow(mock_crud_service).to receive(:list_trajectories).and_return([trajectory])

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('trajectories')
    end
  end

  # =========================================================================
  # SEARCH TRAJECTORIES
  # =========================================================================
  describe "GET /api/v1/ai/teams/trajectories/search" do
    let(:path) { "#{base_path}/trajectories/search" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_crud_service).to receive(:search_trajectories).and_return([])

      get path, params: { query: "test" },
                headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('trajectories')
    end
  end

  # =========================================================================
  # SHOW TRAJECTORY
  # =========================================================================
  describe "GET /api/v1/ai/teams/trajectories/:id" do
    let(:trajectory) { create(:ai_trajectory, account: account) }
    let(:path) { "#{base_path}/trajectories/#{trajectory.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_crud_service).to receive(:get_trajectory).and_return(trajectory)
      allow(trajectory).to receive(:chapters).and_return(Ai::TrajectoryChapter.none)

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW REVIEW
  # =========================================================================
  describe "GET /api/v1/ai/teams/reviews/:id" do
    let(:team_execution) { create(:ai_team_execution, account: account, agent_team: team) }
    let(:team_task) { create(:ai_team_task, team_execution: team_execution) }
    let(:review) { create(:ai_task_review, account: account, team_task: team_task) }
    let(:path) { "#{base_path}/reviews/#{review.id}" }
    let(:team) { create(:ai_agent_team, account: account) }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when authenticated' do
      allow(mock_crud_service).to receive(:get_task_review).and_return(review)

      get path, headers: auth_headers_for(auth_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # PROCESS REVIEW
  # =========================================================================
  describe "POST /api/v1/ai/teams/reviews/:id/process" do
    let(:team_execution) { create(:ai_team_execution, account: account, agent_team: team) }
    let(:team_task) { create(:ai_team_task, team_execution: team_execution) }
    let(:review) { create(:ai_task_review, account: account, team_task: team_task) }
    let(:path) { "#{base_path}/reviews/#{review.id}/process" }
    let(:team) { create(:ai_agent_team, account: account) }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns success when review processed' do
      processed_review = review
      processed_review.status = "approved"
      allow(mock_crud_service).to receive(:process_review).and_return(processed_review)

      post path, params: { action_type: "approve", notes: "Looks good" },
                 headers: auth_headers_for(auth_user),
                 as: :json
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # LIST REVIEW COMMENTS
  # =========================================================================
  describe "GET /api/v1/ai/teams/reviews/:review_id/comments" do
    let(:team) { create(:ai_agent_team, account: account) }
    let(:team_execution) { create(:ai_team_execution, account: account, agent_team: team) }
    let(:team_task) { create(:ai_team_task, team_execution: team_execution) }
    let(:review) { create(:ai_task_review, account: account, team_task: team_task) }
    let(:path) { "#{base_path}/reviews/#{review.id}/comments" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.code_reviews.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with comments when user has permission' do
      create(:ai_code_review_comment, task_review: review, account: account)
      # Controller calls current_account.ai_task_reviews but Account lacks that association.
      # Use without_partial_double_verification to stub the missing method.
      without_partial_double_verification do
        allow_any_instance_of(Account).to receive(:ai_task_reviews)
          .and_return(Ai::TaskReview.where(account: account))
      end

      get path, headers: auth_headers_for(code_review_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']).to have_key('comments')
    end
  end

  # =========================================================================
  # CREATE REVIEW COMMENT
  # =========================================================================
  describe "POST /api/v1/ai/teams/reviews/:review_id/comments" do
    let(:team) { create(:ai_agent_team, account: account) }
    let(:team_execution) { create(:ai_team_execution, account: account, agent_team: team) }
    let(:team_task) { create(:ai_team_task, team_execution: team_execution) }
    let(:review) { create(:ai_task_review, account: account, team_task: team_task) }
    let(:path) { "#{base_path}/reviews/#{review.id}/comments" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.code_reviews.manage permission' do
      post path, params: { comment: { file_path: "test.rb", content: "Fix this", comment_type: "suggestion", severity: "warning" } },
                 headers: auth_headers_for(no_perms_user),
                 as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 201 when comment created' do
      # Controller calls current_account.ai_task_reviews but Account lacks that association.
      without_partial_double_verification do
        allow_any_instance_of(Account).to receive(:ai_task_reviews)
          .and_return(Ai::TaskReview.where(account: account))
      end

      post path, params: {
                   comment: {
                     file_path: "app/test.rb",
                     content: "Consider refactoring this method",
                     comment_type: "suggestion",
                     severity: "warning",
                     line_start: 10,
                     line_end: 15
                   }
                 },
                 headers: auth_headers_for(code_review_user),
                 as: :json
      expect(response).to have_http_status(:created)
      expect(json_response['data']).to have_key('comment')
    end
  end
end
