# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::MarketplaceDiscoveryController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.manage']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.workflows.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let(:discovery_service) { instance_double(Ai::Marketplace::TemplateDiscoveryService) }

  before do
    sign_in_as_user(user)
    allow(Ai::Marketplace::TemplateDiscoveryService).to receive(:new).and_return(discovery_service)
    allow(Audit::LoggingService.instance).to receive(:log).and_return(true)
  end

  # ============================================================================
  # AUTHENTICATION - Public endpoints don't require auth
  # ============================================================================

  describe 'authentication' do
    it 'allows unauthenticated access to discover' do
      @request.env.delete('HTTP_AUTHORIZATION')
      allow(discovery_service).to receive(:discover).and_return({
        templates: [], total_count: 0, recommendations: []
      })

      get :discover
      expect(response).to have_http_status(:ok)
    end

    it 'allows unauthenticated access to featured' do
      @request.env.delete('HTTP_AUTHORIZATION')
      allow(discovery_service).to receive(:featured_templates).and_return([])

      get :featured
      expect(response).to have_http_status(:ok)
    end

    it 'allows unauthenticated access to popular' do
      @request.env.delete('HTTP_AUTHORIZATION')
      allow(discovery_service).to receive(:popular_templates).and_return([])

      get :popular
      expect(response).to have_http_status(:ok)
    end

    it 'allows unauthenticated access to categories' do
      @request.env.delete('HTTP_AUTHORIZATION')
      allow(discovery_service).to receive(:explore_categories).and_return([])

      get :categories
      expect(response).to have_http_status(:ok)
    end

    it 'allows unauthenticated access to tags' do
      @request.env.delete('HTTP_AUTHORIZATION')
      allow(discovery_service).to receive(:explore_tags).and_return([])

      get :tags
      expect(response).to have_http_status(:ok)
    end

    it 'allows unauthenticated access to search' do
      @request.env.delete('HTTP_AUTHORIZATION')
      allow(discovery_service).to receive(:advanced_search).and_return({
        templates: [], total_count: 0, suggestions: []
      })

      post :search, params: { query: 'test' }
      expect(response).to have_http_status(:ok)
    end

    it 'allows unauthenticated access to statistics' do
      @request.env.delete('HTTP_AUTHORIZATION')
      allow(discovery_service).to receive(:marketplace_statistics).and_return({
        total_templates: 0, total_installs: 0
      })

      get :statistics
      expect(response).to have_http_status(:ok)
    end

    it 'returns 401 for recommendations without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :recommendations
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for compare without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      post :compare, params: { template_ids: ['id1', 'id2'] }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # AUTHORIZATION
  # ============================================================================

  describe 'authorization' do
    context 'without permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for recommendations' do
        get :recommendations
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for compare' do
        post :compare, params: { template_ids: ['id1', 'id2'] }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in_as_user(read_only_user) }

      it 'allows recommendations access' do
        allow(discovery_service).to receive(:get_recommendations).and_return([])

        get :recommendations
        expect(response).to have_http_status(:ok)
      end

      it 'returns 403 for compare' do
        post :compare, params: { template_ids: ['id1', 'id2'] }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # DISCOVER
  # ============================================================================

  describe 'GET #discover' do
    it 'returns discovered templates' do
      allow(discovery_service).to receive(:discover).and_return({
        templates: [], total_count: 0, recommendations: []
      })

      get :discover
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['templates']).to be_an(Array)
      expect(json_response['data']).to have_key('total_count')
    end

    it 'accepts filtering parameters' do
      allow(discovery_service).to receive(:discover).and_return({
        templates: [], total_count: 0, recommendations: []
      })

      get :discover, params: {
        category: 'content_generation',
        difficulty: 'beginner',
        featured: 'true',
        sort_by: 'rating'
      }
      expect(response).to have_http_status(:ok)
    end
  end

  # ============================================================================
  # SEARCH
  # ============================================================================

  describe 'POST #search' do
    it 'returns search results' do
      allow(discovery_service).to receive(:advanced_search).and_return({
        templates: [], total_count: 0, suggestions: []
      })

      post :search, params: { query: 'automation' }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['templates']).to be_an(Array)
    end
  end

  # ============================================================================
  # RECOMMENDATIONS
  # ============================================================================

  describe 'GET #recommendations' do
    it 'returns recommendations' do
      allow(discovery_service).to receive(:get_recommendations).and_return([])

      get :recommendations
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['recommendations']).to be_an(Array)
    end
  end

  # ============================================================================
  # COMPARE
  # ============================================================================

  describe 'POST #compare' do
    it 'compares templates' do
      allow(discovery_service).to receive(:compare_templates).and_return({ comparison: [] })

      post :compare, params: { template_ids: [SecureRandom.uuid, SecureRandom.uuid] }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns error for fewer than 2 templates' do
      post :compare, params: { template_ids: [SecureRandom.uuid] }
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns error for more than 5 templates' do
      ids = 6.times.map { SecureRandom.uuid }
      post :compare, params: { template_ids: ids }
      expect(response).to have_http_status(:bad_request)
    end
  end

  # ============================================================================
  # FEATURED
  # ============================================================================

  describe 'GET #featured' do
    it 'returns featured templates' do
      allow(discovery_service).to receive(:featured_templates).and_return([])

      get :featured
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['templates']).to be_an(Array)
    end
  end

  # ============================================================================
  # POPULAR
  # ============================================================================

  describe 'GET #popular' do
    it 'returns popular templates' do
      allow(discovery_service).to receive(:popular_templates).and_return([])

      get :popular
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['templates']).to be_an(Array)
    end
  end

  # ============================================================================
  # CATEGORIES & TAGS
  # ============================================================================

  describe 'GET #categories' do
    it 'returns categories' do
      allow(discovery_service).to receive(:explore_categories).and_return([])

      get :categories
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  describe 'GET #tags' do
    it 'returns tags' do
      allow(discovery_service).to receive(:explore_tags).and_return([])

      get :tags
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # STATISTICS
  # ============================================================================

  describe 'GET #statistics' do
    it 'returns marketplace statistics' do
      allow(discovery_service).to receive(:marketplace_statistics).and_return({
        total_templates: 100, total_installs: 500
      })

      get :statistics
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['statistics']).to be_present
    end
  end

  # ============================================================================
  # TEMPLATE ANALYTICS
  # ============================================================================

  describe 'GET #template_analytics' do
    let(:template) { create(:ai_workflow_template, :public, account: account) }

    it 'returns template analytics' do
      allow(discovery_service).to receive(:template_analytics).and_return({
        views: 100, installs: 50, rating: 4.5
      })

      get :template_analytics, params: { id: template.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['analytics']).to be_present
    end

    it 'returns 404 for non-existent template' do
      get :template_analytics, params: { id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end
  end
end
