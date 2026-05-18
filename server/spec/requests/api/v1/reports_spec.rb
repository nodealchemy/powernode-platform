# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Reports', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  before do
    user.grant_permission('analytics.export')
    allow(WorkerJobService).to receive(:enqueue_job)
  end

  describe 'GET /api/v1/reports' do
    it 'returns the available reports catalog' do
      get '/api/v1/reports', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['supported_formats']).to match_array(%w[pdf csv])
      expect(data['available_reports'].map { |r| r['type'] }).to match_array(PdfReportService::REPORT_TYPES)
      expect(data).to have_key('max_date_range_days')
    end

    context 'without permission' do
      let(:limited_user) { create(:user, account: account) }
      let(:limited_headers) { auth_headers_for(limited_user) }

      it 'returns forbidden' do
        get '/api/v1/reports', headers: limited_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/reports/templates' do
    it 'returns templates keyed on canonical report types' do
      get '/api/v1/reports/templates', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data.map { |t| t['id'] }).to match_array(PdfReportService::REPORT_TYPES)
      expect(data.first).to include('id', 'name', 'description', 'category', 'formats', 'parameters')
    end
  end

  describe 'GET /api/v1/reports/requests' do
    before do
      create_list(:report_request, 3, account: account, user: user)
    end

    it 'returns the account report requests' do
      get '/api/v1/reports/requests', headers: headers, as: :json

      expect_success_response
      expect(json_response_data.length).to eq(3)
    end

    it 'paginates by page and limit' do
      get '/api/v1/reports/requests?page=1&limit=2', headers: headers, as: :json

      expect_success_response
      expect(json_response_data.length).to eq(2)
    end
  end

  describe 'GET /api/v1/reports/requests/:id' do
    let(:report_request) { create(:report_request, account: account, user: user) }

    it 'returns details' do
      get "/api/v1/reports/requests/#{report_request.id}", headers: headers, as: :json

      expect_success_response
      expect(json_response_data['id']).to eq(report_request.id)
    end

    it 'returns not_found when missing' do
      get "/api/v1/reports/requests/#{SecureRandom.uuid}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/reports/requests' do
    let(:valid_params) do
      {
        template_id: 'revenue_analytics',
        name: 'Q1 Revenue',
        format: 'pdf',
        parameters: { date_range: { start_date: '2026-01-01', end_date: '2026-03-31' } }
      }
    end

    it 'creates a pending ReportRequest and dispatches the worker job' do
      expect {
        post '/api/v1/reports/requests', params: valid_params, headers: headers, as: :json
      }.to change { ReportRequest.count }.by(1)

      expect(response).to have_http_status(:accepted)
      data = json_response_data
      expect(data['status']).to eq('pending')
      expect(data['type']).to eq('revenue_analytics')

      expect(WorkerJobService).to have_received(:enqueue_job).with(
        "Reports::GenerateReportJob",
        hash_including(args: [an_instance_of(String)], queue: "reports")
      )
    end

    it 'rejects an unknown template_id' do
      post '/api/v1/reports/requests', params: valid_params.merge(template_id: 'mystery'), headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects an unsupported format' do
      post '/api/v1/reports/requests', params: valid_params.merge(format: 'xlsx'), headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'DELETE /api/v1/reports/requests/:id' do
    it 'cancels a pending request' do
      pending_request = create(:report_request, account: account, user: user, status: 'pending')
      delete "/api/v1/reports/requests/#{pending_request.id}", headers: headers, as: :json
      expect_success_response
      expect(pending_request.reload.status).to eq('cancelled')
    end

    it 'refuses to cancel a completed request' do
      completed = create(:report_request, account: account, user: user, status: 'completed')
      delete "/api/v1/reports/requests/#{completed.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'GET /api/v1/reports/requests/:id/download' do
    let(:file_path) { Rails.root.join('tmp', 'reports', "test_#{SecureRandom.hex(4)}.pdf").to_s }

    before do
      FileUtils.mkdir_p(Rails.root.join('tmp', 'reports'))
      File.write(file_path, 'PDF bytes')
    end

    after do
      File.delete(file_path) if File.exist?(file_path)
    end

    it 'streams the rendered file for a completed request' do
      report_request = create(:report_request,
                              account: account,
                              user: user,
                              status: 'completed',
                              file_path: file_path,
                              file_url: 'http://localhost:3000/api/v1/reports/requests/x/download',
                              content_type: 'application/pdf',
                              format: 'pdf')

      get "/api/v1/reports/requests/#{report_request.id}/download", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Type']).to include('application/pdf')
      expect(response.headers['Content-Disposition']).to include('attachment')
    end

    it 'rejects requests that are not ready' do
      pending_request = create(:report_request, account: account, user: user, status: 'pending')
      get "/api/v1/reports/requests/#{pending_request.id}/download", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'blocks paths outside tmp/reports' do
      bad_request = create(:report_request,
                           account: account,
                           user: user,
                           status: 'completed',
                           file_path: '/etc/passwd',
                           content_type: 'application/pdf')

      get "/api/v1/reports/requests/#{bad_request.id}/download", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/reports/scheduled' do
    before do
      create_list(:scheduled_report, 2, account: account, user: user, is_active: true)
    end

    it 'returns active scheduled reports' do
      get '/api/v1/reports/scheduled', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data.length).to eq(2)
      expect(data.first).to include('id', 'template_id', 'frequency', 'enabled', 'recipients')
    end
  end
end
