# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Devops::Docker', type: :request do
  let(:account) { create(:account) }
  let(:host) { create(:devops_docker_host, :connected, account: account, auto_sync: true) }

  let(:service_headers) do
    payload = { service: 'worker', type: 'service', exp: 24.hours.from_now.to_i }
    token = Security::JwtService.encode(payload)
    { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }
  end

  describe 'GET /api/v1/internal/devops/docker/hosts' do
    it 'returns auto-syncable hosts' do
      host # create the host

      get '/api/v1/internal/devops/docker/hosts', headers: service_headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['hosts']).to be_an(Array)
      expect(response_data['data']['hosts'].first['id']).to eq(host.id)
    end

    it 'excludes non-syncable hosts' do
      create(:devops_docker_host, account: account, auto_sync: false)

      get '/api/v1/internal/devops/docker/hosts', headers: service_headers, as: :json

      expect_success_response
      response_data = json_response
      ids = response_data['data']['hosts'].map { |h| h['id'] }
      expect(ids).not_to include(Devops::DockerHost.where(auto_sync: false).first&.id)
    end

    context 'without service token' do
      it 'returns unauthorized' do
        get '/api/v1/internal/devops/docker/hosts', as: :json

        expect_error_response(nil, 401)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized' do
        get '/api/v1/internal/devops/docker/hosts',
            headers: { 'Authorization' => 'Bearer invalid_token' },
            as: :json

        expect_error_response(nil, 401)
      end
    end
  end

  describe 'GET /api/v1/internal/devops/docker/hosts/:id/connection' do
    it 'returns connection details' do
      get "/api/v1/internal/devops/docker/hosts/#{host.id}/connection",
          headers: service_headers, as: :json

      expect_success_response
      response_data = json_response
      connection = response_data['data']['connection']
      expect(connection['host_id']).to eq(host.id)
      expect(connection['api_endpoint']).to eq(host.api_endpoint)
    end

    it 'returns not found for nonexistent host' do
      get '/api/v1/internal/devops/docker/hosts/nonexistent-id/connection',
          headers: service_headers, as: :json

      expect_error_response('Host not found', 404)
    end
  end

  describe 'POST /api/v1/internal/devops/docker/hosts/:id/sync_results' do
    let(:containers_data) do
      [
        {
          docker_container_id: 'abc123',
          name: 'nginx-proxy',
          image: 'nginx:latest',
          state: 'running',
          status_text: 'Up 2 hours'
        }
      ]
    end

    let(:images_data) do
      [
        {
          docker_image_id: 'sha256:img001',
          repo_tags: ['nginx:latest'],
          size_bytes: 187_000_000
        }
      ]
    end

    it 'syncs containers and images' do
      post "/api/v1/internal/devops/docker/hosts/#{host.id}/sync_results",
           params: { containers: containers_data, images: images_data },
           headers: service_headers, as: :json

      expect_success_response

      expect(host.docker_containers.count).to eq(1)
      expect(host.docker_images.count).to eq(1)

      host.reload
      expect(host.container_count).to eq(1)
      expect(host.image_count).to eq(1)
      expect(host.status).to eq('connected')
      expect(host.consecutive_failures).to eq(0)
    end

    it 'removes stale containers' do
      create(:devops_docker_container, docker_host: host, docker_container_id: 'old_container')

      post "/api/v1/internal/devops/docker/hosts/#{host.id}/sync_results",
           params: { containers: containers_data },
           headers: service_headers, as: :json

      expect_success_response
      expect(host.docker_containers.find_by(docker_container_id: 'old_container')).to be_nil
    end

    it 'returns not found for nonexistent host' do
      post '/api/v1/internal/devops/docker/hosts/nonexistent-id/sync_results',
           params: { containers: [] },
           headers: service_headers, as: :json

      expect_error_response('Host not found', 404)
    end
  end

  describe 'POST /api/v1/internal/devops/docker/hosts/:id/health_results' do
    it 'records healthy status' do
      post "/api/v1/internal/devops/docker/hosts/#{host.id}/health_results",
           params: { status: 'healthy' },
           headers: service_headers, as: :json

      expect_success_response
      host.reload
      expect(host.status).to eq('connected')
      expect(host.consecutive_failures).to eq(0)
    end

    it 'records unhealthy status' do
      post "/api/v1/internal/devops/docker/hosts/#{host.id}/health_results",
           params: { status: 'unhealthy' },
           headers: service_headers, as: :json

      expect_success_response
      host.reload
      expect(host.consecutive_failures).to eq(1)
    end

    it 'creates events from alerts' do
      alerts = [
        {
          type: 'resource_warning',
          severity: 'warning',
          source_type: 'host',
          message: 'High memory usage detected'
        }
      ]

      expect {
        post "/api/v1/internal/devops/docker/hosts/#{host.id}/health_results",
             params: { status: 'healthy', alerts: alerts },
             headers: service_headers, as: :json
      }.to change(Devops::DockerEvent, :count).by(1)

      expect_success_response
      event = Devops::DockerEvent.last
      expect(event.severity).to eq('warning')
      expect(event.message).to eq('High memory usage detected')
    end
  end

  describe 'POST /api/v1/internal/devops/docker/events' do
    it 'creates a new event' do
      expect {
        post '/api/v1/internal/devops/docker/events',
             params: {
               docker_host_id: host.id,
               event_type: 'container_crash',
               severity: 'critical',
               source_type: 'container',
               source_name: 'web-app',
               message: 'Container exited unexpectedly'
             },
             headers: service_headers, as: :json
      }.to change(Devops::DockerEvent, :count).by(1)

      expect_success_response
      response_data = json_response
      expect(response_data['data']['event_id']).to be_present
    end

    it 'cleans up old acknowledged events' do
      # Create old acknowledged events
      3.times do
        create(:devops_docker_event, :acknowledged, docker_host: host, created_at: 60.days.ago)
      end

      post '/api/v1/internal/devops/docker/events',
           params: { action_type: 'cleanup', older_than_days: 30 },
           headers: service_headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['deleted_count']).to eq(3)
    end

    it 'returns not found for nonexistent host' do
      post '/api/v1/internal/devops/docker/events',
           params: {
             docker_host_id: 'nonexistent-id',
             event_type: 'test',
             severity: 'info',
             source_type: 'host',
             message: 'test'
           },
           headers: service_headers, as: :json

      expect_error_response('Host not found', 404)
    end
  end
end
