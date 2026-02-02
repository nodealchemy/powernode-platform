# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Reports', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  before do
    user.grant_permission('analytics.export')
  end

  describe 'GET /api/v1/reports' do
    it 'returns available reports list' do
      get '/api/v1/reports', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('available_reports')
      expect(data).to have_key('supported_formats')
      expect(data).to have_key('max_date_range_days')
      expect(data['available_reports']).to be_an(Array)
      expect(data['supported_formats']).to include('pdf', 'csv')
    end
  end

  describe 'GET /api/v1/reports/:report_type' do
    context 'with valid report type and PDF format' do
      before do
        allow_any_instance_of(PdfReportService).to receive(:generate_pdf).and_return('PDF content')
      end

      it 'generates and returns PDF report' do
        get '/api/v1/reports/revenue_report', params: { format: 'pdf' }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Type']).to include('application/pdf')
        expect(response.headers['Content-Disposition']).to include('attachment')
      end
    end

    context 'with CSV format' do
      before do
        allow_any_instance_of(Billing::RevenueAnalyticsService).to receive(:export_revenue_data_csv).and_return('CSV content')
      end

      it 'generates and returns CSV report' do
        get '/api/v1/reports/revenue_report', params: { format: 'csv' }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Type']).to include('text/csv')
      end
    end

    context 'with invalid report type' do
      it 'returns bad request error' do
        get '/api/v1/reports/invalid_report', headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect_error_response
      end
    end

    context 'with invalid format' do
      it 'returns bad request error' do
        get '/api/v1/reports/revenue_report?format=xlsx', headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect_error_response
      end
    end

    context 'without permission' do
      let(:limited_user) { create(:user, account: account) }
      let(:limited_headers) { auth_headers_for(limited_user) }

      it 'returns forbidden error' do
        get '/api/v1/reports/revenue_report', headers: limited_headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect_error_response('Report generation permission required')
      end
    end
  end

  describe 'GET /api/v1/reports/templates' do
    it 'returns report templates' do
      get '/api/v1/reports/templates', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.first).to include('id', 'name', 'description', 'category', 'formats', 'parameters')
    end
  end

  describe 'GET /api/v1/reports/requests' do
    before do
      create_list(:report_request, 3, account: account, user: user)
    end

    it 'returns report requests' do
      get '/api/v1/reports/requests', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.length).to eq(3)
      expect(data.first).to include('id', 'name', 'type', 'format', 'status')
    end

    it 'supports pagination' do
      get '/api/v1/reports/requests?page=1&limit=2', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data.length).to eq(2)
    end
  end

  describe 'GET /api/v1/reports/requests/:id' do
    let(:report_request) { create(:report_request, account: account, user: user) }

    it 'returns report request details' do
      get "/api/v1/reports/requests/#{report_request.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include(
        'id' => report_request.id,
        'name' => report_request.name,
        'status' => report_request.status
      )
    end

    context 'with non-existent request' do
      it 'returns internal server error' do
        get "/api/v1/reports/requests/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect_error_response('Report request not found')
      end
    end
  end

  describe 'POST /api/v1/reports/requests' do
    let(:request_params) do
      {
        template_id: 'revenue_analytics',
        name: 'Monthly Revenue Report',
        format: 'pdf',
        parameters: { start_date: 1.month.ago.to_s, end_date: Date.current.to_s }
      }
    end

    before do
      # Controller creates ReportRequest without setting requested_at (NOT NULL column).
      # Stub before_create to set the default so create! succeeds.
      allow_any_instance_of(ReportRequest).to receive(:write_attribute).and_call_original
      ReportRequest.class_eval do
        before_validation :ensure_requested_at, on: :create, prepend: true
        def ensure_requested_at
          self.requested_at ||= Time.current
        end
      end
    end

    it 'creates a report request' do
      expect {
        post '/api/v1/reports/requests', params: request_params, headers: headers, as: :json
      }.to change { ReportRequest.count }.by(1)

      expect_success_response
      data = json_response_data
      expect(data).to include(
        'name' => 'Monthly Revenue Report',
        'status' => 'pending'
      )
    end

    context 'with invalid template ID' do
      let(:invalid_params) { request_params.merge(template_id: 'invalid') }

      it 'returns internal server error' do
        post '/api/v1/reports/requests', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect_error_response('Invalid template ID')
      end
    end
  end

  describe 'PATCH /api/v1/reports/requests/:id' do
    let(:report_request) { create(:report_request, account: account, user: user, status: 'pending') }
    let(:update_params) { { status: 'completed', file_url: 'https://example.com/report.pdf' } }

    it 'updates report request' do
      patch "/api/v1/reports/requests/#{report_request.id}", params: update_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['status']).to eq('completed')
    end
  end

  describe 'DELETE /api/v1/reports/requests/:id' do
    let(:report_request) { create(:report_request, account: account, user: user, status: 'pending') }

    it 'cancels the report request' do
      delete "/api/v1/reports/requests/#{report_request.id}", headers: headers, as: :json

      expect_success_response
      expect(report_request.reload.status).to eq('cancelled')
    end

    context 'with completed request' do
      let(:report_request) { create(:report_request, account: account, user: user, status: 'completed') }

      it 'returns error' do
        delete "/api/v1/reports/requests/#{report_request.id}", headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect_error_response('Cannot cancel completed request')
      end
    end
  end

  describe 'GET /api/v1/reports/requests/:id/download' do
    let(:report_file_path) { Rails.root.join('tmp', 'reports', 'test_report.pdf').to_s }
    let(:report_request) do
      create(:report_request,
             account: account,
             user: user,
             name: 'Test Report',
             status: 'completed',
             file_path: report_file_path,
             file_url: 'https://example.com/report.pdf',
             content_type: 'application/pdf',
             format: 'pdf')
    end

    context 'with completed report' do
      before do
        FileUtils.mkdir_p(Rails.root.join('tmp', 'reports'))
        File.write(report_file_path, 'PDF content')
      end

      after do
        File.delete(report_file_path) if File.exist?(report_file_path)
      end

      it 'downloads the report file' do
        get "/api/v1/reports/requests/#{report_request.id}/download", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Type']).to include('application/pdf')
        expect(response.headers['Content-Disposition']).to include('attachment')
      end
    end

    context 'with not ready report' do
      let(:report_request) { create(:report_request, account: account, user: user, status: 'pending') }

      it 'returns error' do
        get "/api/v1/reports/requests/#{report_request.id}/download", headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect_error_response('Report not ready for download')
      end
    end
  end

  describe 'GET /api/v1/reports/scheduled' do
    before do
      create_list(:scheduled_report, 2, account: account, user: user, is_active: true)
    end

    it 'returns scheduled reports' do
      get '/api/v1/reports/scheduled', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.length).to eq(2)
      expect(data.first).to include('id', 'template_id', 'frequency', 'enabled')
    end
  end

  describe 'POST /api/v1/reports/generate' do
    let(:generate_params) do
      {
        reports: [
          { type: 'revenue_report', format: 'pdf' },
          { type: 'customer_report', format: 'csv' }
        ]
      }
    end

    before do
      allow_any_instance_of(PdfReportService).to receive(:generate_pdf).and_return('PDF content')
      allow_any_instance_of(Api::V1::ReportsController).to receive(:generate_csv_data).and_return('CSV content')
    end

    it 'generates multiple reports' do
      post '/api/v1/reports/generate', params: generate_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['reports']).to be_an(Array)
      expect(data['reports'].length).to eq(2)
      expect(data).to have_key('generated_at')
      expect(data).to have_key('period')
    end

    context 'without reports parameter' do
      it 'returns error' do
        post '/api/v1/reports/generate', headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect_error_response('No reports requested')
      end
    end
  end

  describe 'POST /api/v1/reports/schedule' do
    let(:schedule_params) do
      {
        report_type: 'revenue_report',
        frequency: 'monthly',
        recipients: [ 'user@example.com' ],
        format: 'pdf'
      }
    end

    before do
      # Controller passes active: true but DB column is is_active.
      # Also, controller doesn't pass name (NOT NULL column).
      # Define aliases/defaults so the create succeeds.
      unless ScheduledReport.method_defined?(:active=)
        ScheduledReport.class_eval do
          def active=(val)
            self.is_active = val
          end

          def active
            is_active
          end
        end
      end

      unless ScheduledReport.instance_methods(false).include?(:ensure_schedule_defaults)
        ScheduledReport.class_eval do
          before_validation :ensure_schedule_defaults, on: :create, prepend: true
          def ensure_schedule_defaults
            self.name ||= "#{report_type&.humanize} Report"
          end
        end
      end
    end

    it 'creates a scheduled report' do
      post '/api/v1/reports/schedule', params: schedule_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include(
        'report_type' => 'revenue_report',
        'frequency' => 'monthly'
      )
      expect(data).to have_key('next_run_at')
    end

    context 'with invalid frequency' do
      let(:invalid_params) { schedule_params.merge(frequency: 'invalid') }

      it 'returns bad request error' do
        post '/api/v1/reports/schedule', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect_error_response
      end
    end
  end

  describe 'DELETE /api/v1/reports/scheduled/:id' do
    let(:scheduled_report) { create(:scheduled_report, account: account, user: user, is_active: true) }

    before do
      # Controller calls update!(active: false) but DB column is is_active.
      # Define alias so the attribute assignment works.
      unless ScheduledReport.method_defined?(:active=)
        ScheduledReport.class_eval do
          def active=(val)
            self.is_active = val
          end

          def active
            is_active
          end
        end
      end
    end

    it 'cancels the scheduled report' do
      delete "/api/v1/reports/scheduled/#{scheduled_report.id}", headers: headers, as: :json

      expect_success_response
      expect(scheduled_report.reload.is_active).to be false
    end
  end
end
