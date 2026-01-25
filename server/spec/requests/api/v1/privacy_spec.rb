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
      expect(data['message']).to eq('Consent preferences updated')
      expect(data).to have_key('consents')
    end
  end

  describe 'POST /api/v1/privacy/export' do
    let(:export_params) do
      {
        format: 'json',
        export_type: 'full',
        include_data_types: ['profile', 'payments']
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
        expect(data['message']).to eq('Data export request submitted')
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
    let(:export_request) do
      create(:data_management_export_request,
             user: user,
             account: account,
             status: 'completed',
             file_path: Rails.root.join('tmp', 'data_exports', 'test_export.json').to_s,
             download_token: 'test-token')
    end

    before do
      FileUtils.mkdir_p(Rails.root.join('tmp', 'data_exports'))
      File.write(export_request.file_path, '{"test": "data"}')
    end

    after do
      File.delete(export_request.file_path) if File.exist?(export_request.file_path)
    end

    context 'with valid download token' do
      it 'downloads the export file' do
        get "/api/v1/privacy/exports/#{export_request.id}/download",
            params: { token: 'test-token' },
            headers: headers,
            as: :json

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
               download_token: 'test-token')
      end

      it 'returns gone error' do
        get "/api/v1/privacy/exports/#{export_request.id}/download",
            params: { token: 'test-token' },
            headers: headers,
            as: :json

        expect(response).to have_http_status(:gone)
        expect_error_response('Export is not available for download')
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
        expect(data['message']).to eq('Data deletion request submitted')
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

    it 'cancels the deletion request' do
      delete "/api/v1/privacy/deletion/#{deletion_request.id}",
             params: cancel_params,
             headers: headers,
             as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to eq('Deletion request cancelled')
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
        expect(data['message']).to eq('Terms of service accepted')
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

  describe 'GET /api/v1/privacy/cookies' do
    it 'returns cookie preferences' do
      get '/api/v1/privacy/cookies', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('preferences')
      expect(data['preferences']).to have_key('necessary')
      expect(data['preferences']).to have_key('functional')
      expect(data['preferences']).to have_key('analytics')
      expect(data['preferences']).to have_key('marketing')
    end
  end

  describe 'PUT /api/v1/privacy/cookies' do
    let(:cookie_params) do
      {
        functional: true,
        analytics: false,
        marketing: false
      }
    end

    it 'updates cookie preferences' do
      put '/api/v1/privacy/cookies', params: cookie_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to eq('Cookie preferences updated')
      expect(data).to have_key('preferences')
      expect(data['preferences']['necessary']).to be true
    end
  end
end
