# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::AnalyticsReportsController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.analytics.read', account: account) }
  let(:create_user) { user_with_permissions('ai.analytics.create', account: account) }
  let(:manage_user) { user_with_permissions('ai.analytics.manage', account: account) }
  let(:export_user) { user_with_permissions('ai.analytics.export', account: account) }
  let(:full_user) do
    user_with_permissions(
      'ai.analytics.read', 'ai.analytics.create',
      'ai.analytics.manage', 'ai.analytics.export',
      account: account
    )
  end
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:report1) { create(:report_request, account: account, user: read_user, report_type: 'revenue_analytics') }
  let!(:report2) { create(:report_request, account: account, user: read_user, report_type: 'customer_analytics') }

  before do
    allow_any_instance_of(Ai::Analytics::ReportService).to receive(:available_reports).and_return([
      { id: 'executive_summary', name: 'Executive Summary', description: 'High-level overview', category: 'summary', formats: %w[json csv pdf] }
    ])
  end

  # =========================================================================
  # REPORTS INDEX (ai.analytics.read)
  # =========================================================================
  describe "GET /api/v1/ai/analytics/reports" do
    let(:path) { "/api/v1/ai/analytics/reports" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with reports list' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['reports']).to be_an(Array)
      expect(json_response['data']['reports'].length).to eq(2)
    end

    it 'includes pagination data' do
      get path, params: { page: 1, per_page: 1 }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['pagination']).to include(
        'current_page' => 1,
        'per_page' => 1
      )
    end

    it 'limits per_page to 100' do
      get path, params: { per_page: 200 }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['pagination']['per_page']).to eq(100)
    end
  end

  # =========================================================================
  # REPORT SHOW (ai.analytics.read)
  # =========================================================================
  describe "GET /api/v1/ai/analytics/reports/:id" do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/analytics/reports/#{report1.id}", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get "/api/v1/ai/analytics/reports/#{report1.id}", headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns report details' do
      get "/api/v1/ai/analytics/reports/#{report1.id}", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['report']['id']).to eq(report1.id)
    end

    it 'returns 404 for nonexistent report' do
      get "/api/v1/ai/analytics/reports/nonexistent", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # REPORT CREATE (ai.analytics.create)
  # =========================================================================
  describe "POST /api/v1/ai/analytics/reports" do
    let(:path) { "/api/v1/ai/analytics/reports" }
    let(:valid_params) { { report: { template_id: 'revenue_analytics' } } }

    before do
      allow(GenerateReportJob).to receive(:perform_later)
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a report request' do
      expect {
        post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      }.to change(ReportRequest, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
      expect(json_response['data']['report']['type']).to eq('revenue_analytics')
    end

    it 'queues a background job' do
      expect(GenerateReportJob).to receive(:perform_later)
      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
    end
  end

  # =========================================================================
  # REPORT CANCEL (ai.analytics.manage)
  # =========================================================================
  describe "DELETE /api/v1/ai/analytics/reports/:id" do
    let(:pending_report) { create(:report_request, account: account, user: manage_user, status: 'pending') }
    let(:completed_report) { create(:report_request, account: account, user: manage_user, status: 'completed') }

    it 'returns 401 when unauthenticated' do
      delete "/api/v1/ai/analytics/reports/#{pending_report.id}", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.manage permission' do
      delete "/api/v1/ai/analytics/reports/#{pending_report.id}", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'cancels a pending report' do
      delete "/api/v1/ai/analytics/reports/#{pending_report.id}", headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['message']).to include('cancelled successfully')
      expect(pending_report.reload.status).to eq('failed')
    end

    it 'cannot cancel a completed report' do
      delete "/api/v1/ai/analytics/reports/#{completed_report.id}", headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 404 for nonexistent report' do
      delete "/api/v1/ai/analytics/reports/nonexistent", headers: auth_headers_for(manage_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # REPORT DOWNLOAD (ai.analytics.export)
  # =========================================================================
  describe "GET /api/v1/ai/analytics/reports/:id/download" do
    let(:reports_dir) { Rails.root.join('tmp', 'reports') }
    let(:test_report_path) { reports_dir.join('test_download_report.pdf').to_s }
    let(:completed_report) do
      create(:report_request,
        account: account,
        user: export_user,
        status: 'completed',
        file_path: test_report_path
      )
    end
    let(:pending_report) { create(:report_request, account: account, user: export_user, status: 'pending') }

    before do
      FileUtils.mkdir_p(reports_dir)
      File.write(test_report_path, 'test pdf content')
    end

    after do
      File.delete(test_report_path) if File.exist?(test_report_path)
    end

    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/analytics/reports/#{completed_report.id}/download", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.analytics.export permission' do
      get "/api/v1/ai/analytics/reports/#{completed_report.id}/download", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'downloads a completed report' do
      get "/api/v1/ai/analytics/reports/#{completed_report.id}/download", headers: auth_headers_for(export_user)
      expect(response).to have_http_status(:success)
    end

    it 'cannot download a pending report' do
      get "/api/v1/ai/analytics/reports/#{pending_report.id}/download", headers: auth_headers_for(export_user)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # =========================================================================
  # REPORT TEMPLATES (ai.analytics.read)
  # =========================================================================
  describe "GET /api/v1/ai/analytics/reports/templates" do
    let(:path) { "/api/v1/ai/analytics/reports/templates" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns available report templates' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']['templates']).to be_an(Array)
      expect(json_response['data']['templates'].length).to be > 0
    end
  end
end
