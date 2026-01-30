# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Auth', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, password: TestUsers::PASSWORD) }
  let(:unverified_user) { create(:user, :unverified, account: account, password: TestUsers::PASSWORD) }

  before(:each) do
    # Clear rate limiting cache to prevent interference between tests
    Rails.cache.clear
  end

  describe 'POST /api/v1/auth/register' do
    let(:valid_params) do
      {
        email: 'newuser@example.com',
        password: TestUsers::PASSWORD,
        firstName: 'John',
        lastName: 'Doe',
        accountName: 'New Company'
      }
    end

    context 'with valid parameters' do
      it 'creates a new user and account' do
        expect {
          post '/api/v1/auth/register', params: valid_params, as: :json
        }.to change(User, :count).by(1).and change(Account, :count).by(1)
      end

      it 'returns success with user data and tokens' do
        post '/api/v1/auth/register', params: valid_params, as: :json

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['success']).to be true
        expect(response_data['data']['user']).to include(
          'email' => 'newuser@example.com',
          'name' => 'John Doe',
          'roles' => [ 'owner' ]
        )
        expect(response_data['data']).to have_key('access_token')
        expect(response_data['data']).to have_key('refresh_token')
      end

      it 'assigns owner role to first user' do
        post '/api/v1/auth/register', params: valid_params, as: :json

        new_user = User.find_by(email: 'newuser@example.com')
        expect(new_user.has_role?('owner')).to be true
      end
    end

    context 'with invalid parameters' do
      it 'returns error for missing email' do
        invalid_params = valid_params.merge(email: nil)

        post '/api/v1/auth/register', params: invalid_params, as: :json

        expect_error_response("Email can't be blank", 422)
      end

      it 'returns error for duplicate email' do
        create(:user, email: 'newuser@example.com')

        post '/api/v1/auth/register', params: valid_params, as: :json

        expect_error_response('Email has already been taken', 422)
      end

      it 'returns error for weak password' do
        weak_params = valid_params.merge(password: '123')

        post '/api/v1/auth/register', params: weak_params, as: :json

        # The API returns the first validation error (length requirement is checked first)
        expect_error_response('Password Password must be at least 12 characters long', 422)
      end
    end
  end

  describe 'POST /api/v1/auth/login' do
    let(:valid_params) do
      {
        email: user.email,
        password: TestUsers::PASSWORD
      }
    end

    context 'with valid credentials' do
      it 'returns success with user data and tokens' do
        post '/api/v1/auth/login', params: valid_params, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['user']).to include(
          'id' => user.id,
          'email' => user.email
        )
        expect(response_data['data']).to have_key('access_token')
        expect(response_data['data']).to have_key('refresh_token')
      end

      it 'updates last_login_at' do
        expect {
          post '/api/v1/auth/login', params: valid_params, as: :json
        }.to change { user.reload.last_login_at }
      end

      it 'creates audit log entry' do
        # Multiple audit logs may be created: login, user.updated (from Auditable), etc.
        expect {
          post '/api/v1/auth/login', params: valid_params, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        # Find the specific login audit log
        audit_log = AuditLog.find_by(action: 'login')
        expect(audit_log).to be_present
        expect(audit_log.user).to eq(user)
      end
    end

    context 'with invalid credentials' do
      it 'returns error for wrong email' do
        invalid_params = valid_params.merge(email: 'wrong@example.com')

        post '/api/v1/auth/login', params: invalid_params, as: :json

        expect_error_response('Invalid email or password', 401)
      end

      it 'returns error for wrong password' do
        invalid_params = valid_params.merge(password: 'WrongStr0ngP@ssw0rd9!')

        post '/api/v1/auth/login', params: invalid_params, as: :json

        expect_error_response('Invalid email or password', 401)
      end

      it 'returns error for inactive user' do
        user.update(status: 'inactive')

        post '/api/v1/auth/login', params: valid_params, as: :json

        expect_error_response('Account is inactive', 401)
      end

      it 'returns error for suspended user' do
        user.update(status: 'suspended')

        post '/api/v1/auth/login', params: valid_params, as: :json

        expect_error_response('Account is suspended', 401)
      end
    end

    context 'with unverified email' do
      let(:valid_params) do
        {
          email: unverified_user.email,
          password: TestUsers::PASSWORD
        }
      end

      it 'allows login but includes verification warning' do
        post '/api/v1/auth/login', params: valid_params, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['user']['email_verified']).to be false
        expect(response_data['data']['warning']).to include('email verification')
      end
    end
  end

  describe 'POST /api/v1/auth/refresh' do
    let(:tokens) { Security::JwtService.generate_user_tokens(user) }
    let(:refresh_token) { tokens[:refresh_token] }

    context 'with valid refresh token' do
      it 'returns new access and refresh tokens' do
        post '/api/v1/auth/refresh', params: { refresh_token: refresh_token }, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('access_token')
        expect(response_data['data']).to have_key('refresh_token')

        # New tokens are generated (both access and refresh)
        expect(response_data['data']['access_token']).not_to eq(refresh_token)
        expect(response_data['data']['refresh_token']).to be_present
      end
    end

    context 'with invalid refresh token' do
      it 'returns error for malformed token' do
        post '/api/v1/auth/refresh', params: { refresh_token: 'invalid_token' }, as: :json

        # Fixed: Now properly returns 401 with proper error handling via ApiResponse concern
        expect(response).to have_http_status(401)
        expect(json_response).to include(
          'success' => false,
          'error' => 'Invalid or expired refresh token'
        )
      end

      it 'returns error for expired token' do
        # Create an expired refresh token by manually encoding with past expiration
        expired_payload = {
          sub: user.id,
          account_id: user.account_id,
          type: 'refresh',
          version: 2
        }
        expired_token = JWT.encode(
          expired_payload.merge(exp: 1.day.ago.to_i, iat: 2.days.ago.to_i, jti: SecureRandom.hex(16)),
          Rails.application.config.jwt_secret_key,
          'HS256'
        )

        post '/api/v1/auth/refresh', params: { refresh_token: expired_token }, as: :json

        expect(response).to have_http_status(401)
        expect(json_response).to include(
          'success' => false,
          'error' => 'Invalid or expired refresh token'
        )
      end

      it 'returns error for access token used as refresh token' do
        # Create an access token and try to use it as refresh token
        access_token = tokens[:access_token]

        post '/api/v1/auth/refresh', params: { refresh_token: access_token }, as: :json

        # Fixed: Now properly returns 401 with proper error handling via ApiResponse concern
        expect(response).to have_http_status(401)
        expect(json_response).to include(
          'success' => false,
          'error' => 'Invalid or expired refresh token'
        )
      end
    end
  end

  describe 'POST /api/v1/auth/logout' do
    let(:headers) { auth_headers_for(user) }

    it 'successfully logs out authenticated user' do
      post '/api/v1/auth/logout', headers: headers, as: :json

      expect_success_response

      response_data = json_response
      expect(response_data['data']['message']).to eq('Successfully logged out')
    end

    it 'creates audit log entry' do
      expect {
        post '/api/v1/auth/logout', headers: headers, as: :json
      }.to change(AuditLog, :count).by_at_least(1)

      # Find the specific logout audit log
      audit_log = AuditLog.find_by(action: 'logout')
      expect(audit_log).to be_present
      expect(audit_log.user).to eq(user)
    end

    it 'returns error without authentication' do
      post '/api/v1/auth/logout', as: :json

      expect_error_response('Access token required', 401)
    end
  end

  describe 'GET /api/v1/auth/me' do
    let(:headers) { auth_headers_for(user) }

    it 'returns current user data' do
      get '/api/v1/auth/me', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['user']).to include(
        'id' => user.id,
        'email' => user.email,
        'name' => user.name
      )
    end

    it 'returns error without authentication' do
      get '/api/v1/auth/me', as: :json

      expect_error_response('Access token required', 401)
    end

    it 'returns error with invalid token' do
      invalid_headers = { 'Authorization' => 'Bearer invalid_token' }

      get '/api/v1/auth/me', headers: invalid_headers, as: :json

      expect_error_response('Invalid access token', 401)
    end
  end

  describe 'POST /api/v1/auth/forgot-password' do
    it 'sends password reset email for valid email' do
      # Mock the worker service to avoid actual job execution in tests
      expect(WorkerJobService).to receive(:enqueue_password_reset_email).with(user.id)

      post '/api/v1/auth/forgot-password', params: { email: user.email }, as: :json

      expect_success_response
      expect(json_response['data']['message']).to include('password reset instructions')
    end

    it 'returns success even for non-existent email (security)' do
      post '/api/v1/auth/forgot-password', params: { email: 'nonexistent@example.com' }, as: :json

      expect_success_response
      expect(json_response['data']['message']).to include('password reset instructions')
    end

    it 'returns error for missing email' do
      post '/api/v1/auth/forgot-password', params: {}, as: :json

      expect_error_response('Email is required', 400)
    end
  end

  describe 'POST /api/v1/auth/reset-password' do
    let(:reset_token) { user.generate_reset_token! }

    let(:valid_params) do
      {
        token: reset_token,
        password: TestUsers::PASSWORD
      }
    end

    it 'successfully resets password with valid token' do
      old_password_digest = user.password_digest

      post '/api/v1/auth/reset-password', params: valid_params, as: :json

      expect_success_response

      # Verify password was changed by checking digest changed
      user.reload
      expect(user.password_digest).not_to eq(old_password_digest)
      expect(user.reset_token_digest).to be_nil
      expect(user.reset_token_expires_at).to be_nil
    end

    it 'returns error for invalid token' do
      invalid_params = valid_params.merge(token: 'invalid_token')

      post '/api/v1/auth/reset-password', params: invalid_params, as: :json

      expect_error_response('Invalid reset token', 401)
    end

    it 'returns error for expired token' do
      # Create an expired reset token
      expired_token = user.generate_reset_token!

      # Force the token to be expired
      user.update!(reset_token_expires_at: 1.hour.ago)

      expired_params = valid_params.merge(token: expired_token)

      post '/api/v1/auth/reset-password', params: expired_params, as: :json

      # Note: Due to the current implementation, expired tokens return "Invalid reset token"
      # This still provides the same security - expired tokens are rejected
      expect_error_response('Invalid reset token', 401)
    end
  end

  describe 'rate limiting', :rate_limiting do
    # Rate limiting is implemented via Rack::Attack middleware which is intentionally
    # disabled in the test environment to prevent flaky tests and test isolation issues.
    # See config/initializers/rack_attack.rb for the full implementation.
    #
    # To test rate limiting manually:
    # 1. Start the server in development mode: rails s
    # 2. Enable rate limiting in system settings
    # 3. Use curl or similar to make repeated requests
    #
    # Rate limiting configuration:
    # - Login attempts per hour: 10 per IP
    # - Login attempts per email: 5 per hour
    # - Registration attempts: 5 per hour
    # - Password reset attempts: 3 per hour

    it 'limits login attempts per IP (verified via Rack::Attack middleware)' do
      # This test documents the expected behavior but cannot be executed
      # because Rack::Attack middleware is disabled in test environment
      skip 'Rate limiting via Rack::Attack is disabled in test environment - see config/initializers/rack_attack.rb line 77'

      # Expected behavior when rate limiting is enabled:
      # After 10 failed login attempts from the same IP within an hour,
      # subsequent requests should receive 429 Too Many Requests response
      10.times do
        post '/api/v1/auth/login', params: { email: user.email, password: 'wrong' }, as: :json
      end

      post '/api/v1/auth/login', params: { email: user.email, password: 'wrong' }, as: :json

      expect(response).to have_http_status(429)
      expect(json_response['error']).to eq('Too many requests')
    end
  end
end
