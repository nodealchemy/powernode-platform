# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::WorkerAuth', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, email_verified: true) }
  let(:worker) { create(:worker, account: nil, status: 'active') } # System worker

  before do
    # Grant admin permissions
    allow_any_instance_of(User).to receive(:has_permission?).with('admin.access').and_return(true)
    allow_any_instance_of(User).to receive(:has_permission?).with('system.admin').and_return(true)
  end

  describe 'POST /api/v1/service/verify' do
    context 'with valid service token' do
      it 'verifies the service token' do
        allow(Worker).to receive(:authenticate).and_return(worker)
        allow(worker).to receive(:system?).and_return(true)

        post '/api/v1/service/verify', headers: {
          'Authorization' => "Bearer valid_token",
          'Content-Type' => 'application/json'
        }, as: :json

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be true
        expect(data['service']).to eq('powernode_worker')
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        allow(Worker).to receive(:authenticate).and_return(nil)

        post '/api/v1/service/verify', headers: {
          'Authorization' => 'Bearer invalid_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Invalid service token', 401)
      end
    end

    context 'without authorization header' do
      it 'returns unauthorized error' do
        post '/api/v1/service/verify', as: :json

        expect_error_response('Invalid service token', 401)
      end
    end
  end

  describe 'POST /api/v1/worker_auth/authenticate_user' do
    let(:auth_params) do
      {
        email: user.email,
        password: 'password123'
      }
    end

    before do
      allow(Worker).to receive(:authenticate).and_return(worker)
      allow(worker).to receive(:system?).and_return(true)
    end

    context 'with valid credentials' do
      it 'authenticates user and returns session token' do
        allow(user).to receive(:authenticate).and_return(true)
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

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

        expect(Rails.cache).to receive(:write).with(
          /worker_session:/,
          anything,
          expires_in: 24.hours
        )

        post '/api/v1/worker_auth/authenticate_user', params: auth_params, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json
      end
    end

    context 'with invalid email' do
      it 'returns unauthorized error' do
        allow(User).to receive(:find_by).with(email: auth_params[:email]).and_return(nil)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Invalid email or password', 401)
      end
    end

    context 'with invalid password' do
      it 'returns unauthorized error' do
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)
        allow(user).to receive(:authenticate).and_return(false)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Invalid email or password', 401)
      end
    end

    context 'with unverified email' do
      it 'returns unauthorized error' do
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:email_verified?).and_return(false)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Email not verified', 401)
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        allow(User).to receive(:find_by).with(email: user.email).and_return(user)
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:has_permission?).and_return(false)

        post '/api/v1/worker_auth/authenticate_user', params: auth_params, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Insufficient permissions to access worker interface', 403)
      end
    end

    context 'with missing parameters' do
      it 'returns bad request for missing email' do
        post '/api/v1/worker_auth/authenticate_user', params: { password: 'test' }, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Email and password are required', 400)
      end

      it 'returns bad request for missing password' do
        post '/api/v1/worker_auth/authenticate_user', params: { email: 'test@example.com' }, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Email and password are required', 400)
      end
    end
  end

  describe 'POST /api/v1/service/verify_session' do
    let(:session_token) { SecureRandom.uuid }
    let(:session_data) do
      {
        user_id: user.id,
        user_email: user.email,
        permissions: ['admin.access'],
        created_at: Time.current.iso8601
      }
    end

    before do
      allow(Worker).to receive(:authenticate).and_return(worker)
      allow(worker).to receive(:system?).and_return(true)
    end

    context 'with valid session token' do
      it 'verifies the session' do
        allow(Rails.cache).to receive(:read).with("worker_session:#{session_token}").and_return(session_data)
        allow(User).to receive(:find_by).with(id: user.id).and_return(user)

        post '/api/v1/service/verify_session', params: { session_token: session_token }, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be true
        expect(data['user_email']).to eq(user.email)
        expect(data['permissions']).to be_an(Array)
      end
    end

    context 'with invalid session token' do
      it 'returns unauthorized error' do
        allow(Rails.cache).to receive(:read).with("worker_session:#{session_token}").and_return(nil)

        post '/api/v1/service/verify_session', params: { session_token: session_token }, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Invalid or expired session token', 401)
      end
    end

    context 'when user no longer exists' do
      it 'invalidates session and returns error' do
        allow(Rails.cache).to receive(:read).with("worker_session:#{session_token}").and_return(session_data)
        allow(User).to receive(:find_by).with(id: user.id).and_return(nil)

        expect(Rails.cache).to receive(:delete).with("worker_session:#{session_token}")

        post '/api/v1/service/verify_session', params: { session_token: session_token }, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Session invalid - user permissions changed', 401)
      end
    end

    context 'when user lost permissions' do
      it 'invalidates session and returns error' do
        allow(Rails.cache).to receive(:read).with("worker_session:#{session_token}").and_return(session_data)
        allow(User).to receive(:find_by).with(id: user.id).and_return(user)
        allow(user).to receive(:has_permission?).and_return(false)

        expect(Rails.cache).to receive(:delete).with("worker_session:#{session_token}")

        post '/api/v1/service/verify_session', params: { session_token: session_token }, headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Session invalid - user permissions changed', 401)
      end
    end

    context 'with missing session token' do
      it 'returns bad request error' do
        post '/api/v1/service/verify_session', headers: {
          'Authorization' => 'Bearer worker_token',
          'Content-Type' => 'application/json'
        }, as: :json

        expect_error_response('Session token is required', 400)
      end
    end
  end
end
