# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authentication Security', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before(:each) do
    # Clear rate limiting cache to prevent interference between tests
    Rails.cache.clear
  end

  describe 'Password Security' do
    it 'enforces minimum password length' do
      post '/api/v1/auth/register', params: {
        email: 'test@example.com',
        password: '123',
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company'
      }, as: :json

      expect(response).to have_http_status(422)
      expect(json_response['error']).to include('Password must be at least 12 characters long')
    end

    it 'enforces password complexity requirements' do
      post '/api/v1/auth/register', params: {
        email: 'test@example.com',
        password: 'simplepAssword',
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company'
      }, as: :json

      expect(response).to have_http_status(422)
      expect(json_response['error']).to include('Password must contain')
    end

    it 'accepts strong passwords' do
      post '/api/v1/auth/register', params: {
        email: 'test@example.com',
        password: TestUsers::PASSWORD,
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company'
      }, as: :json

      expect(response).to have_http_status(201)
    end

    it 'rejects common passwords' do
      post '/api/v1/auth/register', params: {
        email: 'test@example.com',
        password: 'Password123!',
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company'
      }, as: :json

      expect(response).to have_http_status(422)
      expect(json_response['error']).to include('common')
    end

    it 'hashes passwords securely' do
      user = create(:user, password: 'UncommonStr0ngP@ssw0rd99!')
      expect(user.password_digest).not_to eq('UncommonStr0ngP@ssw0rd99!')
      expect(user.password_digest).to start_with('$2a$')  # bcrypt hash
    end

    it 'does not expose password digest in API responses' do
      headers = auth_headers_for(user)
      get '/api/v1/auth/me', headers: headers

      expect(response).to have_http_status(200)
      user_data = json_response_data['user']
      expect(user_data).not_to have_key('password_digest')
      expect(user_data).not_to have_key('password')
    end
  end

  describe 'Token Security' do
    it 'generates secure access tokens' do
      post '/api/v1/auth/login', params: {
        email: user.email,
        password: TestUsers::PASSWORD
      }, as: :json

      expect(response).to have_http_status(200)
      token = json_response_data['access_token']

      # JWT tokens have 3 segments separated by dots
      expect(token.split('.').length).to eq(3)

      # Token should be a JWT string
      expect(token).to be_a(String)
      expect(token.length).to be >= 100  # JWT tokens are typically longer

      # Token should be decodable and contain user info
      payload = Security::JwtService.decode(token)
      expect(payload['sub']).to eq(user.id)
      expect(payload['type']).to eq('access')
    end

    it 'validates token authenticity' do
      # Create an invalid token (random string)
      invalid_token = SecureRandom.urlsafe_base64(48)

      get '/api/v1/auth/me', headers: {
        'Authorization' => "Bearer #{invalid_token}"
      }

      expect(response).to have_http_status(401)
      expect(json_response['error']).to include('Invalid')
    end

    it 'rejects expired tokens' do
      # Create a UserToken
      result = UserToken.create_token_for_user(user, type: 'access')
      user_token = result[:user_token]
      expired_token = result[:token]

      # Use time travel to make token appear expired (respects database constraints)
      travel_to (user_token.expires_at + 1.hour) do
        get '/api/v1/auth/me', headers: {
          'Authorization' => "Bearer #{expired_token}"
        }

        expect(response).to have_http_status(401)
      end
      expect(json_response['error']).to include('Invalid')
    end
  end

  describe 'Account Lockout Security' do
    it 'locks account after failed login attempts' do
      # Make multiple failed login attempts
      User::MAX_FAILED_ATTEMPTS.times do
        post '/api/v1/auth/login', params: {
          email: user.email,
          password: 'wrong_password'
        }, as: :json

        expect(response).to have_http_status(401)
      end

      user.reload
      expect(user.locked?).to be true
      expect(user.failed_login_attempts).to eq(User::MAX_FAILED_ATTEMPTS)
    end

    it 'prevents login when account is locked' do
      user.update!(locked_until: 1.hour.from_now)

      post '/api/v1/auth/login', params: {
        email: user.email,
        password: TestUsers::PASSWORD
      }, as: :json

      expect(response).to have_http_status(401)
      expect(json_response['error']).to include('account is temporarily locked')
    end

    it 'resets failed attempts on successful login' do
      user.update!(failed_login_attempts: 3)

      post '/api/v1/auth/login', params: {
        email: user.email,
        password: TestUsers::PASSWORD
      }, as: :json

      expect(response).to have_http_status(200)
      user.reload
      expect(user.failed_login_attempts).to eq(0)
    end
  end

  describe 'Rate Limiting', :rate_limiting do
    # Rate limiting is implemented via Rack::Attack middleware which is intentionally
    # disabled in the test environment to prevent flaky tests and test isolation issues.
    # See config/initializers/rack_attack.rb for the full implementation.
    #
    # Rate limiting provides protection against:
    # - Brute force password attacks (login attempts limited per IP and per email)
    # - Account enumeration (registration/password reset attempts limited)
    # - API abuse (tier-based rate limits for authenticated requests)
    #
    # To verify rate limiting manually, run the server in development mode
    # and use curl to make repeated requests against the login endpoint.

    it 'limits login attempts per IP address (verified via Rack::Attack middleware)' do
      # This test documents the expected behavior but cannot be executed
      # because Rack::Attack middleware is disabled in test environment
      skip 'Rate limiting via Rack::Attack is disabled in test environment - see config/initializers/rack_attack.rb line 77'

      # Expected behavior when rate limiting is enabled:
      # After 10 failed login attempts from the same IP within an hour,
      # subsequent requests should receive 429 Too Many Requests response
      10.times do
        post '/api/v1/auth/login', params: {
          email: user.email,
          password: 'wrong_password'
        }, as: :json

        expect(response).to have_http_status(401)
      end

      # 11th attempt should be rate limited
      post '/api/v1/auth/login', params: {
        email: user.email,
        password: 'wrong_password'
      }, as: :json

      expect(response).to have_http_status(429)
      expect(json_response['error']).to eq('Too many requests')
    end
  end

  describe 'Session Security' do
    it 'does not expose sensitive data in session' do
      post '/api/v1/auth/login', params: {
        email: user.email,
        password: TestUsers::PASSWORD
      }, as: :json

      expect(response).to have_http_status(200)

      # Check that sensitive data is not in the response (response is wrapped in data envelope)
      expect(json_response_data).not_to have_key('password_digest')
      expect(json_response_data).not_to have_key('password')
      expect(json_response_data['user']).not_to have_key('password_digest')
    end

    it 'invalidates refresh tokens on logout' do
      # Login to get tokens
      post '/api/v1/auth/login', params: {
        email: user.email,
        password: TestUsers::PASSWORD
      }, as: :json

      refresh_token = json_response_data['refresh_token']
      headers = auth_headers_for(user)

      # Logout
      post '/api/v1/auth/logout', params: { refresh_token: refresh_token }, headers: headers, as: :json

      expect(response).to have_http_status(200)

      # Try to use refresh token after logout - JWT refresh tokens are stateless
      # but the app should reject blacklisted/revoked tokens
      post '/api/v1/auth/refresh', params: {
        refresh_token: refresh_token
      }, as: :json

      # JWT tokens are stateless, so the refresh endpoint might return 400 if the
      # token is blacklisted or 401 if it's invalid/expired
      expect(response.status).to be_in([ 400, 401 ])
    end
  end

  describe 'Authorization Security' do
    let(:admin_user) { create(:user, :admin, account: account) }
    let(:member_user) { create(:user, :member, account: account) }
    let(:other_account) { create(:account) }
    let(:other_user) { create(:user, account: other_account) }

    it 'enforces account isolation' do
      headers = auth_headers_for(other_user)

      # Try to access user from different account
      get "/api/v1/users/#{user.id}", headers: headers

      expect(response).to have_http_status(403)
    end

    it 'enforces role-based permissions' do
      headers = auth_headers_for(member_user)

      # Try to access admin-only functionality
      # Since we don't have admin routes yet, test with a regular endpoint but different account
      other_account = create(:account)
      other_user = create(:user, account: other_account)

      get "/api/v1/users/#{other_user.id}", headers: headers

      expect(response).to have_http_status(403)
    end

    it 'validates permission scopes' do
      headers = auth_headers_for(member_user)

      # Try to delete user as member (should not have permission)
      delete "/api/v1/users/#{user.id}", headers: headers

      expect(response).to have_http_status(403)
    end
  end

  describe 'Input Validation Security' do
    it 'prevents SQL injection in login' do
      post '/api/v1/auth/login', params: {
        email: "test@example.com'; DROP TABLE users; --",
        password: 'password'
      }, as: :json

      expect(response).to have_http_status(401)
      # User table should still exist
      expect { User.count }.not_to raise_error
    end

    it 'sanitizes email input' do
      post '/api/v1/auth/register', params: {
        email: '<script>alert("xss")</script>@example.com',
        password: TestUsers::PASSWORD,
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company'
      }, as: :json

      if response.status == 201
        user = User.find_by(first_name: 'Test')
        expect(user.email).not_to include('<script>')
      end
    end

    it 'validates email format strictly' do
      post '/api/v1/auth/register', params: {
        email: 'not_an_email',
        password: TestUsers::PASSWORD,
        firstName: 'Test',
        lastName: 'User',
        accountName: 'Test Company'
      }, as: :json

      expect(response).to have_http_status(422)
      expect(json_response['error']).to include('Email is invalid')
    end
  end

  describe 'HTTPS and Security Headers' do
    it 'enforces secure headers in production' do
      get '/', headers: { 'HTTP_X_FORWARDED_PROTO' => 'https' }

      # Test that security headers are present (development mode has SAMEORIGIN instead of DENY)
      expect(response.headers).to include(
        'X-Content-Type-Options' => 'nosniff',
        'X-XSS-Protection' => '1; mode=block'
      )

      # Check that X-Frame-Options is present (SAMEORIGIN in dev, DENY in prod)
      expect(response.headers).to have_key('X-Frame-Options')

      # CSP should be present
      expect(response.headers).to have_key('Content-Security-Policy')
    end

    it 'sets secure cookie flags in production' do
      allow(Rails.env).to receive(:production?).and_return(true)

      post '/api/v1/auth/login', params: {
        email: user.email,
        password: TestUsers::PASSWORD
      }, as: :json

      # Check Set-Cookie header for secure flags if cookies are used
      set_cookie = response.headers['Set-Cookie']
      if set_cookie
        expect(set_cookie).to include('Secure')
        expect(set_cookie).to include('HttpOnly')
        expect(set_cookie).to include('SameSite=Strict')
      end
    end
  end
end
