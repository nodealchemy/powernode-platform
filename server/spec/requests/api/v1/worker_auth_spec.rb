# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::WorkerAuth', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, email_verified: true) }
  let(:worker) { create(:worker, :system_worker, status: 'active') }

  # mTLS auth — Traefik forwards the verified CN (= NodeInstance.id) via
  # the URL-encoded X-Forwarded-Tls-Client-Cert-Info header. The Worker is
  # resolved by node_instance_id (Stage 8b Workers-as-NodeInstances).
  let(:worker_auth_headers) do
    {
      'X-Forwarded-Tls-Client-Cert-Info' =>
        CGI.escape(%(Subject="CN=#{worker.node_instance_id}")),
      'Content-Type' => 'application/json'
    }
  end

  before do
    # Grant admin permissions
    allow_any_instance_of(User).to receive(:has_permission?).with('admin.access').and_return(true)
    allow_any_instance_of(User).to receive(:has_permission?).with('system.admin').and_return(true)
  end

  describe 'POST /api/v1/worker_auth/authenticate_user' do
    let(:auth_params) do
      {
        email: user.email,
        password: TestUsers::PASSWORD
      }
    end

    context 'with valid credentials' do
      it 'authenticates user and returns session token' do
        allow(user).to receive(:authenticate).and_return(true)
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params,
          headers: worker_auth_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be true
        expect(data['session_token']).to be_present
        expect(data['user_email']).to eq(user.email)
        expect(data['permissions']).to be_an(Array)
      end

      it 'caches session token' do
        allow(user).to receive(:authenticate).and_return(true)
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params,
          headers: worker_auth_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['session_token']).to be_present

        # Verify the session was cached by reading it back
        session_data = Rails.cache.read("worker_session:#{data['session_token']}")
        expect(session_data).to be_present
        expect(session_data[:user_id]).to eq(user.id)
      end
    end

    context 'with invalid email' do
      it 'returns unauthorized error' do
        allow(User).to receive(:find_by).with(email: auth_params[:email]).and_return(nil)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params,
          headers: worker_auth_headers, as: :json

        expect_error_response('Invalid email or password', 401)
      end
    end

    context 'with invalid password' do
      it 'returns unauthorized error' do
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)
        allow(user).to receive(:authenticate).and_return(false)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params,
          headers: worker_auth_headers, as: :json

        expect_error_response('Invalid email or password', 401)
      end
    end

    context 'with unverified email' do
      it 'returns unauthorized error' do
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:email_verified?).and_return(false)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params,
          headers: worker_auth_headers, as: :json

        expect_error_response('Email not verified', 401)
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:has_permission?).and_return(false)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params,
          headers: worker_auth_headers, as: :json

        expect_error_response('Insufficient permissions to access worker interface', 403)
      end
    end

    context 'with missing parameters' do
      it 'returns bad request for missing email' do
        post '/api/v1/worker_auth/authenticate_user', params: { password: 'test' },
          headers: worker_auth_headers, as: :json

        expect_error_response('Email and password are required', 400)
      end

      it 'returns bad request for missing password' do
        post '/api/v1/worker_auth/authenticate_user', params: { email: 'test@example.com' },
          headers: worker_auth_headers, as: :json

        expect_error_response('Email and password are required', 400)
      end
    end

    context 'without mTLS client cert' do
      it 'returns unauthorized error' do
        post '/api/v1/worker_auth/authenticate_user', params: auth_params,
          headers: { 'Content-Type' => 'application/json' }, as: :json

        expect_error_response('mTLS client certificate required', 401)
      end
    end

    context 'with mTLS cert for unknown worker' do
      it 'returns unauthorized error' do
        bad_headers = {
          'X-Forwarded-Tls-Client-Cert-Info' =>
            CGI.escape(%(Subject="CN=#{SecureRandom.uuid}")),
          'Content-Type' => 'application/json'
        }

        post '/api/v1/worker_auth/authenticate_user', params: auth_params,
          headers: bad_headers, as: :json

        expect_error_response('Worker not found for mTLS subject', 401)
      end
    end
  end

  describe 'POST /api/v1/worker_auth/verify_session' do
    let(:session_token) { SecureRandom.uuid }
    let(:session_data) do
      {
        user_id: user.id,
        user_email: user.email,
        permissions: [ 'admin.access' ],
        created_at: Time.current.iso8601
      }
    end

    before do
      Rails.cache.write("worker_session:#{session_token}", session_data, expires_in: 24.hours)
    end

    context 'with valid session token' do
      it 'verifies the session' do
        post '/api/v1/worker_auth/verify_session', params: { session_token: session_token },
          headers: worker_auth_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be true
        expect(data['user_email']).to eq(user.email)
        expect(data['permissions']).to be_an(Array)
      end
    end

    context 'with invalid session token' do
      it 'returns unauthorized error' do
        post '/api/v1/worker_auth/verify_session', params: { session_token: 'invalid-session-token' },
          headers: worker_auth_headers, as: :json

        expect_error_response('Invalid or expired session token', 401)
      end
    end

    context 'when user no longer exists' do
      it 'invalidates session and returns error' do
        Rails.cache.write("worker_session:#{session_token}", session_data.merge(user_id: SecureRandom.uuid), expires_in: 24.hours)

        post '/api/v1/worker_auth/verify_session', params: { session_token: session_token },
          headers: worker_auth_headers, as: :json

        expect_error_response('Session invalid - user permissions changed', 401)
        expect(Rails.cache.read("worker_session:#{session_token}")).to be_nil
      end
    end

    context 'when user lost permissions' do
      it 'invalidates session and returns error' do
        allow_any_instance_of(User).to receive(:has_permission?).and_return(false)

        post '/api/v1/worker_auth/verify_session', params: { session_token: session_token },
          headers: worker_auth_headers, as: :json

        expect_error_response('Session invalid - user permissions changed', 401)
        expect(Rails.cache.read("worker_session:#{session_token}")).to be_nil
      end
    end

    context 'with missing session token' do
      it 'returns bad request error' do
        post '/api/v1/worker_auth/verify_session',
          headers: worker_auth_headers, as: :json

        expect_error_response('Session token is required', 400)
      end
    end
  end
end
