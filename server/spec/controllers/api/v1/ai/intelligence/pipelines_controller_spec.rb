# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::Intelligence::PipelinesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:intel_user) { create(:user, account: account, permissions: ['ai.intelligence.view']) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'

    allow_any_instance_of(Ai::Intelligence::PipelineIntelligenceService).to receive(:analyze_failure).and_return({
      success: true, pipeline_run_id: SecureRandom.uuid, root_cause: { category: "timeout" },
      suggested_fixes: [], step_analysis: []
    })

    allow_any_instance_of(Ai::Intelligence::PipelineIntelligenceService).to receive(:health_check).and_return({
      success: true, total_pipelines: 0, overall_health: "healthy", pipelines: []
    })

    allow_any_instance_of(Ai::Intelligence::PipelineIntelligenceService).to receive(:failure_trends).and_return({
      success: true, period_days: 30, total_runs: 0, failed_runs: 0,
      failure_rate: 0, weekly_trends: [], failure_categories: {}
    })
  end

  describe 'POST #analyze_failure' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns failure analysis' do
        post :analyze_failure, params: { pipeline_run_id: SecureRandom.uuid }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'returns error when service returns failure' do
        allow_any_instance_of(Ai::Intelligence::PipelineIntelligenceService).to receive(:analyze_failure).and_return({
          success: false, error: "Pipeline run not found"
        })

        post :analyze_failure, params: { pipeline_run_id: SecureRandom.uuid }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :analyze_failure, params: { pipeline_run_id: SecureRandom.uuid }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #health' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns health data' do
        get :health

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('overall_health')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :health

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #trends' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns trend data' do
        get :trends

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('period_days')
      end

      it 'passes period_days parameter' do
        expect_any_instance_of(Ai::Intelligence::PipelineIntelligenceService).to receive(:failure_trends).with(
          hash_including(period_days: 60)
        ).and_return({ success: true, period_days: 60, total_runs: 0, failed_runs: 0, failure_rate: 0, weekly_trends: [], failure_categories: {} })

        get :trends, params: { days: 60 }

        expect(response).to have_http_status(:success)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :trends

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
