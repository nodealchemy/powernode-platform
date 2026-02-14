# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::LearningController", type: :request do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.analytics.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.analytics.read', 'ai.analytics.manage', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:recommendation) { create(:ai_improvement_recommendation, account: account) }

  # Stub services to avoid deep dependency issues
  before do
    # Stub CompoundLearningService
    compound_service = instance_double(Ai::Learning::CompoundLearningService)
    allow(Ai::Learning::CompoundLearningService).to receive(:new).and_return(compound_service)
    allow(compound_service).to receive(:compound_metrics).and_return({
      total_learnings: 10,
      active_learnings: 8,
      avg_importance: 0.65
    })
    allow(compound_service).to receive(:list_learnings).and_return([])
    allow(compound_service).to receive(:reinforce_learning).and_return(nil)
    allow(compound_service).to receive(:promote_cross_team).and_return(0)
    allow(compound_service).to receive(:decay_and_consolidate).and_return({ decayed: 0, consolidated: 0 })

    # Stub EvaluationService
    eval_service = instance_double(Ai::Learning::EvaluationService)
    allow(Ai::Learning::EvaluationService).to receive(:new).and_return(eval_service)
    allow(eval_service).to receive(:agent_score_trends).and_return(nil)

    # Stub PromptCacheService
    allow(Ai::Learning::PromptCacheService).to receive(:metrics).and_return({
      hit_rate: 0.75,
      total_hits: 100,
      total_misses: 33
    })

    # Stub ImprovementRecommender
    recommender = instance_double(Ai::Learning::ImprovementRecommender)
    allow(Ai::Learning::ImprovementRecommender).to receive(:new).and_return(recommender)
    allow(recommender).to receive(:apply_recommendation!).and_return(nil)
  end

  # =========================================================================
  # RECOMMENDATIONS (GET /api/v1/ai/learning/recommendations)
  # =========================================================================
  describe "GET /api/v1/ai/learning/recommendations" do
    let(:path) { "/api/v1/ai/learning/recommendations" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.analytics.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['recommendations']).to be_an(Array)
    end
  end

  # =========================================================================
  # APPLY RECOMMENDATION (POST /api/v1/ai/learning/recommendations/:id/apply)
  # =========================================================================
  describe "POST /api/v1/ai/learning/recommendations/:id/apply" do
    let(:path) { "/api/v1/ai/learning/recommendations/#{recommendation.id}/apply" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.analytics.manage permission' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # DISMISS RECOMMENDATION (POST /api/v1/ai/learning/recommendations/:id/dismiss)
  # =========================================================================
  describe "POST /api/v1/ai/learning/recommendations/:id/dismiss" do
    let(:path) { "/api/v1/ai/learning/recommendations/#{recommendation.id}/dismiss" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.analytics.manage permission' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # AGENT TRENDS (GET /api/v1/ai/learning/agent_trends)
  # =========================================================================
  describe "GET /api/v1/ai/learning/agent_trends" do
    let(:path) { "/api/v1/ai/learning/agent_trends" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.analytics.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['trends']).to be_an(Array)
    end
  end

  # =========================================================================
  # CACHE METRICS (GET /api/v1/ai/learning/cache_metrics)
  # =========================================================================
  describe "GET /api/v1/ai/learning/cache_metrics" do
    let(:path) { "/api/v1/ai/learning/cache_metrics" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.analytics.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['metrics']).to be_a(Hash)
    end
  end

  # =========================================================================
  # COMPOUND METRICS (GET /api/v1/ai/learning/compound_metrics)
  # =========================================================================
  describe "GET /api/v1/ai/learning/compound_metrics" do
    let(:path) { "/api/v1/ai/learning/compound_metrics" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.analytics.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['metrics']).to be_a(Hash)
    end
  end

  # =========================================================================
  # LEARNINGS (GET /api/v1/ai/learning/learnings)
  # =========================================================================
  describe "GET /api/v1/ai/learning/learnings" do
    let(:path) { "/api/v1/ai/learning/learnings" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.analytics.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['learnings']).to be_an(Array)
    end
  end

  # =========================================================================
  # REINFORCE (POST /api/v1/ai/learning/reinforce/:id)
  # =========================================================================
  describe "POST /api/v1/ai/learning/reinforce/:id" do
    let(:path) { "/api/v1/ai/learning/reinforce/#{SecureRandom.uuid}" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.analytics.manage permission' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # PROMOTE (POST /api/v1/ai/learning/promote)
  # =========================================================================
  describe "POST /api/v1/ai/learning/promote" do
    let(:path) { "/api/v1/ai/learning/promote" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.analytics.manage permission' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
    end
  end

  # =========================================================================
  # BENCHMARKS (GET /api/v1/ai/learning/benchmarks)
  # =========================================================================
  describe "GET /api/v1/ai/learning/benchmarks" do
    let(:path) { "/api/v1/ai/learning/benchmarks" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.analytics.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['benchmarks']).to be_an(Array)
    end
  end

  # =========================================================================
  # CREATE BENCHMARK (POST /api/v1/ai/learning/benchmarks)
  # =========================================================================
  describe "POST /api/v1/ai/learning/benchmarks" do
    let(:path) { "/api/v1/ai/learning/benchmarks" }
    let(:valid_params) { { name: "Test Benchmark", agent_id: agent.id, thresholds: { latency: 100 } } }

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.manage permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.analytics.manage permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # EVALUATION RESULTS (GET /api/v1/ai/learning/evaluation_results)
  # =========================================================================
  describe "GET /api/v1/ai/learning/evaluation_results" do
    let(:path) { "/api/v1/ai/learning/evaluation_results" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.analytics.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # COMPOUND MAINTENANCE (POST /api/v1/ai/learning/compound_maintenance)
  # =========================================================================
  describe "POST /api/v1/ai/learning/compound_maintenance" do
    let(:path) { "/api/v1/ai/learning/compound_maintenance" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.manage permission' do
      post path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.analytics.manage permission' do
      post path, headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
    end
  end
end
