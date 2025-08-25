# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RateLimiting, type: :module do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new(ApplicationController) do
      include RateLimiting

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
    end
  end

  let(:controller) { test_class.new }
  let(:request) { ActionDispatch::TestRequest.create }
  let(:response) { ActionDispatch::TestResponse.new }

  before do
    controller.request = request
    controller.response = response
    request.remote_addr = '192.168.1.1'
    Rails.cache.clear
    
    # Mock system settings
    allow(SystemSettingsService).to receive(:rate_limiting_enabled?).and_return(true)
    allow(SystemSettingsService).to receive(:rate_limit_setting)
      .with('api_requests_per_minute').and_return(3)
  end

  describe '#rate_limit_type' do
    it 'returns different types based on controller name' do
      allow(controller).to receive(:controller_name).and_return('sessions')
      allow(controller).to receive(:authenticated_request?).and_return(false)
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

  describe '#rate_limit_key' do
    it 'generates correct key for anonymous requests' do
      allow(controller).to receive(:current_user).and_return(nil)
      allow(controller).to receive(:controller_name).and_return('test')
      allow(controller).to receive(:action_name).and_return('show')
      
      expected_key = "rate_limit:test:show:ip_192.168.1.1"
      expect(controller.send(:rate_limit_key)).to eq(expected_key)
    end

    it 'generates correct key for authenticated requests' do
      user = double('User', id: 123)
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:controller_name).and_return('test')
      allow(controller).to receive(:action_name).and_return('show')
      
      expected_key = "rate_limit:test:show:user_123"
      expect(controller.send(:rate_limit_key)).to eq(expected_key)
    end
  end

  describe '#rate_limit_max_attempts' do
    it 'returns system setting value when available' do
      allow(SystemSettingsService).to receive(:rate_limit_setting)
        .with('api_requests_per_minute').and_return(50)
      
      expect(controller.send(:rate_limit_max_attempts)).to eq(50)
    end

    it 'returns default value when system setting unavailable' do
      allow(SystemSettingsService).to receive(:rate_limit_setting)
        .with('api_requests_per_minute').and_return(nil)
      
      expect(controller.send(:rate_limit_max_attempts)).to eq(60) # default for api_requests_per_minute
    end
  end

  describe '#check_and_increment_rate_limit' do
    before do
      allow(controller).to receive(:should_rate_limit?).and_return(true)
      allow(controller).to receive(:controller_name).and_return('test')
      allow(controller).to receive(:action_name).and_return('action')
      allow(controller).to receive(:current_user).and_return(nil)
    end

    it 'allows requests when under limit' do
      expect(controller).not_to receive(:render_rate_limit_exceeded)
      controller.send(:check_and_increment_rate_limit)
    end

    it 'blocks requests when over limit' do
      # Set cache to simulate hitting the limit
      key = controller.send(:rate_limit_key)
      Rails.cache.write(key, 3, expires_in: 60.seconds)

      expect(controller).to receive(:render_rate_limit_exceeded)
      controller.send(:check_and_increment_rate_limit)
    end

    it 'skips rate limiting when disabled' do
      allow(SystemSettingsService).to receive(:rate_limiting_enabled?).and_return(false)
      
      expect(controller).not_to receive(:render_rate_limit_exceeded)
      controller.send(:check_and_increment_rate_limit)
    end
  end

  describe '#increment_rate_limit_count' do
    before do
      allow(controller).to receive(:should_rate_limit?).and_return(true)
      allow(controller).to receive(:controller_name).and_return('test')
      allow(controller).to receive(:action_name).and_return('action')
      allow(controller).to receive(:current_user).and_return(nil)
      
      # Simulate check_and_increment_rate_limit setting instance variables
      key = controller.send(:rate_limit_key)
      controller.instance_variable_set(:@rate_limit_key, key)
      controller.instance_variable_set(:@rate_limit_current_count, 0)
    end

    it 'increments the rate limit count' do
      key = controller.instance_variable_get(:@rate_limit_key)
      
      expect(Rails.cache).to receive(:write).with(key, 1, expires_in: 60.seconds)
      controller.send(:increment_rate_limit_count)
    end

    it 'logs the rate limit increment' do
      expect(Rails.logger).to receive(:info)
        .with(/Rate limit increment:.*=.*1\/3/)
      
      controller.send(:increment_rate_limit_count)
    end
  end
end