# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Learning', type: :request do
  let(:account) { create(:account) }
  let(:read_user) { create(:user, account: account, permissions: ['ai.analytics.read']) }
  let(:manage_user) { create(:user, account: account, permissions: ['ai.analytics.read', 'ai.analytics.manage']) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }
  let(:read_headers) { auth_headers_for(read_user) }
  let(:manage_headers) { auth_headers_for(manage_user) }

  describe 'GET /api/v1/ai/learning/recommendations' do
    let!(:rec1) { create(:ai_improvement_recommendation, :pending, account: account) }
    let!(:rec2) { create(:ai_improvement_recommendation, :applied, account: account) }
    let!(:rec3) { create(:ai_improvement_recommendation, :dismissed, account: account) }

    it 'returns list of recommendations' do
      get '/api/v1/ai/learning/recommendations', headers: read_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['recommendations']).to be_an(Array)
      expect(data['recommendations'].length).to eq(3)
    end

    it 'filters by status' do
      get '/api/v1/ai/learning/recommendations?status=pending', headers: read_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['recommendations'].length).to eq(1)
      expect(data['recommendations'].first['status']).to eq('pending')
    end

    it 'filters by type' do
      create(:ai_improvement_recommendation, :cost_optimization, account: account)

      get '/api/v1/ai/learning/recommendations?type=cost_optimization',
          headers: read_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['recommendations'].all? { |r| r['recommendation_type'] == 'cost_optimization' }).to be true
    end

    it 'respects limit parameter' do
      get '/api/v1/ai/learning/recommendations?limit=2', headers: read_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['recommendations'].length).to eq(2)
    end

    it 'includes all expected fields' do
      get '/api/v1/ai/learning/recommendations', headers: read_headers, as: :json

      expect_success_response
      data = json_response_data
      rec = data['recommendations'].first
      expect(rec).to include(
        'id', 'recommendation_type', 'target_type', 'target_id',
        'confidence_score', 'status', 'created_at'
      )
    end

    context 'without permission' do
      it 'returns forbidden' do
        get '/api/v1/ai/learning/recommendations',
            headers: auth_headers_for(unauthorized_user), as: :json

        expect_error_response("Permission denied", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get '/api/v1/ai/learning/recommendations', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/ai/learning/recommendations/:id/apply' do
    let(:recommendation) { create(:ai_improvement_recommendation, :pending, account: account) }

    it 'applies recommendation with manage permission' do
      allow_any_instance_of(Ai::Learning::ImprovementRecommender).to receive(:apply_recommendation!)
        .and_return(recommendation.tap { |r| r.update!(status: 'applied', applied_at: Time.current) })

      post "/api/v1/ai/learning/recommendations/#{recommendation.id}/apply",
           headers: manage_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['recommendation']).to be_present
    end

    it 'returns not found for missing recommendation' do
      allow_any_instance_of(Ai::Learning::ImprovementRecommender).to receive(:apply_recommendation!)
        .and_return(nil)

      post '/api/v1/ai/learning/recommendations/nonexistent-id/apply',
           headers: manage_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    context 'with only read permission' do
      it 'returns forbidden' do
        post "/api/v1/ai/learning/recommendations/#{recommendation.id}/apply",
             headers: read_headers, as: :json

        expect_error_response("Permission denied", 403)
      end
    end
  end

  describe 'POST /api/v1/ai/learning/recommendations/:id/dismiss' do
    let(:recommendation) { create(:ai_improvement_recommendation, :pending, account: account) }

    it 'dismisses recommendation with manage permission' do
      post "/api/v1/ai/learning/recommendations/#{recommendation.id}/dismiss",
           headers: manage_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['recommendation']['status']).to eq('dismissed')
    end

    it 'returns not found for missing recommendation' do
      post '/api/v1/ai/learning/recommendations/nonexistent-id/dismiss',
           headers: manage_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    context 'with only read permission' do
      it 'returns forbidden' do
        post "/api/v1/ai/learning/recommendations/#{recommendation.id}/dismiss",
             headers: read_headers, as: :json

        expect_error_response("Permission denied", 403)
      end
    end
  end

  describe 'GET /api/v1/ai/learning/agent_trends' do
    it 'returns trends for active agents' do
      allow_any_instance_of(Ai::Learning::EvaluationService).to receive(:agent_score_trends)
        .and_return({ avg_score: 0.85, trend: 'improving', data_points: 10 })

      create(:ai_agent, account: account, status: 'active')

      get '/api/v1/ai/learning/agent_trends', headers: read_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['trends']).to be_an(Array)
    end

    it 'skips agents with no trend data' do
      allow_any_instance_of(Ai::Learning::EvaluationService).to receive(:agent_score_trends)
        .and_return(nil)

      create(:ai_agent, account: account, status: 'active')

      get '/api/v1/ai/learning/agent_trends', headers: read_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['trends']).to eq([])
    end

    context 'without permission' do
      it 'returns forbidden' do
        get '/api/v1/ai/learning/agent_trends',
            headers: auth_headers_for(unauthorized_user), as: :json

        expect_error_response("Permission denied", 403)
      end
    end
  end

  describe 'GET /api/v1/ai/learning/cache_metrics' do
    it 'returns cache metrics' do
      allow(Ai::Learning::PromptCacheService).to receive(:metrics)
        .and_return({ hit_rate: 0.72, total_hits: 1500, total_misses: 580 })

      get '/api/v1/ai/learning/cache_metrics', headers: read_headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['metrics']).to include('hit_rate', 'total_hits', 'total_misses')
    end

    context 'without permission' do
      it 'returns forbidden' do
        get '/api/v1/ai/learning/cache_metrics',
            headers: auth_headers_for(unauthorized_user), as: :json

        expect_error_response("Permission denied", 403)
      end
    end
  end
end
