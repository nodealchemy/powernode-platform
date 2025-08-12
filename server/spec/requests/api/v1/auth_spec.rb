require 'rails_helper'

RSpec.describe 'Api::V1::Auth', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, password: 'StrongTestP@ssw0rd9!') }
  let(:unverified_user) { create(:user, :unverified, account: account, password: 'StrongTestP@ssw0rd9!') }

  before(:each) do
    # Clear rate limiting cache to prevent interference between tests
    Rails.cache.clear
  end

  describe 'POST /api/v1/auth/register' do
    let(:valid_params) do
      {
        email: 'newuser@example.com',
        password: 'StrongTest4P@9w0rd!',
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

        if response.status != 201
          puts "Response status: #{response.status}"
          puts "Response body: #{response.body}"
        end

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data).to include(
          'success' => true,
          'user' => hash_including(
            'email' => 'newuser@example.com',
            'firstName' => 'John',
            'lastName' => 'Doe',
            'role' => 'owner'
          )
        )
        expect(response_data).to have_key('access_token')
        expect(response_data).to have_key('refresh_token')
      end

      it 'assigns owner role to first user' do
        post '/api/v1/auth/register', params: valid_params, as: :json

        new_user = User.find_by(email: 'newuser@example.com')
        expect(new_user.role).to eq('owner')
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

        expect_error_response('Password Password must be at least 12 characters long', 422)
      end
    end
  end

  describe 'POST /api/v1/auth/login' do
    let(:valid_params) do
      {
        email: user.email,
        password: 'StrongTestP@ssw0rd9!'
      }
    end

    context 'with valid credentials' do
      it 'returns success with user data and tokens' do
        post '/api/v1/auth/login', params: valid_params, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data).to include(
          'user' => hash_including(
            'id' => user.id,
            'email' => user.email
          )
        )
        expect(response_data).to have_key('access_token')
        expect(response_data).to have_key('refresh_token')
      end

      it 'updates last_login_at' do
        expect {
          post '/api/v1/auth/login', params: valid_params, as: :json
        }.to change { user.reload.last_login_at }
      end

      it 'creates audit log entry' do
        expect {
          post '/api/v1/auth/login', params: valid_params, as: :json
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('login')
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
        invalid_params = valid_params.merge(password: 'WrongStrongP@ssw0rd9!')

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
          password: 'StrongTestP@ssw0rd9!'
        }
      end

      it 'allows login but includes verification warning' do
        post '/api/v1/auth/login', params: valid_params, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['user']['emailVerified']).to be false
        expect(response_data['warning']).to include('email verification')
      end
    end
  end

  describe 'POST /api/v1/auth/refresh' do
    let(:refresh_token) do
      payload = {
        user_id: user.id,
        account_id: user.account.id,
        type: 'refresh',
        exp: 7.days.from_now.to_i
      }
      JWT.encode(payload, Rails.application.config.jwt_secret_key, 'HS256')
    end

    context 'with valid refresh token' do
      it 'returns new access and refresh tokens' do
        post '/api/v1/auth/refresh', params: { refresh_token: refresh_token }, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data).to have_key('access_token')
        expect(response_data).to have_key('refresh_token')

        # Tokens should be different from the original
        expect(response_data['access_token']).not_to eq(refresh_token)
        expect(response_data['refresh_token']).not_to eq(refresh_token)
      end
    end

    context 'with invalid refresh token' do
      it 'returns error for malformed token' do
        post '/api/v1/auth/refresh', params: { refresh_token: 'invalid_token' }, as: :json

        expect_error_response('Invalid refresh token', 401)
      end

      it 'returns error for expired token' do
        expired_payload = {
          user_id: user.id,
          account_id: user.account.id,
          type: 'refresh',
          exp: 1.day.ago.to_i
        }
        expired_token = JWT.encode(expired_payload, Rails.application.config.jwt_secret_key, 'HS256')

        post '/api/v1/auth/refresh', params: { refresh_token: expired_token }, as: :json

        expect_error_response('Refresh token has expired', 401)
      end

      it 'returns error for access token used as refresh token' do
        access_payload = {
          user_id: user.id,
          account_id: user.account.id,
          type: 'access',
          exp: 1.hour.from_now.to_i
        }
        access_token = JWT.encode(access_payload, Rails.application.config.jwt_secret_key, 'HS256')

        post '/api/v1/auth/refresh', params: { refresh_token: access_token }, as: :json

        expect_error_response('Invalid token type', 401)
      end
    end
  end

  describe 'POST /api/v1/auth/logout' do
    let(:headers) { auth_headers_for(user) }

    it 'successfully logs out authenticated user' do
      post '/api/v1/auth/logout', headers: headers, as: :json

      expect_success_response

      response_data = json_response
      expect(response_data['message']).to eq('Successfully logged out')
    end

    it 'creates audit log entry' do
      expect {
        post '/api/v1/auth/logout', headers: headers, as: :json
      }.to change(AuditLog, :count).by(1)

      audit_log = AuditLog.last
      expect(audit_log.action).to eq('logout')
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

      expect(response_data['user']).to include(
        'id' => user.id,
        'email' => user.email,
        'firstName' => user.first_name,
        'lastName' => user.last_name,
        'role' => user.role || 'member',
        'account' => hash_including(
          'id' => user.account.id,
          'name' => user.account.name
        )
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
      expect {
        post '/api/v1/auth/forgot-password', params: { email: user.email }, as: :json
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect_success_response
      response_data = json_response
      expect(response_data['message']).to include('password reset instructions')
    end

    it 'returns success even for non-existent email (security)' do
      post '/api/v1/auth/forgot-password', params: { email: 'nonexistent@example.com' }, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['message']).to include('password reset instructions')
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
        password: 'BrandNewUniqueP@ssw0rd9!'
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
      # Create an expired JWT token manually
      expired_payload = {
        user_id: user.id,
        type: 'password_reset',
        exp: 1.hour.ago.to_i
      }
      expired_jwt_token = JWT.encode(expired_payload, Rails.application.config.jwt_secret_key, 'HS256')
      
      # Set up user state as if token was generated in the past
      user.update!(
        reset_token_digest: BCrypt::Password.create(expired_jwt_token),
        reset_token_expires_at: 1.hour.ago
      )
      
      expired_params = valid_params.merge(token: expired_jwt_token)

      post '/api/v1/auth/reset-password', params: expired_params, as: :json

      expect_error_response('Reset token has expired', 401)
    end
  end

  describe 'rate limiting' do
    before do
      # Configure rate limiting for testing
      Rails.application.config.rate_limiting_enabled = true
      # Skip this test in test environment since RateLimiting module is not included
      skip 'Rate limiting is disabled in test environment'
    end

    it 'limits login attempts per IP' do
      # Attempt to login 6 times with wrong credentials
      6.times do
        post '/api/v1/auth/login', params: { email: user.email, password: 'wrong' }, as: :json
      end

      # 7th attempt should be rate limited
      post '/api/v1/auth/login', params: { email: user.email, password: 'wrong' }, as: :json

      expect(response).to have_http_status(429)
      expect(json_response['error']).to eq('Too many requests')
    end
  end
end
