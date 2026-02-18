# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::Intelligence::SupplyChainsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:intel_user) { create(:user, account: account, permissions: ['ai.intelligence.view']) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'

    allow_any_instance_of(Ai::Intelligence::SupplyChainAnalysisService).to receive(:triage_vulnerabilities).and_return({
      success: true, analysis: { risk_score: 42.5 }
    })

    allow_any_instance_of(Ai::Intelligence::SupplyChainAnalysisService).to receive(:security_posture).and_return({
      success: true, posture: { overall_risk: "low" }
    })

    allow_any_instance_of(Ai::Intelligence::SupplyChainAnalysisService).to receive(:analyze_risk_trends).and_return({
      success: true, current_state: { total_open: 0, by_severity: {} }
    })
  end

  describe 'POST #analyze' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns security posture when no sbom_id' do
        post :analyze, params: { target: 'dependencies' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'triages vulnerabilities when sbom_id provided' do
        post :analyze, params: { sbom_id: SecureRandom.uuid }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        post :analyze, params: { target: 'dependencies' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #risk_summary' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns risk summary data' do
        get :risk_summary

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :risk_summary

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #vulnerability_report' do
    context 'with valid permissions' do
      before { sign_in intel_user }

      it 'returns vulnerability report' do
        get :vulnerability_report

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :vulnerability_report

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
