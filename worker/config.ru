#!/usr/bin/env ruby

require_relative 'config/application'

# Initialize the Powernode Worker application
PowernodeWorker.application

# Jobs API endpoint
map '/api/v1/jobs' do
  run JobsController
end

# Configure Sidekiq Web with authentication
map '/sidekiq' do
  use SidekiqWebAuth
  run Sidekiq::Web
end

# Health check endpoint
map '/health' do
  run proc { |env|
    begin
      # Check Redis connection
      redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/1')
      redis = Redis.new(url: redis_url)
      redis.ping
      
      # Check backend API connection
      api_client = BackendApiClient.new
      api_client.health_check
      
      [200, {'Content-Type' => 'application/json'}, [
        {
          status: 'ok',
          timestamp: Time.current.iso8601,
          redis: 'connected',
          backend_api: 'connected'
        }.to_json
      ]]
    rescue => e
      [503, {'Content-Type' => 'application/json'}, [
        {
          status: 'error',
          timestamp: Time.current.iso8601,
          error: e.message
        }.to_json
      ]]
    end
  }
end

# Root endpoint - basic info
map '/' do
  run proc { |env|
    [200, {'Content-Type' => 'application/json'}, [
      {
        service: 'Powernode Worker',
        version: '1.0.0',
        environment: PowernodeWorker.application.env,
        timestamp: Time.current.iso8601,
        endpoints: {
          sidekiq_web: '/sidekiq',
          health_check: '/health'
        }
      }.to_json
    ]]
  }
end