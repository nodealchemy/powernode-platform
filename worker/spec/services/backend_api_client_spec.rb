# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BackendApiClient, type: :service do
  let(:client) { described_class.new }

  before do
    mock_powernode_worker_config
  end

  describe 'initialization' do
    it 'creates a client instance' do
      expect(client).to be_a(BackendApiClient)
    end

    it 'builds connection with proper configuration' do
      connection = client.instance_variable_get(:@connection)
      expect(connection).to be_a(Faraday::Connection)
    end
  end

  describe 'API Error handling' do
    describe BackendApiClient::ApiError do
      it 'stores status and response body' do
        error = BackendApiClient::ApiError.new('Test message', 404, { 'error' => 'Not found' })
        
        expect(error.message).to eq('Test message')
        expect(error.status).to eq(404)
        expect(error.response_body).to eq({ 'error' => 'Not found' })
      end

      it 'works without status or response body' do
        error = BackendApiClient::ApiError.new('Simple error')
        
        expect(error.message).to eq('Simple error')
        expect(error.status).to be_nil
        expect(error.response_body).to be_nil
      end
    end
  end

  describe 'HTTP methods' do
    describe '#get' do
      it 'makes GET requests successfully' do
        stub_backend_api_success(:get, '/api/v1/test', { result: 'success' })
        
        result = client.get('/api/v1/test')
        expect(result).to eq({ 'result' => 'success' })
      end

      it 'passes parameters in query string' do
        stub_backend_api_success(:get, '/api/v1/test', { result: 'success' })
        
        client.get('/api/v1/test', { param1: 'value1', param2: 'value2' })
        
        expect_api_request(:get, '/api/v1/test')
      end

      it 'handles GET request errors' do
        stub_backend_api_error(:get, '/api/v1/test', status: 404, error_message: 'Not Found')
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Not Found')
      end
    end

    describe '#post' do
      it 'makes POST requests successfully' do
        data = { name: 'test', value: 42 }
        stub_backend_api_success(:post, '/api/v1/create', { id: '123', created: true })
        
        result = client.post('/api/v1/create', data)
        expect(result).to eq({ 'id' => '123', 'created' => true })
      end

      it 'sends data in request body' do
        data = { test: 'data' }
        stub_backend_api_success(:post, '/api/v1/create')
        
        client.post('/api/v1/create', data)
        
        expect_api_request(:post, '/api/v1/create', with_body: data)
      end
    end

    describe '#put' do
      it 'makes PUT requests successfully' do
        data = { name: 'updated' }
        stub_backend_api_success(:put, '/api/v1/update/123', { updated: true })
        
        result = client.put('/api/v1/update/123', data)
        expect(result).to eq({ 'updated' => true })
      end
    end

    describe '#patch' do
      it 'makes PATCH requests successfully' do
        data = { status: 'completed' }
        stub_backend_api_success(:patch, '/api/v1/items/456', { patched: true })
        
        result = client.patch('/api/v1/items/456', data)
        expect(result).to eq({ 'patched' => true })
      end
    end

    describe '#delete' do
      it 'makes DELETE requests successfully' do
        stub_backend_api_success(:delete, '/api/v1/delete/789', { deleted: true })
        
        result = client.delete('/api/v1/delete/789')
        expect(result).to eq({ 'deleted' => true })
      end
    end
  end

  describe 'specific API methods' do
    describe '#get_account' do
      it 'fetches account data' do
        account_id = 'account-123'
        account_data = { id: account_id, name: 'Test Account' }
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}", account_data)
        
        result = client.get_account(account_id)
        expect(result).to eq(account_data.stringify_keys)
      end
    end

    describe '#get_account_subscription' do
      it 'fetches subscription data' do
        account_id = 'account-123'
        subscription_data = { plan: 'pro', status: 'active' }
        stub_backend_api_success(:get, "/api/v1/accounts/#{account_id}/subscription", subscription_data)
        
        result = client.get_account_subscription(account_id)
        expect(result).to eq(subscription_data.stringify_keys)
      end
    end

    describe '#get_analytics' do
      it 'fetches analytics data' do
        analytics_data = { metrics: [{ date: '2024-01-01', value: 100 }] }
        stub_backend_api_success(:get, '/api/v1/analytics/revenue', analytics_data)
        
        result = client.get_analytics('revenue', { start_date: '2024-01-01' })
        expect(result).to eq(analytics_data.stringify_keys)
      end
    end

    describe '#create_report' do
      it 'creates a new report' do
        report_data = { type: 'analytics', parameters: {} }
        response_data = { id: 'report-123', status: 'created' }
        stub_backend_api_success(:post, '/api/v1/reports', response_data)
        
        result = client.create_report(report_data)
        expect(result).to eq(response_data.stringify_keys)
      end
    end

    describe 'report request management' do
      let(:request_id) { 'request-123' }

      describe '#get_report_request' do
        it 'fetches report request data' do
          request_data = { id: request_id, status: 'processing' }
          stub_backend_api_success(:get, "/api/v1/reports/requests/#{request_id}", request_data)
          
          result = client.get_report_request(request_id)
          expect(result).to eq(request_data.stringify_keys)
        end
      end

      describe '#update_report_request_status' do
        it 'updates request status' do
          stub_backend_api_success(:patch, "/api/v1/reports/requests/#{request_id}", { updated: true })
          
          result = client.update_report_request_status(request_id, 'processing')
          expect(result).to eq({ 'updated' => true })
        end
      end

      describe '#complete_report_request' do
        it 'completes report request with file details' do
          stub_backend_api_success(:patch, "/api/v1/reports/requests/#{request_id}", { completed: true })
          
          freeze_time_at(Time.current) do
            result = client.complete_report_request(
              request_id, 
              file_path: '/tmp/report.pdf',
              file_size: 1024,
              file_url: 'https://example.com/report.pdf'
            )
            
            expect(result).to eq({ 'completed' => true })
          end
          
          expect_api_request(:patch, "/api/v1/reports/requests/#{request_id}", 
            with_body: {
              status: 'completed',
              file_path: '/tmp/report.pdf',
              file_size: 1024,
              file_url: 'https://example.com/report.pdf',
              completed_at: Time.current.iso8601
            }
          )
        end
      end

      describe '#fail_report_request' do
        it 'marks report request as failed' do
          error_message = 'Generation failed'
          stub_backend_api_success(:patch, "/api/v1/reports/requests/#{request_id}", { failed: true })
          
          freeze_time_at(Time.current) do
            result = client.fail_report_request(request_id, error_message)
            expect(result).to eq({ 'failed' => true })
          end
          
          expect_api_request(:patch, "/api/v1/reports/requests/#{request_id}",
            with_body: {
              status: 'failed',
              error_message: error_message,
              completed_at: Time.current.iso8601
            }
          )
        end
      end
    end

    describe '#get_report_data' do
      it 'fetches report data for generation' do
        report_data = { data: [{ metric: 'value' }] }
        stub_backend_api_success(:get, '/api/v1/analytics/export', report_data)
        
        result = client.get_report_data('analytics', 'account-123', { period: 'monthly' })
        expect(result).to eq(report_data.stringify_keys)
      end

      it 'works without account_id' do
        report_data = { data: [{ global: 'metric' }] }
        stub_backend_api_success(:get, '/api/v1/analytics/export', report_data)
        
        result = client.get_report_data('system', nil, { scope: 'global' })
        expect(result).to eq(report_data.stringify_keys)
      end
    end

    describe 'service authentication' do
      describe '#verify_service_token' do
        it 'verifies service authentication' do
          auth_response = { valid: true, service: 'worker' }
          stub_backend_api_success(:post, '/api/v1/service/verify', auth_response)
          
          result = client.verify_service_token
          expect(result).to eq(auth_response.stringify_keys)
        end
      end

      describe '#authenticate_user' do
        it 'authenticates user credentials' do
          auth_response = { success: true, user_id: 'user-123' }
          stub_backend_api_success(:post, '/api/v1/service/authenticate_user', auth_response)
          
          result = client.authenticate_user('test@example.com', 'password')
          expect(result).to eq(auth_response.stringify_keys)
        end
      end

      describe '#verify_session' do
        it 'verifies user session' do
          session_response = { valid: true, user_id: 'user-123' }
          stub_backend_api_success(:post, '/api/v1/service/verify_session', session_response)
          
          result = client.verify_session('session-token-456')
          expect(result).to eq(session_response.stringify_keys)
        end
      end
    end

    describe '#health_check' do
      it 'performs health check' do
        health_data = { status: 'ok', timestamp: Time.current.iso8601 }
        stub_backend_api_success(:get, '/api/v1/health', health_data)
        
        result = client.health_check
        expect(result).to eq(health_data.stringify_keys)
      end
    end
  end

  describe 'error handling' do
    context 'HTTP status code errors' do
      it 'handles 400 Bad Request' do
        stub_backend_api_error(:get, '/api/v1/test', status: 400, error_message: 'Invalid request')
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError) do |error|
          expect(error.status).to eq(400)
          expect(error.message).to eq('Invalid request')
        end
      end

      it 'handles 401 Unauthorized' do
        stub_backend_api_error(:get, '/api/v1/test', status: 401, error_message: 'Unauthorized')
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Service authentication failed')
      end

      it 'handles 403 Forbidden' do
        stub_backend_api_error(:get, '/api/v1/test', status: 403)
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Service access forbidden')
      end

      it 'handles 404 Not Found' do
        stub_backend_api_error(:get, '/api/v1/test', status: 404, error_message: 'Resource not found')
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Resource not found')
      end

      it 'handles 422 Unprocessable Entity' do
        stub_backend_api_error(:post, '/api/v1/test', status: 422, error_message: 'Validation failed')
        
        expect {
          client.post('/api/v1/test', {})
        }.to raise_error(BackendApiClient::ApiError, 'Validation failed')
      end

      it 'handles 500 Server Error' do
        stub_backend_api_error(:get, '/api/v1/test', status: 500)
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Backend server error')
      end

      it 'handles unexpected status codes' do
        stub_backend_api_error(:get, '/api/v1/test', status: 418) # I'm a teapot
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Unexpected response: 418')
      end
    end

    context 'network errors' do
      it 'handles timeout errors' do
        stub_backend_api_timeout(:get, '/api/v1/test')
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, /Request timeout/)
      end

      it 'handles connection failures' do
        stub_backend_api_connection_failure(:get, '/api/v1/test')
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, /Connection failed/)
      end
    end

    describe 'error message extraction' do
      it 'extracts error from message field' do
        error_body = { 'message' => 'Custom error message' }
        url = 'http://localhost:3000/api/v1/test'
        
        WebMock.stub_request(:get, url)
          .to_return(status: 400, body: error_body.to_json, headers: { 'Content-Type' => 'application/json' })
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Custom error message')
      end

      it 'extracts error from error field' do
        error_body = { 'error' => 'Another error message' }
        url = 'http://localhost:3000/api/v1/test'
        
        WebMock.stub_request(:get, url)
          .to_return(status: 422, body: error_body.to_json, headers: { 'Content-Type' => 'application/json' })
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Another error message')
      end

      it 'extracts nested error messages' do
        error_body = { 'errors' => { 'message' => 'Nested error' } }
        url = 'http://localhost:3000/api/v1/test'
        
        WebMock.stub_request(:get, url)
          .to_return(status: 400, body: error_body.to_json, headers: { 'Content-Type' => 'application/json' })
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Nested error')
      end

      it 'extracts first error from array' do
        error_body = { 'errors' => ['First error', 'Second error'] }
        url = 'http://localhost:3000/api/v1/test'
        
        WebMock.stub_request(:get, url)
          .to_return(status: 422, body: error_body.to_json, headers: { 'Content-Type' => 'application/json' })
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'First error')
      end

      it 'uses default message when no error found' do
        error_body = { 'other_field' => 'not an error' }
        url = 'http://localhost:3000/api/v1/test'
        
        WebMock.stub_request(:get, url)
          .to_return(status: 404, body: error_body.to_json, headers: { 'Content-Type' => 'application/json' })
        
        expect {
          client.get('/api/v1/test')
        }.to raise_error(BackendApiClient::ApiError, 'Resource not found')
      end
    end
  end

  describe 'request configuration' do
    it 'includes proper headers' do
      stub_backend_api_success(:get, '/api/v1/test')
      
      client.get('/api/v1/test')
      
      expect(WebMock).to have_been_requested(:get, 'http://localhost:3000/api/v1/test')
        .with(headers: {
          'Authorization' => 'Bearer test-service-token-456',
          'Content-Type' => 'application/json',
          'Accept' => 'application/json',
          'User-Agent' => 'PowernodeWorker/1.0'
        })
    end
  end
end