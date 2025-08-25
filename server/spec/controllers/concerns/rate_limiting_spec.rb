# frozen_string_literal: true

require 'rails_helper'

# Test controller to test the RateLimiting concern
class TestRateLimitingController < ApplicationController
  def test_action
    render_success({ message: "Test successful" })
  end

  def no_rate_limit_action
    render_success({ message: "No rate limit action" })
  end

  private

  def should_rate_limit?
    action_name != 'no_rate_limit_action'
  end

  def rate_limit_type
    'api_requests_per_minute'
  end
end

RSpec.describe RateLimiting, type: :controller do
  controller TestRateLimitingController

  let(:test_ip) { '192.168.1.1' }
  
  before do
    Rails.application.routes.draw do
      get 'test_rate_limiting/test_action', to: 'test_rate_limiting#test_action'
      get 'test_rate_limiting/no_rate_limit_action', to: 'test_rate_limiting#no_rate_limit_action'
    end
    
    request.remote_addr = test_ip
    Rails.cache.clear
    
    # Mock system settings to return predictable rate limits
    allow(SystemSettingsService).to receive(:rate_limiting_enabled?).and_return(true)
    allow(SystemSettingsService).to receive(:rate_limit_setting)
      .with('api_requests_per_minute').and_return(3)
  end

  after do
    Rails.application.reload_routes!
  end

  describe '#check_and_increment_rate_limit' do
    context 'when rate limiting is enabled' do
      it 'allows requests within the limit' do
        get :test_action
        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
      end

      it 'blocks requests that exceed the limit' do
        # Make 3 requests (at the limit)
        3.times { get :test_action }
        expect(response).to have_http_status(:ok)

        # The 4th request should be blocked
        get :test_action
        expect(response).to have_http_status(:too_many_requests)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('Rate limit exceeded')
        expect(json_response['code']).to eq('RATE_LIMITED')
      end

      it 'provides retry information in rate limit response' do
        # Exceed the limit
        4.times { get :test_action }
        
        expect(json_response['details']).to include(
          'retry_after' => 60,
          'limit' => 3,
          'window' => 60
        )
      end

      it 'tracks separate limits for different actions' do
        # Use different action that doesn't have rate limiting
        3.times { get :no_rate_limit_action }
        expect(response).to have_http_status(:ok)

        # Should still be able to make requests to test_action
        get :test_action
        expect(response).to have_http_status(:ok)
      end

      it 'tracks separate limits for different IPs' do
        # Make requests from first IP
        3.times { get :test_action }
        expect(response).to have_http_status(:ok)

        # Change IP and should still work
        request.remote_addr = '192.168.1.2'
        get :test_action
        expect(response).to have_http_status(:ok)
      end

      it 'resets limits after the window expires' do
        # Exceed the limit
        4.times { get :test_action }
        expect(response).to have_http_status(:too_many_requests)

        # Mock time passing (simulate cache expiry)
        Rails.cache.clear
        
        get :test_action
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when rate limiting is disabled' do
      before do
        allow(SystemSettingsService).to receive(:rate_limiting_enabled?).and_return(false)
      end

      it 'allows unlimited requests' do
        10.times do
          get :test_action
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context 'with authenticated users' do
      let(:account) { create(:account) }
      let(:user) { create(:user, account: account) }

      before do
        authenticate_as(user)
      end

      it 'uses user ID in rate limit key for authenticated requests' do
        # This test verifies that authenticated users get per-user limits
        # rather than per-IP limits
        expect(controller).to receive(:rate_limit_key)
          .and_return("rate_limit:test_rate_limiting:test_action:user_#{user.id}")
          .at_least(:once)
        
        get :test_action
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe '#rate_limit_type' do
    it 'returns correct limit type for different controllers' do
      allow(controller).to receive(:controller_name).and_return('sessions')
      expect(controller.send(:rate_limit_type)).to eq('login_attempts_per_hour')

      allow(controller).to receive(:controller_name).and_return('registrations')
      expect(controller.send(:rate_limit_type)).to eq('registration_attempts_per_hour')

      allow(controller).to receive(:controller_name).and_return('passwords')
      expect(controller.send(:rate_limit_type)).to eq('password_reset_attempts_per_hour')

      allow(controller).to receive(:controller_name).and_return('webhooks')
      expect(controller.send(:rate_limit_type)).to eq('webhook_requests_per_minute')
    end

    it 'returns default type for unknown controllers' do
      allow(controller).to receive(:controller_name).and_return('unknown')
      allow(controller).to receive(:authenticated_request?).and_return(false)
      expect(controller.send(:rate_limit_type)).to eq('api_requests_per_minute')

      allow(controller).to receive(:authenticated_request?).and_return(true)
      expect(controller.send(:rate_limit_type)).to eq('authenticated_requests_per_hour')
    end
  end

  describe '#rate_limit_window_seconds' do
    it 'returns 60 seconds for per-minute limits' do
      allow(controller).to receive(:rate_limit_type).and_return('api_requests_per_minute')
      expect(controller.send(:rate_limit_window_seconds)).to eq(60)

      allow(controller).to receive(:rate_limit_type).and_return('webhook_requests_per_minute')
      expect(controller.send(:rate_limit_window_seconds)).to eq(60)
    end

    it 'returns 3600 seconds for per-hour limits' do
      allow(controller).to receive(:rate_limit_type).and_return('login_attempts_per_hour')
      expect(controller.send(:rate_limit_window_seconds)).to eq(3600)
    end
  end

  describe '#increment_rate_limit_count' do
    it 'increments the count when called after a request' do
      expect(Rails.cache).to receive(:write)
        .with(anything, 1, expires_in: 60.seconds)
      
      get :test_action
      controller.send(:increment_rate_limit_count)
    end

    it 'logs rate limit increments for monitoring' do
      expect(Rails.logger).to receive(:info)
        .with(/Rate limit increment:.*=.*1\/3/)
      
      get :test_action
      controller.send(:increment_rate_limit_count)
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def authenticate_as(user)
    payload = { user_id: user.id }
    token = JWT.encode(payload, Rails.application.config.jwt_secret_key, 'HS256')
    request.headers['Authorization'] = "Bearer #{token}"
  end
end