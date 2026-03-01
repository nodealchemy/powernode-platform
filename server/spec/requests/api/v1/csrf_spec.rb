# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Csrf', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/csrf_token' do
    context 'with authenticated user' do
      before do
        Rails.cache.clear
      end

      it 'generates CSRF token successfully' do
        get '/api/v1/csrf_token', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'csrf_token',
          'expires_at',
          'header_name'
        )
      end

      it 'returns valid token format' do
        get '/api/v1/csrf_token', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['csrf_token']).to be_present
        expect(data['csrf_token'].length).to be > 20
      end

      it 'includes expiration timestamp' do
        get '/api/v1/csrf_token', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['expires_at']).to be_present

        expires_at = Time.parse(data['expires_at'])
        expect(expires_at).to be > Time.current
        expect(expires_at).to be < (Time.current + 3.hours)
      end

      it 'includes header name for token usage' do
        get '/api/v1/csrf_token', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['header_name']).to eq('X-CSRF-Token')
      end

      it 'stores token in Rails cache' do
        get '/api/v1/csrf_token', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        cached_token = Rails.cache.read("csrf_token_#{user.id}")
        expect(cached_token).to eq(data['csrf_token'])
      end

      it 'creates audit log entry' do
        expect do
          get '/api/v1/csrf_token', headers: headers, as: :json
        end.to change(AuditLog, :count).by(1)

        audit = AuditLog.last
        expect(audit.action).to eq('csrf_token_generated')
        expect(audit.user_id).to eq(user.id)
        expect(audit.account_id).to eq(account.id)
        expect(audit.resource_type).to eq('User')
        expect(audit.resource_id).to eq(user.id)
      end

      it 'includes IP address in audit log' do
        get '/api/v1/csrf_token', headers: headers, as: :json

        audit = AuditLog.last
        expect(audit.ip_address).to be_present
      end

      it 'includes user agent in audit log' do
        custom_headers = headers.merge('User-Agent' => 'TestBrowser/1.0')

        get '/api/v1/csrf_token', headers: custom_headers, as: :json

        audit = AuditLog.last
        expect(audit.user_agent).to eq('TestBrowser/1.0')
      end

      it 'generates different tokens on subsequent calls' do
        get '/api/v1/csrf_token', headers: headers, as: :json
        first_token = json_response_data['csrf_token']

        get '/api/v1/csrf_token', headers: headers, as: :json
        second_token = json_response_data['csrf_token']

        expect(first_token).not_to eq(second_token)
      end

      it 'overwrites previous token in cache' do
        get '/api/v1/csrf_token', headers: headers, as: :json
        first_token = json_response_data['csrf_token']

        get '/api/v1/csrf_token', headers: headers, as: :json
        second_token = json_response_data['csrf_token']

        cached_token = Rails.cache.read("csrf_token_#{user.id}")
        expect(cached_token).to eq(second_token)
        expect(cached_token).not_to eq(first_token)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/csrf_token', as: :json

        expect_error_response('Access token required', 401)
      end

      it 'does not create audit log entry' do
        expect do
          get '/api/v1/csrf_token', as: :json
        end.not_to change(AuditLog, :count)
      end

      it 'does not store token in cache' do
        get '/api/v1/csrf_token', as: :json

        expect(Rails.cache.exist?("csrf_token_#{user.id}")).to be false
      end
    end

    context 'with custom token expiry configuration' do
      around do |example|
        original_expiry = Rails.configuration.x.csrf_token_expiry
        Rails.configuration.x.csrf_token_expiry = 1.hour
        example.run
        Rails.configuration.x.csrf_token_expiry = original_expiry
      end

      it 'respects custom expiry time' do
        get '/api/v1/csrf_token', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expires_at = Time.parse(data['expires_at'])
        expected_expiry = Time.current + 1.hour

        expect(expires_at).to be_within(5.seconds).of(expected_expiry)
      end
    end

    context 'with custom header name configuration' do
      around do |example|
        original_header = Rails.configuration.x.csrf_token_header_name
        Rails.configuration.x.csrf_token_header_name = 'X-Custom-CSRF'
        example.run
        Rails.configuration.x.csrf_token_header_name = original_header
      end

      it 'returns custom header name' do
        get '/api/v1/csrf_token', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['header_name']).to eq('X-Custom-CSRF')
      end
    end
  end
end
