# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Auth::EmailVerifications', type: :request do
  let(:account) { create(:account) }
  let(:unverified_user) do
    create(:user,
           account: account,
           email_verified_at: nil,
           email_verification_token: 'valid-verification-token',
           email_verification_token_expires_at: 24.hours.from_now)
  end
  let(:verified_user) { create(:user, account: account, email_verified_at: Time.current) }
  let(:headers) { auth_headers_for(unverified_user) }

  describe 'POST /api/v1/auth/verify-email' do
    context 'with valid token' do
      before do
        allow_any_instance_of(User).to receive(:email_verification_expired?).and_return(false)
      end

      it 'verifies email successfully' do
        post '/api/v1/auth/verify-email',
             params: { token: unverified_user.email_verification_token },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('verified successfully')
        expect(response_data['data']['user']['email_verified']).to be true
      end

      it 'creates audit log entry' do
        expect {
          post '/api/v1/auth/verify-email',
               params: { token: unverified_user.email_verification_token },
               as: :json
        }.to change(AuditLog, :count).by(1)
      end
    end

    context 'with invalid token' do
      it 'returns not found error' do
        post '/api/v1/auth/verify-email',
             params: { token: 'invalid-token' },
             as: :json

        expect_error_response('Invalid verification token', 404)
      end
    end

    context 'with expired token' do
      before do
        unverified_user.update!(email_verification_token_expires_at: 1.hour.ago)
      end

      it 'returns error for expired token' do
        allow_any_instance_of(User).to receive(:email_verification_expired?).and_return(true)

        post '/api/v1/auth/verify-email',
             params: { token: unverified_user.email_verification_token },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when email already verified' do
      it 'returns already verified message' do
        verified_user.update!(email_verification_token: 'another-token')

        allow_any_instance_of(User).to receive(:email_verification_expired?).and_return(false)

        post '/api/v1/auth/verify-email',
             params: { token: verified_user.email_verification_token },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('already verified')
      end
    end

    context 'without token' do
      it 'returns bad request error' do
        post '/api/v1/auth/verify-email', params: {}, as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'POST /api/v1/auth/resend-verification' do
    context 'with authenticated unverified user' do
      before do
        allow(WorkerJobService).to receive(:enqueue_notification_email).and_return(true)
        allow_any_instance_of(User).to receive(:generate_email_verification_token).and_return(true)
      end

      it 'resends verification email' do
        post '/api/v1/auth/resend-verification', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('Verification email sent')
      end
    end

    context 'with verified user' do
      let(:verified_headers) { auth_headers_for(verified_user) }

      it 'returns error for already verified' do
        post '/api/v1/auth/resend-verification', headers: verified_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with recent verification request' do
      before do
        unverified_user.update!(email_verification_sent_at: 1.minute.ago)
      end

      it 'rate limits requests' do
        post '/api/v1/auth/resend-verification', headers: headers, as: :json

        expect(response).to have_http_status(:too_many_requests)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/auth/resend-verification', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
