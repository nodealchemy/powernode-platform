# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataExports', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/users/:user_id/export/profile' do
    context 'with internal authentication' do
      it 'returns user profile data' do
        get "/api/v1/internal/users/#{user.id}/export/profile", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to include(
          'id' => user.id,
          'email' => user.email
        )
      end

      it 'includes user timestamps' do
        get "/api/v1/internal/users/#{user.id}/export/profile", headers: internal_headers, as: :json

        response_data = json_response
        expect(response_data['data']['data']).to have_key('created_at')
      end
    end

    context 'when user does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/users/nonexistent-id/export/profile', headers: internal_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/users/#{user.id}/export/profile", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/users/:user_id/export/activity' do
    context 'with internal authentication' do
      it 'returns user activity data' do
        get "/api/v1/internal/users/#{user.id}/export/activity", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/internal/users/:user_id/export/audit_logs' do
    before do
      create_list(:audit_log, 3, user: user, account: account)
    end

    context 'with internal authentication' do
      it 'returns user audit logs' do
        get "/api/v1/internal/users/#{user.id}/export/audit_logs", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to be_an(Array)
        expect(response_data['data']['data'].length).to eq(3)
      end

      it 'includes audit log details' do
        get "/api/v1/internal/users/#{user.id}/export/audit_logs", headers: internal_headers, as: :json

        response_data = json_response
        first_log = response_data['data']['data'].first

        expect(first_log).to include('id', 'action', 'resource_type')
      end
    end
  end

  describe 'GET /api/v1/internal/users/:user_id/export/consents' do
    context 'with internal authentication' do
      it 'returns user consents' do
        get "/api/v1/internal/users/#{user.id}/export/consents", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/payments' do
    before do
      create_list(:payment, 3, account: account)
    end

    context 'with internal authentication' do
      it 'returns account payments' do
        get "/api/v1/internal/accounts/#{account.id}/export/payments", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to be_an(Array)
        expect(response_data['data']['data'].length).to eq(3)
      end

      it 'includes payment details' do
        get "/api/v1/internal/accounts/#{account.id}/export/payments", headers: internal_headers, as: :json

        response_data = json_response
        first_payment = response_data['data']['data'].first

        expect(first_payment).to include('id', 'amount', 'currency', 'status')
      end
    end

    context 'when account does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/accounts/nonexistent-id/export/payments', headers: internal_headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/invoices' do
    before do
      create_list(:invoice, 3, account: account)
    end

    context 'with internal authentication' do
      it 'returns account invoices' do
        get "/api/v1/internal/accounts/#{account.id}/export/invoices", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to be_an(Array)
        expect(response_data['data']['data'].length).to eq(3)
      end

      it 'includes invoice details' do
        get "/api/v1/internal/accounts/#{account.id}/export/invoices", headers: internal_headers, as: :json

        response_data = json_response
        first_invoice = response_data['data']['data'].first

        expect(first_invoice).to include('id', 'invoice_number', 'status')
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/subscriptions' do
    context 'with internal authentication' do
      it 'returns account subscriptions' do
        get "/api/v1/internal/accounts/#{account.id}/export/subscriptions", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/internal/accounts/:account_id/export/files' do
    context 'with internal authentication' do
      it 'returns account files' do
        get "/api/v1/internal/accounts/#{account.id}/export/files", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to be_an(Array)
      end
    end
  end
end
