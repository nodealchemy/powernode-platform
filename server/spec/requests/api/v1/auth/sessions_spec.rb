# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Auth::Sessions', type: :request do
  let(:account) { create(:account) }
  let(:password) { TestUsers::PASSWORD }
  let(:user) { create(:user, account: account, password: password, email_verified_at: Time.current) }

  describe 'POST /api/v1/auth/login' do
    context 'with valid credentials' do
      it 'returns user data and tokens' do
        post '/api/v1/auth/login',
             params: { email: user.email, password: password },
             as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['user']).to be_present
        expect(response_data['data']['account']).to be_present
        expect(response_data['data']['access_token']).to be_present
        expect(response_data['data']['expires_at']).to be_present
        # Refresh token is now in HttpOnly cookie, not in response body
        expect(response.cookies['refresh_token']).to be_present
      end

      it 'creates audit log entry' do
        expect {
          post '/api/v1/auth/login',
               params: { email: user.email, password: password },
               as: :json
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('login')
        expect(audit_log.user_id).to eq(user.id)
      end

      it 'records login timestamp' do
        expect {
          post '/api/v1/auth/login',
               params: { email: user.email, password: password },
               as: :json
        }.to change { user.reload.last_login_at }
      end
    end

    context 'with nested session parameters' do
      it 'accepts session[email] and session[password]' do
        post '/api/v1/auth/login',
             params: { session: { email: user.email, password: password } },
             as: :json

        expect_success_response
      end
    end

    context 'with case-insensitive email' do
      it 'finds user by downcased email' do
        post '/api/v1/auth/login',
             params: { email: user.email.upcase, password: password },
             as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['user']['email']).to eq(user.email)
      end
    end

    context 'with unverified email' do
      let(:unverified_user) { create(:user, account: account, password: password, email_verified_at: nil) }

      it 'allows login but includes warning' do
        post '/api/v1/auth/login',
             params: { email: unverified_user.email, password: password },
             as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['warning']).to include('complete email verification')
      end
    end

    context 'with two-factor authentication enabled' do
      let(:two_fa_user) { create(:user, account: account, password: password, two_factor_enabled: true) }

      before do
        allow_any_instance_of(User).to receive(:two_factor_enabled?).and_return(true)
        allow(Security::JwtService).to receive(:generate_2fa_token).and_return(
          { token: 'two-fa-token', expires_at: 5.minutes.from_now.to_i }
        )
      end

      it 'returns 2FA requirement instead of full tokens' do
        post '/api/v1/auth/login',
             params: { email: two_fa_user.email, password: password },
             as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['requires_2fa']).to be true
        expect(response_data['data']['verification_token']).to be_present
        expect(response_data['data']['access_token']).to be_nil
      end

      it 'creates partial audit log for 2FA requirement' do
        expect {
          post '/api/v1/auth/login',
               params: { email: two_fa_user.email, password: password },
               as: :json
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('login_2fa_required')
      end
    end

    context 'with invalid password' do
      it 'returns unauthorized error' do
        post '/api/v1/auth/login',
             params: { email: user.email, password: 'WrongPassword' },
             as: :json

        expect_error_response('Invalid email or password', 401)
      end
    end

    context 'with non-existent email' do
      it 'returns unauthorized error' do
        post '/api/v1/auth/login',
             params: { email: 'nonexistent@example.com', password: password },
             as: :json

        expect_error_response('Invalid email or password', 401)
      end
    end

    context 'with inactive user' do
      let(:inactive_user) { create(:user, account: account, password: password, status: 'inactive') }

      it 'returns unauthorized error' do
        post '/api/v1/auth/login',
             params: { email: inactive_user.email, password: password },
             as: :json

        expect_error_response('Account is inactive', 401)
      end
    end

    context 'with suspended user' do
      let(:suspended_user) { create(:user, account: account, password: password, status: 'suspended') }

      it 'returns unauthorized error' do
        post '/api/v1/auth/login',
             params: { email: suspended_user.email, password: password },
             as: :json

        expect_error_response('Account is suspended', 401)
      end
    end

    context 'with locked account' do
      let(:locked_user) { create(:user, account: account, password: password) }

      before do
        allow_any_instance_of(User).to receive(:locked?).and_return(true)
      end

      it 'returns locked error before authentication' do
        post '/api/v1/auth/login',
             params: { email: locked_user.email, password: password },
             as: :json

        expect_error_response('Your account is temporarily locked due to multiple failed login attempts. Please try again later.', 401)
      end
    end

    context 'with inactive account' do
      let(:inactive_account) { create(:account, status: 'suspended') }
      let(:user_inactive_account) { create(:user, account: inactive_account, password: password) }

      it 'returns unauthorized error' do
        post '/api/v1/auth/login',
             params: { email: user_inactive_account.email, password: password },
             as: :json

        expect_error_response('Account access denied', 401)
      end
    end
  end

  describe 'POST /api/v1/auth/refresh' do
    let(:refresh_token) { 'valid-refresh-token' }

    context 'with valid refresh token' do
      before do
        allow(Security::JwtService).to receive(:refresh_access_token).and_return(
          {
            access_token: 'new-access-token',
            refresh_token: 'new-refresh-token',
            expires_at: 1.hour.from_now.to_i
          }
        )
      end

      it 'returns new tokens' do
        post '/api/v1/auth/refresh',
             params: { refresh_token: refresh_token },
             as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['access_token']).to eq('new-access-token')
        expect(response_data['data']['expires_at']).to be_present
        # Refresh token is now in HttpOnly cookie, not in response body
        expect(response.cookies['refresh_token']).to eq('new-refresh-token')
      end
    end

    context 'with invalid refresh token' do
      before do
        allow(Security::JwtService).to receive(:refresh_access_token).and_raise(
          StandardError.new('Invalid token')
        )
      end

      it 'returns unauthorized error' do
        post '/api/v1/auth/refresh',
             params: { refresh_token: 'invalid-token' },
             as: :json

        expect_error_response('Invalid or expired refresh token', 401)
      end
    end

    context 'when permissions changed' do
      before do
        allow(Security::JwtService).to receive(:refresh_access_token).and_raise(
          StandardError.new('Permissions changed - re-login required')
        )
      end

      it 'returns re-login required error' do
        post '/api/v1/auth/refresh',
             params: { refresh_token: refresh_token },
             as: :json

        expect_error_response('Authentication required - please log in again', 401)
      end
    end

    context 'without refresh token' do
      it 'returns bad request error' do
        post '/api/v1/auth/refresh',
             params: {},
             as: :json

        expect_error_response('Refresh token required', 400)
      end
    end
  end

  describe 'POST /api/v1/auth/logout' do
    let(:headers) { auth_headers_for(user) }

    before do
      allow(Security::JwtService).to receive(:blacklist_token).and_return(true)
    end

    context 'with valid authentication' do
      it 'logs out successfully' do
        post '/api/v1/auth/logout',
               headers: headers,
               as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['message']).to include('Successfully logged out')
      end

      it 'blacklists access token' do
        post '/api/v1/auth/logout',
               headers: headers,
               as: :json

        expect(Security::JwtService).to have_received(:blacklist_token).with(
          anything,
          hash_including(reason: 'logout', user_id: user.id)
        )
      end

      it 'creates audit log entry' do
        expect {
          post '/api/v1/auth/logout',
                 headers: headers,
                 as: :json
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('logout')
        expect(audit_log.user_id).to eq(user.id)
      end
    end

    context 'with refresh token provided' do
      it 'blacklists both access and refresh tokens' do
        post '/api/v1/auth/logout',
               params: { refresh_token: 'some-refresh-token' },
               headers: headers,
               as: :json

        expect(Security::JwtService).to have_received(:blacklist_token).twice
      end
    end

    context 'when blacklisting fails' do
      before do
        allow(Security::JwtService).to receive(:blacklist_token).and_raise(StandardError.new('Redis down'))
      end

      it 'still logs out successfully' do
        post '/api/v1/auth/logout',
               headers: headers,
               as: :json

        expect_success_response
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/auth/logout',
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/auth/me' do
    let(:headers) { auth_headers_for(user) }

    context 'with valid authentication' do
      it 'returns current user data' do
        get '/api/v1/auth/me',
            headers: headers,
            as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['user']).to be_present
        expect(response_data['data']['user']['id']).to eq(user.id)
        expect(response_data['data']['user']['email']).to eq(user.email)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/auth/me',
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/auth/verify-2fa' do
    let(:verification_token) { 'verification-token' }
    let(:two_factor_code) { '123456' }

    context 'with valid 2FA code' do
      before do
        allow(Security::JwtService).to receive(:verify_2fa_token).and_return(
          {
            access_token: 'access-token',
            refresh_token: 'refresh-token',
            expires_at: 1.hour.from_now.to_i
          }
        )
        allow(Security::JwtService).to receive(:decode).and_return({ sub: user.id })
      end

      it 'returns full authentication tokens' do
        post '/api/v1/auth/verify-2fa',
             params: { verification_token: verification_token, code: two_factor_code },
             as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['user']).to be_present
        expect(response_data['data']['access_token']).to be_present
        # Refresh token is now in HttpOnly cookie, not in response body
        expect(response.cookies['refresh_token']).to be_present
      end

      it 'creates audit log entry' do
        expect {
          post '/api/v1/auth/verify-2fa',
               params: { verification_token: verification_token, code: two_factor_code },
               as: :json
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('login')
        expect(audit_log.metadata['login_method']).to eq('password_2fa')
      end
    end

    context 'with invalid 2FA code' do
      before do
        allow(Security::JwtService).to receive(:verify_2fa_token).and_raise(
          StandardError.new('Invalid code')
        )
      end

      it 'returns unauthorized error' do
        post '/api/v1/auth/verify-2fa',
             params: { verification_token: verification_token, code: 'wrong-code' },
             as: :json

        expect_error_response('Authentication verification failed', 401)
      end
    end

    context 'without verification token' do
      it 'returns bad request error' do
        post '/api/v1/auth/verify-2fa',
             params: { code: two_factor_code },
             as: :json

        expect_error_response('Verification token is required', 400)
      end
    end

    context 'without 2FA code' do
      it 'returns bad request error' do
        post '/api/v1/auth/verify-2fa',
             params: { verification_token: verification_token },
             as: :json

        expect_error_response('Two-factor authentication code is required', 400)
      end
    end
  end
end
