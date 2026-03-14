# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Accounts', type: :request do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
  end

  # owner is simply a user belonging to this account
  before do
    owner # ensure the owner user is created
  end

  describe 'GET /api/v1/internal/accounts/:id' do
    context 'with internal authentication' do
      it 'returns account details' do
        get "/api/v1/internal/accounts/#{account.id}", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['account']).to include(
          'id' => account.id,
          'name' => account.name
        )
      end

      it 'includes owner information' do
        get "/api/v1/internal/accounts/#{account.id}", headers: internal_headers, as: :json

        data = json_response_data
        expect(data['account']).to have_key('owner_email')
      end

      it 'includes subscription status' do
        get "/api/v1/internal/accounts/#{account.id}", headers: internal_headers, as: :json

        data = json_response_data
        expect(data['account']).to have_key('status')
      end
    end

    context 'when account does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/accounts/nonexistent-id', headers: internal_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/accounts/#{account.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/users' do
    before do
      create_list(:user, 3, account: account)
    end

    context 'with internal authentication' do
      it 'returns account users' do
        get "/api/v1/internal/accounts/#{account.id}/users", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to be_an(Array)
        expect(data.length).to eq(4) # 3 + owner
      end

      it 'includes user details' do
        get "/api/v1/internal/accounts/#{account.id}/users", headers: internal_headers, as: :json

        data = json_response_data
        first_user = data.first

        expect(first_user).to include('id', 'email', 'name')
      end
    end
  end

  describe 'PATCH /api/v1/internal/accounts/:account_id/anonymize_audit_logs' do
    before do
      create_list(:audit_log, 5, account: account, user: owner, ip_address: '192.168.1.1')
    end

    context 'with internal authentication' do
      it 'anonymizes audit logs' do
        patch "/api/v1/internal/accounts/#{account.id}/anonymize_audit_logs", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Anonymized')

        # Verify audit logs are anonymized
        account.reload
        audit_log = AuditLog.where(account_id: account.id).first
        expect(audit_log.ip_address).to eq('0.0.0.0')
      end
    end
  end

  describe 'PATCH /api/v1/internal/accounts/:account_id/anonymize_payments' do
    before do
      skip 'Business billing module not loaded' unless FactoryBot.factories.registered?(:payment)
      create_list(:payment, 3, account: account)
    end

    context 'with internal authentication' do
      it 'anonymizes payment records' do
        patch "/api/v1/internal/accounts/#{account.id}/anonymize_payments", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Anonymized')
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts/:account_id/api_keys' do
    before do
      create_list(:api_key, 3, account: account, created_by: owner)
    end

    context 'with internal authentication' do
      it 'deletes account API keys' do
        delete "/api/v1/internal/accounts/#{account.id}/api_keys", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Deleted')
        expect(account.api_keys.count).to eq(0)
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts/:account_id/webhooks' do
    before do
      create_list(:webhook_endpoint, 2, account: account)
    end

    context 'with internal authentication' do
      it 'deletes account webhooks' do
        delete "/api/v1/internal/accounts/#{account.id}/webhooks", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Deleted')
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts/:account_id/data_export_requests' do
    context 'with internal authentication' do
      it 'deletes data export requests' do
        delete "/api/v1/internal/accounts/#{account.id}/data_export_requests", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Deleted')
      end
    end
  end

  describe 'DELETE /api/v1/internal/accounts/:account_id/data_deletion_requests' do
    context 'with internal authentication' do
      it 'deletes data deletion requests' do
        delete "/api/v1/internal/accounts/#{account.id}/data_deletion_requests", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('Deleted')
      end
    end
  end
end
