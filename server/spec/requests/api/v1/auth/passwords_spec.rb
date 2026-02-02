# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Auth::Passwords', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, email_verified_at: Time.current) }
  let(:headers) { auth_headers_for(user) }

  before do
    allow(WorkerJobService).to receive(:enqueue_password_reset_email).and_return(true)
  end

  describe 'POST /api/v1/auth/forgot-password' do
    context 'with valid email for active verified user' do
      it 'returns success message without revealing user existence' do
        post '/api/v1/auth/forgot-password',
             params: { email: user.email },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('password reset instructions')
        expect(WorkerJobService).to have_received(:enqueue_password_reset_email).with(user.id)
      end

      it 'generates reset token for user' do
        expect {
          post '/api/v1/auth/forgot-password',
               params: { email: user.email },
               as: :json
        }.to change { user.reload.reset_token_digest }.from(nil)
      end
    end

    context 'with non-existent email' do
      it 'returns success message to prevent enumeration' do
        post '/api/v1/auth/forgot-password',
             params: { email: 'nonexistent@example.com' },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('password reset instructions')
        expect(WorkerJobService).not_to have_received(:enqueue_password_reset_email)
      end
    end

    context 'with inactive user' do
      let(:inactive_user) { create(:user, account: account, status: 'inactive', email_verified_at: Time.current) }

      it 'returns success message without sending email' do
        post '/api/v1/auth/forgot-password',
             params: { email: inactive_user.email },
             as: :json

        expect_success_response
        expect(WorkerJobService).not_to have_received(:enqueue_password_reset_email)
      end
    end

    context 'with unverified email' do
      let(:unverified_user) { create(:user, account: account, email_verified_at: nil) }

      it 'returns success message without sending email' do
        post '/api/v1/auth/forgot-password',
             params: { email: unverified_user.email },
             as: :json

        expect_success_response
        expect(WorkerJobService).not_to have_received(:enqueue_password_reset_email)
      end
    end

    context 'without email parameter' do
      it 'returns bad request error' do
        post '/api/v1/auth/forgot-password',
             params: {},
             as: :json

        expect_error_response('Email is required', 400)
      end
    end

    context 'with case-insensitive email' do
      it 'finds user by downcased email' do
        post '/api/v1/auth/forgot-password',
             params: { email: user.email.upcase },
             as: :json

        expect_success_response
        expect(WorkerJobService).to have_received(:enqueue_password_reset_email).with(user.id)
      end
    end
  end

  describe 'POST /api/v1/auth/reset-password' do
    let(:reset_token) { 'valid-reset-token' }

    before do
      user.generate_reset_token!
      # Store the actual token for testing
      @stored_token = user.instance_variable_get(:@reset_token_plaintext) || reset_token
      # Mock BCrypt comparison
      bcrypt_double = double('BCrypt::Password')
      allow(bcrypt_double).to receive(:==) { |token| token == @stored_token }
      allow(BCrypt::Password).to receive(:new).and_return(bcrypt_double)
    end

    context 'with valid reset token and password' do
      it 'resets password successfully' do
        allow_any_instance_of(User).to receive(:reset_password!).and_return(true)

        post '/api/v1/auth/reset-password',
             params: { token: @stored_token, password: TestUsers::PASSWORD },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('reset successfully')
      end
    end

    context 'with invalid reset token' do
      it 'returns unauthorized error' do
        post '/api/v1/auth/reset-password',
             params: { token: 'invalid-token', password: TestUsers::PASSWORD },
             as: :json

        expect_error_response('Invalid reset token', 401)
      end
    end

    context 'without reset token' do
      it 'returns bad request error' do
        post '/api/v1/auth/reset-password',
             params: { password: TestUsers::PASSWORD },
             as: :json

        expect_error_response('Reset token is required', 400)
      end
    end

    context 'without password' do
      it 'returns bad request error' do
        post '/api/v1/auth/reset-password',
             params: { token: @stored_token },
             as: :json

        expect_error_response('New password is required', 400)
      end
    end

    context 'with weak password' do
      it 'returns validation error' do
        allow_any_instance_of(User).to receive(:reset_password!).and_return(false)
        allow_any_instance_of(User).to receive(:errors).and_return(
          double(full_messages: [ 'Password is too weak' ])
        )

        post '/api/v1/auth/reset-password',
             params: { token: @stored_token, password: 'weak' },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PUT /api/v1/auth/change-password' do
    context 'with valid current password' do
      it 'changes password successfully' do
        put '/api/v1/auth/change-password',
             params: {
               password: {
                 current_password: TestUsers::PASSWORD,
                 new_password: 'NewStr0ngP@ssw0rd!#',
                 password_confirmation: 'NewStr0ngP@ssw0rd!#'
               }
             },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('changed successfully')
      end
    end

    context 'with incorrect current password' do
      it 'returns unauthorized error' do
        put '/api/v1/auth/change-password',
             params: {
               password: {
                 current_password: 'WrongPassword',
                 new_password: 'NewStr0ngP@ssw0rd!#',
                 password_confirmation: 'NewStr0ngP@ssw0rd!#'
               }
             },
             headers: headers,
             as: :json

        expect_error_response('Current password is incorrect', 401)
      end
    end

    context 'with mismatched password confirmation' do
      it 'returns validation error' do
        put '/api/v1/auth/change-password',
             params: {
               password: {
                 current_password: TestUsers::PASSWORD,
                 new_password: 'NewStr0ngP@ssw0rd!#',
                 password_confirmation: 'DifferentPassword123!'
               }
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        put '/api/v1/auth/change-password',
             params: {
               password: {
                 current_password: TestUsers::PASSWORD,
                 new_password: 'NewStr0ngP@ssw0rd!#',
                 password_confirmation: 'NewStr0ngP@ssw0rd!#'
               }
             },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
