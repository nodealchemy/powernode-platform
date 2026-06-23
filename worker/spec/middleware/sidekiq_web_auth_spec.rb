# frozen_string_literal: true

require 'spec_helper'
require 'rack/mock'

RSpec.describe SidekiqWebAuth do
  let(:app_calls) { [] }
  let(:app) { ->(env) { app_calls << env; [200, { 'content-type' => 'text/plain' }, ['DASHBOARD']] } }
  let(:api_client) { instance_double(WebAuthApiClient) }
  let(:middleware) { described_class.new(app) }

  before do
    mock_powernode_worker_config
    allow(WebAuthApiClient).to receive(:new).and_return(api_client)
  end

  def call(path: '/sidekiq/', method: 'GET', params: {}, session: {})
    env = Rack::MockRequest.env_for(path, method: method, params: params)
    env['rack.session'] = session
    middleware.call(env)
  end

  describe 'unauthenticated bypasses' do
    it 'allows /health without auth' do
      status, = call(path: '/health')
      expect(status).to eq(200)
      expect(app_calls.size).to eq(1)
    end

    it 'allows static assets without auth' do
      status, = call(path: '/sidekiq/javascripts/application.js')
      expect(status).to eq(200)
      expect(app_calls.size).to eq(1)
    end
  end

  describe 'access without a valid session' do
    it 'returns a 401 login page and never reaches the dashboard when there is no session' do
      status, headers, = call
      expect(status).to eq(401)
      expect(headers['content-type']).to include('text/html')
      expect(app_calls).to be_empty
    end

    it 'returns 401 when the session token fails backend verification' do
      allow(api_client).to receive(:verify_session).with('stale')
        .and_return({ 'success' => true, 'data' => { 'valid' => false } })
      status, = call(session: { 'session_token' => 'stale' })
      expect(status).to eq(401)
      expect(app_calls).to be_empty
    end

    it 'treats a backend ApiError during verification as unauthenticated (fails closed)' do
      allow(api_client).to receive(:verify_session)
        .and_raise(BackendApiClient::ApiError.new('backend unavailable'))
      status, = call(session: { 'session_token' => 'whatever' })
      expect(status).to eq(401)
      expect(app_calls).to be_empty
    end
  end

  describe 'access with a valid session' do
    it 'passes through to the dashboard when the backend verifies the session' do
      allow(api_client).to receive(:verify_session).with('good')
        .and_return({ 'success' => true, 'data' => { 'valid' => true } })
      status, _headers, body = call(session: { 'session_token' => 'good' })
      expect(status).to eq(200)
      expect(body.join).to include('DASHBOARD')
      expect(app_calls.size).to eq(1)
    end
  end

  describe 'platform token login' do
    it 'creates a session and redirects on a valid token' do
      allow(api_client).to receive(:verify_platform_token).with('tkn').and_return(
        { 'success' => true,
          'data' => { 'valid' => true, 'session_token' => 'sess', 'user_email' => 'a@example.com', 'expires_at' => 123 } }
      )
      session = {}
      env = Rack::MockRequest.env_for('/sidekiq/', method: 'GET', params: { token: 'tkn' })
      env['rack.session'] = session
      status, = middleware.call(env)
      expect(status).to eq(302)
      expect(session['session_token']).to eq('sess')
      expect(app_calls).to be_empty
    end

    it 'returns 401 for an invalid platform token' do
      allow(api_client).to receive(:verify_platform_token)
        .and_return({ 'success' => false, 'error' => 'nope' })
      status, = call(params: { token: 'bad' })
      expect(status).to eq(401)
      expect(app_calls).to be_empty
    end
  end

  describe 'email/password login' do
    it 'creates a session and redirects on valid credentials' do
      allow(api_client).to receive(:authenticate_user).with('a@example.com', 'pw').and_return(
        { 'success' => true, 'data' => { 'valid' => true, 'session_token' => 'sess', 'user_email' => 'a@example.com' } }
      )
      session = {}
      env = Rack::MockRequest.env_for('/sidekiq/', method: 'POST', params: { email: 'a@example.com', password: 'pw' })
      env['rack.session'] = session
      status, = middleware.call(env)
      expect(status).to eq(302)
      expect(session['session_token']).to eq('sess')
    end

    it 'returns 401 on a backend ApiError (bad credentials)' do
      allow(api_client).to receive(:authenticate_user)
        .and_raise(BackendApiClient::ApiError.new('invalid'))
      status, = call(method: 'POST', params: { email: 'a@example.com', password: 'wrong' })
      expect(status).to eq(401)
      expect(app_calls).to be_empty
    end
  end

  describe 'logout' do
    it 'clears the session and redirects' do
      session = { 'session_token' => 'sess', 'user_email' => 'a@example.com' }
      env = Rack::MockRequest.env_for('/sidekiq/logout', method: 'GET')
      env['rack.session'] = session
      status, = middleware.call(env)
      expect(status).to eq(302)
      expect(session).to be_empty
    end
  end
end
