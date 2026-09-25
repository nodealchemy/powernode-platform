# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Privacy', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/privacy/dashboard' do
    it 'returns privacy dashboard data' do
      get '/api/v1/privacy/dashboard', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('consents')
      expect(data).to have_key('export_requests')
      expect(data).to have_key('deletion_requests')
      expect(data).to have_key('terms_status')
      expect(data).to have_key('data_retention_info')
    end
  end

  describe 'GET /api/v1/privacy/consents' do
    it 'returns user consent preferences' do
      get '/api/v1/privacy/consents', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('consents')
      expect(data).to have_key('consent_types')
    end
  end

  describe 'PUT /api/v1/privacy/consents' do
    let(:consent_params) do
      {
        marketing: true,
        analytics: true,
        cookies: false
      }
    end

    it 'updates user consent preferences' do
      put '/api/v1/privacy/consents', params: consent_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('consents')
    end
  end

  describe 'POST /api/v1/privacy/export' do
    let(:export_params) do
      {
        format: 'json',
        export_type: 'full',
        include_data_types: [ 'profile', 'payments' ]
      }
    end

    context 'with valid export request' do
      it 'creates an export request' do
        expect {
          post '/api/v1/privacy/export', params: export_params, headers: headers, as: :json
        }.to change { DataManagement::ExportRequest.count }.by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response_data
        expect(data).to have_key('request')
      end
    end

    context 'with recent export request' do
      before do
        create(:data_management_export_request, user: user, account: account, created_at: 1.day.ago)
      end

      it 'returns rate limit error' do
        post '/api/v1/privacy/export', params: export_params, headers: headers, as: :json

        expect(response).to have_http_status(:too_many_requests)
        expect_error_response('You can only request one data export per week')
      end
    end
  end

  describe 'GET /api/v1/privacy/exports' do
    before do
      create_list(:data_management_export_request, 3, user: user, account: account)
    end

    it 'returns user export requests' do
      get '/api/v1/privacy/exports', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['requests']).to be_an(Array)
      expect(data['requests'].length).to eq(3)
    end
  end

  describe 'GET /api/v1/privacy/exports/:id/download' do
    let(:export_file_path) { Rails.root.join('tmp', 'data_exports', 'test_export.json').to_s }
    let(:export_request) do
      create(:data_management_export_request,
             user: user,
             account: account,
             status: 'completed',
             file_path: export_file_path,
             download_token: 'test-token',
             download_token_expires_at: 7.days.from_now)
    end

    context 'with valid download token' do
      before do
        FileUtils.mkdir_p(Rails.root.join('tmp', 'data_exports'))
        File.write(export_file_path, '{"test": "data"}')
      end

      after do
        File.delete(export_file_path) if File.exist?(export_file_path)
      end

      it 'downloads the export file' do
        # Do NOT use as: :json on GET with params - rack-test sends as POST
        get "/api/v1/privacy/exports/#{export_request.id}/download?token=test-token",
            headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Type']).to include('application/json')
      end
    end

    context 'with export not ready' do
      let(:export_request) do
        create(:data_management_export_request,
               user: user,
               account: account,
               status: 'pending',
               download_token: 'test-token',
               download_token_expires_at: 7.days.from_now)
      end

      it 'returns gone error' do
        # Do NOT use as: :json on GET with params - rack-test sends as POST
        get "/api/v1/privacy/exports/#{export_request.id}/download?token=test-token",
            headers: headers

        expect(response).to have_http_status(:gone)
        expect_error_response('Export is not available for download')
      end
    end

    # IMP-0310a1351dab review round 3, item 2: `downloadable?` checks the RAW
    # file_path (a file can genuinely exist there), so a file OUTSIDE the
    # allowed exports directory can still pass it and reach the separate
    # path-containment check, which 403s. record_download! must not have
    # already fired by the time that happens — a rejected download must
    # never count as "delivered" for the GDPR deletion gate
    # (DataManagement::ExportRequest#delivered_for_deletion? reads
    # downloaded_at).
    context 'when the file exists but outside the allowed exports directory' do
      let(:outside_file_path) { Rails.root.join('tmp', 'not_data_exports', 'test_export.json').to_s }
      let(:export_request) do
        create(:data_management_export_request,
               user: user,
               account: account,
               status: 'completed',
               file_path: outside_file_path,
               download_token: 'test-token',
               download_token_expires_at: 7.days.from_now)
      end

      before do
        FileUtils.mkdir_p(Rails.root.join('tmp', 'not_data_exports'))
        File.write(outside_file_path, '{"test": "data"}')
      end

      after do
        File.delete(outside_file_path) if File.exist?(outside_file_path)
      end

      it 'returns forbidden and does not record a download' do
        get "/api/v1/privacy/exports/#{export_request.id}/download?token=test-token",
            headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(export_request.reload.downloaded_at).to be_nil
      end
    end

    # Belt-and-suspenders on the RE-CHECK this fix added (post path
    # validation) — `downloadable?` already covers the common "file
    # genuinely missing" case via its own file_exists?, so this mostly pins
    # that the added check doesn't itself misbehave when the containment
    # check passes but the file is gone.
    context 'when the record says completed but the file is missing on disk' do
      let(:export_request) do
        create(:data_management_export_request,
               user: user,
               account: account,
               status: 'completed',
               file_path: Rails.root.join('tmp', 'data_exports', 'never_written.json').to_s,
               download_token: 'test-token',
               download_token_expires_at: 7.days.from_now)
      end

      it 'does not record a download' do
        get "/api/v1/privacy/exports/#{export_request.id}/download?token=test-token",
            headers: headers

        expect(export_request.reload.downloaded_at).to be_nil
      end
    end
  end

  describe 'POST /api/v1/privacy/deletion' do
    let(:deletion_params) do
      {
        deletion_type: 'full',
        reason: 'No longer need the service'
      }
    end

    context 'with valid deletion request' do
      it 'creates a deletion request' do
        expect {
          post '/api/v1/privacy/deletion', params: deletion_params, headers: headers, as: :json
        }.to change { DataManagement::DeletionRequest.count }.by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response_data
        expect(data).to have_key('request')
        expect(data).to have_key('grace_period_days')
      end
    end

    context 'with existing active deletion request' do
      before do
        create(:data_management_deletion_request, user: user, account: account, status: 'pending')
      end

      it 'returns conflict error' do
        post '/api/v1/privacy/deletion', params: deletion_params, headers: headers, as: :json

        expect(response).to have_http_status(:conflict)
        expect_error_response('You already have an active deletion request')
      end
    end

    # IMP-bf52b4da135b — 'activity' and 'analytics' are withdrawn from
    # DELETABLE_DATA_TYPES because nothing in core can erase them, and the
    # model now rejects them on create. This is the USER-FACING half of that
    # withdrawal: before it, this endpoint accepted a request for a category
    # the platform could never erase and reported it as submitted.
    #
    # The endpoint builds the request with `create!`; the resulting
    # ActiveRecord::RecordInvalid is turned into the platform's standard
    # VALIDATION_ERROR envelope by ApiResponse's `rescue_from`
    # (app/controllers/concerns/api_response.rb), not by Rails' debug
    # exception formatter — so this 422 and its message are real behaviour in
    # every environment, not a test-only artifact.
    context 'with a data type the platform cannot erase' do
      it 'rejects the request with a client error rather than raising' do
        expect {
          post '/api/v1/privacy/deletion',
               params: deletion_params.merge(data_types_to_delete: %w[profile analytics]),
               headers: headers,
               as: :json
        }.not_to change { DataManagement::DeletionRequest.count }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to include('analytics')
      end

      it 'still accepts a selection of advertised data types' do
        expect {
          post '/api/v1/privacy/deletion',
               params: deletion_params.merge(data_types_to_delete: %w[profile settings communications]),
               headers: headers,
               as: :json
        }.to change { DataManagement::DeletionRequest.count }.by(1)

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'GET /api/v1/privacy/deletion' do
    context 'with existing deletion request' do
      before do
        create(:data_management_deletion_request, user: user, account: account)
      end

      it 'returns deletion request status' do
        get '/api/v1/privacy/deletion', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('request')
        expect(data['request']).not_to be_nil
      end
    end

    context 'without deletion request' do
      it 'returns null request' do
        get '/api/v1/privacy/deletion', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['request']).to be_nil
      end
    end
  end

  describe 'DELETE /api/v1/privacy/deletion/:id' do
    let(:deletion_request) do
      create(:data_management_deletion_request, user: user, account: account, status: 'pending')
    end
    let(:cancel_params) { { reason: 'Changed my mind' } }

    before do
      # cancel! tries to set cancellation_reason column which doesn't exist in DB.
      # Stub it to update only valid columns.
      allow_any_instance_of(DataManagement::DeletionRequest).to receive(:cancel!).and_wrap_original do |method, *args|
        request = method.receiver
        request.update!(status: 'cancelled', completed_at: Time.current)
        true
      end
    end

    it 'cancels the deletion request' do
      delete "/api/v1/privacy/deletion/#{deletion_request.id}",
             params: cancel_params,
             headers: headers,
             as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('request')
    end
  end

  describe 'GET /api/v1/privacy/terms' do
    it 'returns terms acceptance status' do
      get '/api/v1/privacy/terms', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('current_versions')
      expect(data).to have_key('accepted')
      expect(data).to have_key('missing')
    end
  end

  describe 'POST /api/v1/privacy/terms/:document_type/accept' do
    let(:accept_params) { { version: '1.0' } }

    context 'with valid document type' do
      it 'records terms acceptance' do
        post '/api/v1/privacy/terms/terms_of_service/accept',
             params: accept_params,
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('acceptance')
      end
    end

    context 'with invalid document type' do
      it 'returns bad request error' do
        post '/api/v1/privacy/terms/invalid_type/accept',
             params: accept_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:bad_request)
        expect_error_response('Invalid document type')
      end
    end
  end
end
