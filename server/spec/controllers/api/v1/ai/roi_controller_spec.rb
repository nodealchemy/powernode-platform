# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::RoiController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.roi.read', 'ai.roi.manage']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.roi.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let(:cost_service) { instance_double(Ai::Analytics::CostAnalysisService) }

  before do
    sign_in_as_user(user)
    allow(Ai::Analytics::CostAnalysisService).to receive(:new).and_return(cost_service)
    allow(Audit::LoggingService.instance).to receive(:log).and_return(true)
  end

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :dashboard
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # AUTHORIZATION
  # ============================================================================

  describe 'authorization' do
    context 'without permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for dashboard' do
        get :dashboard
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for summary' do
        get :summary
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for trends' do
        get :trends
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for daily_metrics' do
        get :daily_metrics
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for by_workflow' do
        get :by_workflow
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for by_agent' do
        get :by_agent
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for by_provider' do
        get :by_provider
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for cost_breakdown' do
        get :cost_breakdown
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for attributions' do
        get :attributions
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # DASHBOARD
  # ============================================================================

  describe 'GET #dashboard' do
    it 'returns dashboard data' do
      allow(cost_service).to receive(:roi_dashboard).and_return({
        total_cost: 100.0, total_savings: 50.0, roi_percentage: 150.0
      })

      get :dashboard
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['dashboard']).to be_present
      expect(json_response['data']['time_range']).to be_present
    end

    it 'accepts time_range parameter' do
      allow(cost_service).to receive(:roi_dashboard).and_return({
        total_cost: 100.0, total_savings: 50.0
      })

      get :dashboard, params: { time_range: '7d' }
      expect(response).to have_http_status(:ok)
    end

    it 'accepts hourly_rate parameter' do
      allow(cost_service).to receive(:roi_dashboard).and_return({
        total_cost: 100.0
      })

      get :dashboard, params: { hourly_rate: 100.0 }
      expect(response).to have_http_status(:ok)
    end
  end

  # ============================================================================
  # SUMMARY
  # ============================================================================

  describe 'GET #summary' do
    it 'returns summary metrics' do
      allow(cost_service).to receive(:roi_summary_metrics).and_return({
        total_cost: 500.0, total_value: 2000.0, roi: 300.0
      })

      get :summary
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['summary']).to be_present
    end

    it 'accepts period parameter' do
      allow(cost_service).to receive(:roi_summary_metrics).and_return({
        total_cost: 100.0
      })

      get :summary, params: { period: 7 }
      expect(response).to have_http_status(:ok)
    end
  end

  # ============================================================================
  # TRENDS
  # ============================================================================

  describe 'GET #trends' do
    it 'returns trend data' do
      allow(cost_service).to receive(:roi_trends).and_return([
        { date: '2026-01-01', cost: 10.0, value: 50.0 }
      ])

      get :trends
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['trends']).to be_present
    end
  end

  # ============================================================================
  # DAILY METRICS
  # ============================================================================

  describe 'GET #daily_metrics' do
    it 'returns daily metrics' do
      allow(cost_service).to receive(:roi_daily_metrics).and_return([
        { date: '2026-01-01', cost: 5.0 }
      ])

      get :daily_metrics
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['metrics']).to be_present
    end

    it 'accepts days parameter' do
      allow(cost_service).to receive(:roi_daily_metrics).and_return([])

      get :daily_metrics, params: { days: 7 }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['days']).to eq(7)
    end
  end

  # ============================================================================
  # BREAKDOWN BY WORKFLOW / AGENT / PROVIDER
  # ============================================================================

  describe 'GET #by_workflow' do
    it 'returns ROI by workflow' do
      allow(cost_service).to receive(:roi_by_workflow).and_return([])

      get :by_workflow
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['workflows']).to be_an(Array)
    end
  end

  describe 'GET #by_agent' do
    it 'returns ROI by agent' do
      allow(cost_service).to receive(:roi_by_agent).and_return([])

      get :by_agent
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['agents']).to be_an(Array)
    end
  end

  describe 'GET #by_provider' do
    it 'returns cost by provider' do
      allow(cost_service).to receive(:roi_cost_by_provider).and_return([])

      get :by_provider
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['providers']).to be_an(Array)
    end
  end

  # ============================================================================
  # COST BREAKDOWN
  # ============================================================================

  describe 'GET #cost_breakdown' do
    before do
      allow(Ai::CostAttribution).to receive(:cost_breakdown_by_category).and_return({})
      allow(Ai::CostAttribution).to receive(:cost_breakdown_by_source_type).and_return({})
      allow(Ai::CostAttribution).to receive(:cost_breakdown_by_provider).and_return({})
      allow(Ai::CostAttribution).to receive(:daily_cost_trend).and_return([])
      allow(Ai::CostAttribution).to receive(:top_cost_sources).and_return([])
    end

    it 'returns cost breakdown data' do
      get :cost_breakdown
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['cost_breakdown']).to be_present
      expect(json_response['data']['cost_breakdown']).to have_key('by_category')
      expect(json_response['data']['cost_breakdown']).to have_key('by_source_type')
      expect(json_response['data']['cost_breakdown']).to have_key('by_provider')
      expect(json_response['data']['cost_breakdown']).to have_key('daily_trend')
      expect(json_response['data']['cost_breakdown']).to have_key('top_sources')
    end

    it 'includes time_range info' do
      get :cost_breakdown, params: { time_range: '7d' }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['time_range']).to be_present
    end
  end

  # ============================================================================
  # ATTRIBUTIONS
  # ============================================================================

  describe 'GET #attributions' do
    it 'returns cost attributions' do
      create(:ai_cost_attribution, account: account)

      get :attributions
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['attributions']).to be_an(Array)
      expect(json_response['data']['pagination']).to be_present
    end

    it 'filters by category' do
      create(:ai_cost_attribution, :ai_inference, account: account)

      get :attributions, params: { category: 'ai_inference' }
      expect(response).to have_http_status(:ok)
    end

    it 'filters by source_type' do
      get :attributions, params: { source_type: 'workflow' }
      expect(response).to have_http_status(:ok)
    end

    it 'filters by date range' do
      get :attributions, params: {
        start_date: 7.days.ago.to_date.iso8601,
        end_date: Date.current.iso8601
      }
      expect(response).to have_http_status(:ok)
    end

    it 'paginates results' do
      get :attributions, params: { page: 1, per_page: 10 }
      expect(response).to have_http_status(:ok)
    end
  end
end
