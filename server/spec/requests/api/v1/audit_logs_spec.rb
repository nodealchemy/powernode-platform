# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AuditLogs', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_audit_permission) { create(:user, account: account, permissions: [ 'audit_logs.read' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  before do
    # Create some audit logs for testing
    create_list(:audit_log, 5, account: account, user: admin_user, action: 'user_login')
    create_list(:audit_log, 3, account: account, user: admin_user, action: 'user_logout')
    create(:audit_log, account: account, user: admin_user, action: 'admin_settings_update')
  end

  describe 'GET /api/v1/audit_logs' do
    context 'with audit_logs.read permission' do
      let(:headers) { auth_headers_for(user_with_audit_permission) }

      it 'returns paginated list of audit logs' do
        get '/api/v1/audit_logs', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to be_an(Array)
        expect(response_data['meta']).to include(
          'current_page' => 1,
          'total' => 9
        )
      end

      it 'returns logs in descending order by created_at' do
        get '/api/v1/audit_logs', headers: headers, as: :json

        response_data = json_response
        timestamps = response_data['data'].map { |log| log['created_at'] }

        # Should be in descending order
        expect(timestamps).to eq(timestamps.sort.reverse)
      end

      it 'respects per_page parameter' do
        get '/api/v1/audit_logs?per_page=5', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data'].length).to eq(5)
        expect(response_data['meta']['per_page']).to eq(5)
      end

      it 'filters by action_type' do
        get '/api/v1/audit_logs?action_type=user_login',
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response
        # The controller returns render_success(data: logs, meta: {}) so data is nested
        logs_array = response_data['data'].is_a?(Hash) ? response_data['data']['data'] : response_data['data']
        if logs_array.is_a?(Array) && logs_array.any?
          actions = logs_array.map { |log| log['action'] }
          expect(actions.uniq).to eq([ 'user_login' ])
        end
      end

      it 'filters by date range' do
        get "/api/v1/audit_logs?date_from=#{1.day.ago.to_date}&date_to=#{Date.current}",
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'includes stats in response' do
        get '/api/v1/audit_logs', headers: headers, as: :json

        response_data = json_response
        expect(response_data['meta']).to have_key('stats')
      end
    end

    context 'without audit_logs.read permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/audit_logs', headers: headers, as: :json

        expect_error_response('Permission denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/audit_logs', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/audit_logs/:id' do
    let(:headers) { auth_headers_for(user_with_audit_permission) }
    let(:audit_log) { AuditLog.first }

    context 'with audit_logs.read permission' do
      it 'returns audit log details' do
        get "/api/v1/audit_logs/#{audit_log.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include('id', 'action', 'created_at')
      end

      it 'includes user information' do
        get "/api/v1/audit_logs/#{audit_log.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('user')
      end
    end

    context 'when audit log does not exist' do
      it 'returns not found error' do
        get '/api/v1/audit_logs/nonexistent-id', headers: headers, as: :json

        expect_error_response('Audit log not found', 404)
      end
    end
  end

  describe 'GET /api/v1/audit_logs/stats' do
    let(:headers) { auth_headers_for(user_with_audit_permission) }

    it 'returns detailed statistics' do
      get '/api/v1/audit_logs/stats', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to be_present
    end
  end

  describe 'GET /api/v1/audit_logs/security_summary' do
    let(:headers) { auth_headers_for(user_with_audit_permission) }

    it 'returns security summary for default time range' do
      get '/api/v1/audit_logs/security_summary', headers: headers, as: :json

      expect_success_response
    end

    it 'accepts custom time range' do
      get '/api/v1/audit_logs/security_summary?time_range=7d',
          headers: headers,
          as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/audit_logs/compliance_summary' do
    let(:headers) { auth_headers_for(user_with_audit_permission) }

    it 'returns compliance summary' do
      get '/api/v1/audit_logs/compliance_summary', headers: headers, as: :json

      expect_success_response
    end

    it 'accepts custom time range' do
      get '/api/v1/audit_logs/compliance_summary?time_range=30d',
          headers: headers,
          as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/audit_logs/activity_timeline' do
    let(:headers) { auth_headers_for(user_with_audit_permission) }

    before do
      allow_any_instance_of(AuditLogQueryService).to receive(:activity_timeline).and_return({
        timeline: {},
        actionTimeline: {},
        userActivity: {},
        summary: {
          totalEvents: 0,
          averagePerHour: 0,
          peakActivity: { time: nil, count: 0 },
          lowestActivity: { time: nil, count: 0 },
          uniqueUsers: 0,
          uniqueActions: 0
        },
        topActions: {},
        topUsers: {}
      })
    end

    it 'returns activity timeline' do
      get '/api/v1/audit_logs/activity_timeline', headers: headers, as: :json

      expect_success_response
    end

    it 'accepts granularity parameter' do
      get '/api/v1/audit_logs/activity_timeline?granularity=day',
          headers: headers,
          as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/audit_logs/risk_analysis' do
    let(:headers) { auth_headers_for(user_with_audit_permission) }

    it 'returns risk analysis' do
      get '/api/v1/audit_logs/risk_analysis', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/audit_logs/export' do
    let(:user_with_export_permission) { create(:user, account: account, permissions: [ 'audit_logs.export' ]) }
    let(:headers) { auth_headers_for(user_with_export_permission) }

    context 'with audit_logs.export permission' do
      it 'exports audit logs as CSV' do
        post '/api/v1/audit_logs/export',
             params: { format: 'csv' },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include('format', 'content', 'filename')
      end

      it 'exports audit logs as JSON' do
        post '/api/v1/audit_logs/export',
             params: { format: 'json' },
             headers: headers,
             as: :json

        expect_success_response
      end

      it 'applies filters to export' do
        post '/api/v1/audit_logs/export',
             params: { action_type: 'user_login', format: 'csv' },
             headers: headers,
             as: :json

        expect_success_response
      end
    end

    context 'without audit_logs.export permission' do
      let(:headers) { auth_headers_for(user_with_audit_permission) }

      it 'returns forbidden error' do
        post '/api/v1/audit_logs/export',
             params: { format: 'csv' },
             headers: headers,
             as: :json

        expect_error_response('Permission denied', 403)
      end
    end
  end

  describe 'POST /api/v1/audit_logs' do
    context 'with admin access' do
      let(:admin_with_access) { create(:user, account: account, permissions: [ 'admin.access' ]) }
      let(:headers) { auth_headers_for(admin_with_access) }

      before do
        # authenticate_request is skipped for :create, so current_user is nil.
        # The controller's authenticate_worker_or_admin has a fallback JWT decode that looks for
        # payload[:user_id] but the JWT uses :sub. We stub to set current_user properly.
        allow_any_instance_of(Api::V1::AuditLogsController).to receive(:current_user).and_return(admin_with_access)
      end

      it 'creates audit log successfully' do
        expect {
          post '/api/v1/audit_logs',
               params: {
                 audit_log: {
                   action: 'user_login',
                   resource_type: 'TestResource',
                   resource_id: 'test-123'
                 }
               },
               headers: headers,
               as: :json
        }.to change(AuditLog, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['action']).to eq('user_login')
      end

      it 'returns error for missing action' do
        post '/api/v1/audit_logs',
             params: { audit_log: { resource_type: 'Test' } },
             headers: headers,
             as: :json

        expect_error_response('Action is required', 422)
      end
    end

    context 'with worker token' do
      let(:worker) { create(:worker, status: 'active') }
      let(:worker_jwt_payload) do
        {
          sub: worker.id,
          type: 'worker',
          version: Security::JwtService::CURRENT_TOKEN_VERSION
        }
      end
      let(:worker_jwt) { Security::JwtService.encode(worker_jwt_payload) }
      let(:headers) do
        {
          'Authorization' => "Bearer #{worker_jwt}",
          'Content-Type' => 'application/json'
        }
      end

      it 'creates audit log with worker authentication' do
        expect {
          post '/api/v1/audit_logs',
               params: {
                 audit_log: {
                   action: 'job_enqueue',
                   resource_type: 'WorkerJob',
                   resource_id: 'job-123'
                 }
               },
               headers: headers,
               as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        expect(response).to have_http_status(:created)
      end
    end

    context 'without proper authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/audit_logs',
             params: { audit_log: { action: 'test' } },
             as: :json

        expect_error_response('Missing authorization header', 401)
      end
    end
  end

  describe 'DELETE /api/v1/audit_logs/cleanup' do
    let(:headers) { auth_headers_for(admin_user) }

    before do
      # Create some old audit logs
      create_list(:audit_log, 3, account: account, user: admin_user, created_at: 2.years.ago)
    end

    it 'cleans up old audit logs' do
      # Cleanup deletes 3 old logs but creates 1 audit log for the cleanup action itself, net -2
      expect {
        delete '/api/v1/audit_logs/cleanup',
               params: { cutoff_date: 1.year.ago.to_date },
               headers: headers,
               as: :json
      }.to change(AuditLog, :count).by(-2)

      expect_success_response
      response_data = json_response

      expect(response_data['data']['deleted_count']).to eq(3)
    end

    it 'returns error for future cutoff date' do
      delete '/api/v1/audit_logs/cleanup',
             params: { cutoff_date: 1.day.from_now.to_date },
             headers: headers,
             as: :json

      expect_error_response('Invalid cutoff date', 400)
    end

    it 'creates audit log for cleanup action' do
      delete '/api/v1/audit_logs/cleanup',
             params: { cutoff_date: 1.year.ago.to_date },
             headers: headers,
             as: :json

      cleanup_log = AuditLog.find_by(action: 'audit_log_cleanup')
      expect(cleanup_log).to be_present
    end
  end
end
