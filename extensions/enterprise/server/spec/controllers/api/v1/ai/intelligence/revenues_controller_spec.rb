# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::Intelligence::RevenuesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:intel_user) { create(:user, account: account, permissions: ['ai.intelligence.view']) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'

    allow_any_instance_of(Ai::Intelligence::RevenueIntelligenceService).to receive(:forecast_accuracy_analysis).and_return({
      success: true, total_evaluated: 0, average_accuracy: nil, analyzed_at: Time.current.iso8601
    })

    allow_any_instance_of(Ai::Intelligence::RevenueIntelligenceService).to receive(:churn_risk_report).and_return({
      success: true, total_predictions: 0, risk_tier_distribution: {}
    })

    allow_any_instance_of(Ai::Intelligence::RevenueIntelligenceService).to receive(:health_score_distribution).and_return({
      success: true, total_accounts: 0, status_distribution: {}
    })
  end

  describe 'GET #forecast' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns forecast data' do
        get :forecast

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'returns data keys' do
        get :forecast

        json = JSON.parse(response.body)
        expect(json['data']).to include('total_evaluated')
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :forecast

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #churn_risks' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns churn risk data' do
        get :churn_risks

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :churn_risks

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #health_scores' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns health score data' do
        get :health_scores

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :health_scores

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
