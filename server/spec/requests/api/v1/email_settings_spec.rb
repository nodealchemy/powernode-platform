# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::EmailSettings', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: ['admin.settings.email']) }
  let(:regular_user) { create(:user, account: account) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:user_headers) { auth_headers_for(regular_user) }

  describe 'GET /api/v1/email_settings' do
    context 'with admin permission' do
      before do
        allow(AdminSetting).to receive(:get).and_call_original
        allow(AdminSetting).to receive(:get).with('email_provider', anything).and_return('smtp')
        allow(AdminSetting).to receive(:get).with('smtp_host', anything).and_return('smtp.example.com')
        allow(AdminSetting).to receive(:get).with('smtp_port', anything).and_return(587)
      end

      it 'returns email settings' do
        get '/api/v1/email_settings', headers: admin_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('provider')
        expect(response_data['data']).to have_key('smtp_host')
        expect(response_data['data']).to have_key('smtp_port')
      end

      it 'includes provider-specific settings' do
        get '/api/v1/email_settings', headers: admin_headers, as: :json

        response_data = json_response

        expect(response_data['data']).to have_key('sendgrid_api_key')
        expect(response_data['data']).to have_key('ses_region')
        expect(response_data['data']).to have_key('mailgun_domain')
      end

      it 'includes email behavior settings' do
        get '/api/v1/email_settings', headers: admin_headers, as: :json

        response_data = json_response

        expect(response_data['data']).to have_key('email_verification_expiry_hours')
        expect(response_data['data']).to have_key('password_reset_expiry_hours')
        expect(response_data['data']).to have_key('max_email_retries')
      end
    end

    context 'without admin permission' do
      it 'returns forbidden error' do
        get '/api/v1/email_settings', headers: user_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/email_settings', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /api/v1/email_settings' do
    let(:update_params) do
      {
        email_settings: {
          email_provider: 'smtp',
          smtp_host: 'new-smtp.example.com',
          smtp_port: 465,
          smtp_from_address: 'noreply@example.com'
        }
      }
    end

    context 'with admin permission' do
      before do
        allow(AdminSetting).to receive(:set).and_return(true)
        allow(WorkerJobService).to receive(:enqueue_refresh_email_settings).and_return(true)
      end

      it 'updates email settings' do
        put '/api/v1/email_settings', params: update_params, headers: admin_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('updated successfully')
      end

      it 'handles worker service errors gracefully' do
        allow(WorkerJobService).to receive(:enqueue_refresh_email_settings)
          .and_raise(WorkerJobService::WorkerServiceError.new('Service unavailable'))

        put '/api/v1/email_settings', params: update_params, headers: admin_headers, as: :json

        # Should still succeed even if worker notification fails
        expect_success_response
      end
    end

    context 'without admin permission' do
      it 'returns forbidden error' do
        put '/api/v1/email_settings', params: update_params, headers: user_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/email_settings/test' do
    context 'with admin permission' do
      before do
        allow(WorkerJobService).to receive(:enqueue_test_email).and_return(true)
      end

      it 'sends test email' do
        post '/api/v1/email_settings/test',
             params: { email: 'test@example.com' },
             headers: admin_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('Test email queued')
      end

      it 'requires email address' do
        post '/api/v1/email_settings/test',
             params: {},
             headers: admin_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'handles worker service errors' do
        allow(WorkerJobService).to receive(:enqueue_test_email)
          .and_raise(WorkerJobService::WorkerServiceError.new('Service unavailable'))

        post '/api/v1/email_settings/test',
             params: { email: 'test@example.com' },
             headers: admin_headers,
             as: :json

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'without admin permission' do
      it 'returns forbidden error' do
        post '/api/v1/email_settings/test',
             params: { email: 'test@example.com' },
             headers: user_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
