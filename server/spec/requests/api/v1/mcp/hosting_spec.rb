# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Mcp::Hosting', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'mcp.hosting.read', 'mcp.hosting.write' ]) }
  let(:headers) { auth_headers_for(user) }

  let(:hosting_service) { instance_double(Mcp::HostingService) }

  before do
    allow(Mcp::HostingService).to receive(:new).with(account).and_return(hosting_service)
  end

  describe 'GET /api/v1/mcp/hosting/servers' do
    let(:servers_list) do
      {
        servers: [
          { id: SecureRandom.uuid, name: 'Test Server 1', status: 'running' },
          { id: SecureRandom.uuid, name: 'Test Server 2', status: 'stopped' }
        ],
        total: 2
      }
    end

    it 'returns list of servers' do
      allow(hosting_service).to receive(:list_servers).and_return(servers_list)

      get '/api/v1/mcp/hosting/servers', headers: headers, as: :json

      expect_success_response
      expect(json_response_data).to include('servers')
    end

    it 'applies status filter' do
      expect(hosting_service).to receive(:list_servers)
        .with(hash_including(status: 'running'))
        .and_return(servers_list)

      get '/api/v1/mcp/hosting/servers?status=running', headers: headers, as: :json

      expect_success_response
    end

    it 'applies pagination parameters' do
      expect(hosting_service).to receive(:list_servers)
        .with(hash_including(limit: 20, offset: 10))
        .and_return(servers_list)

      get '/api/v1/mcp/hosting/servers?limit=20&offset=10', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/mcp/hosting/servers/:id' do
    let(:server_id) { SecureRandom.uuid }
    let(:server_data) do
      { id: server_id, name: 'Test Server', status: 'running', tools: [] }
    end

    it 'returns server details when found' do
      allow(hosting_service).to receive(:get_server).with(server_id).and_return(server_data)

      get "/api/v1/mcp/hosting/servers/#{server_id}", headers: headers, as: :json

      expect_success_response
      expect(json_response_data).to include('id' => server_id)
    end

    it 'returns not found error when server does not exist' do
      allow(hosting_service).to receive(:get_server).with(server_id).and_return(nil)
      allow(hosting_service).to receive(:errors).and_return([ 'Server not found' ])

      get "/api/v1/mcp/hosting/servers/#{server_id}", headers: headers, as: :json

      expect_error_response('Server not found', 404)
    end
  end

  describe 'POST /api/v1/mcp/hosting/servers' do
    let(:server_params) do
      {
        name: 'New Server',
        description: 'Test server',
        server_type: 'custom',
        runtime: 'node',
        visibility: 'private'
      }
    end
    let(:created_server) { { id: SecureRandom.uuid, name: 'New Server' } }

    it 'creates a new server successfully' do
      allow(hosting_service).to receive(:create_server).and_return(created_server)

      post '/api/v1/mcp/hosting/servers', params: server_params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect_success_response
    end

    it 'returns error when creation fails' do
      allow(hosting_service).to receive(:create_server).and_return(nil)
      allow(hosting_service).to receive(:errors).and_return([ 'Name cannot be blank' ])

      post '/api/v1/mcp/hosting/servers', params: server_params, headers: headers, as: :json

      expect_error_response('Name cannot be blank', 422)
    end
  end

  describe 'PATCH /api/v1/mcp/hosting/servers/:id' do
    let(:server_id) { SecureRandom.uuid }
    let(:update_params) { { name: 'Updated Name' } }
    let(:updated_server) { { id: server_id, name: 'Updated Name' } }

    it 'updates server successfully' do
      allow(hosting_service).to receive(:update_server).with(server_id, anything).and_return(updated_server)

      patch "/api/v1/mcp/hosting/servers/#{server_id}", params: update_params, headers: headers, as: :json

      expect_success_response
    end

    it 'returns error when update fails' do
      allow(hosting_service).to receive(:update_server).and_return(nil)
      allow(hosting_service).to receive(:errors).and_return([ 'Update failed' ])

      patch "/api/v1/mcp/hosting/servers/#{server_id}", params: update_params, headers: headers, as: :json

      expect_error_response('Update failed', 422)
    end
  end

  describe 'DELETE /api/v1/mcp/hosting/servers/:id' do
    let(:server_id) { SecureRandom.uuid }

    it 'deletes server successfully' do
      allow(hosting_service).to receive(:delete_server).with(server_id).and_return(true)

      delete "/api/v1/mcp/hosting/servers/#{server_id}", headers: headers, as: :json

      expect_success_response
    end

    it 'returns error when deletion fails' do
      allow(hosting_service).to receive(:delete_server).and_return(nil)
      allow(hosting_service).to receive(:errors).and_return([ 'Cannot delete running server' ])

      delete "/api/v1/mcp/hosting/servers/#{server_id}", headers: headers, as: :json

      expect_error_response('Cannot delete running server', 422)
    end
  end

  describe 'POST /api/v1/mcp/hosting/servers/:id/deploy' do
    let(:server_id) { SecureRandom.uuid }
    let(:deployment_result) { { deployment_id: SecureRandom.uuid, status: 'deploying' } }

    it 'deploys server successfully' do
      expect(hosting_service).to receive(:deploy_server)
        .with(server_id, hash_including(user: user))
        .and_return(deployment_result)

      post "/api/v1/mcp/hosting/servers/#{server_id}/deploy", headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect_success_response
    end

    it 'accepts version and commit_sha parameters' do
      expect(hosting_service).to receive(:deploy_server)
        .with(server_id, hash_including(version: '1.0.0', commit_sha: 'abc123'))
        .and_return(deployment_result)

      post "/api/v1/mcp/hosting/servers/#{server_id}/deploy",
           params: { version: '1.0.0', commit_sha: 'abc123' },
           headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/mcp/hosting/servers/:id/rollback' do
    let(:server_id) { SecureRandom.uuid }
    let(:deployment_id) { SecureRandom.uuid }

    it 'rolls back deployment successfully' do
      allow(hosting_service).to receive(:rollback_deployment)
        .with(server_id, deployment_id: deployment_id)
        .and_return({ status: 'rolled_back' })

      post "/api/v1/mcp/hosting/servers/#{server_id}/rollback",
           params: { deployment_id: deployment_id },
           headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/mcp/hosting/servers/:id/deployments' do
    let(:server_id) { SecureRandom.uuid }
    let(:deployments) do
      [
        { id: SecureRandom.uuid, version: '1.0.0', status: 'deployed' },
        { id: SecureRandom.uuid, version: '0.9.0', status: 'deployed' }
      ]
    end

    it 'returns deployment history' do
      allow(hosting_service).to receive(:get_deployment_history)
        .with(server_id, limit: 20)
        .and_return(deployments)

      get "/api/v1/mcp/hosting/servers/#{server_id}/deployments", headers: headers, as: :json

      expect_success_response
    end

    it 'respects limit parameter' do
      expect(hosting_service).to receive(:get_deployment_history)
        .with(server_id, limit: 10)
        .and_return(deployments)

      get "/api/v1/mcp/hosting/servers/#{server_id}/deployments?limit=10", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/mcp/hosting/servers/:id/start' do
    let(:server_id) { SecureRandom.uuid }

    it 'starts server successfully' do
      allow(hosting_service).to receive(:start_server).with(server_id).and_return({ status: 'running' })

      post "/api/v1/mcp/hosting/servers/#{server_id}/start", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/mcp/hosting/servers/:id/stop' do
    let(:server_id) { SecureRandom.uuid }

    it 'stops server successfully' do
      allow(hosting_service).to receive(:stop_server).with(server_id).and_return({ status: 'stopped' })

      post "/api/v1/mcp/hosting/servers/#{server_id}/stop", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/mcp/hosting/servers/:id/restart' do
    let(:server_id) { SecureRandom.uuid }

    it 'restarts server successfully' do
      allow(hosting_service).to receive(:restart_server).with(server_id).and_return({ status: 'running' })

      post "/api/v1/mcp/hosting/servers/#{server_id}/restart", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/mcp/hosting/servers/:id/metrics' do
    let(:server_id) { SecureRandom.uuid }
    let(:metrics_data) do
      {
        cpu_usage: [ { timestamp: Time.current, value: 45.2 } ],
        memory_usage: [ { timestamp: Time.current, value: 60.5 } ]
      }
    end

    it 'returns server metrics' do
      allow(hosting_service).to receive(:get_server_metrics)
        .with(server_id, hash_including(period: 24.hours, granularity: 'hourly'))
        .and_return(metrics_data)

      get "/api/v1/mcp/hosting/servers/#{server_id}/metrics", headers: headers, as: :json

      expect_success_response
    end

    it 'accepts custom period and granularity' do
      expect(hosting_service).to receive(:get_server_metrics)
        .with(server_id, hash_including(period: 48.hours, granularity: 'daily'))
        .and_return(metrics_data)

      get "/api/v1/mcp/hosting/servers/#{server_id}/metrics?period_hours=48&granularity=daily", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/mcp/hosting/servers/:id/health' do
    let(:server_id) { SecureRandom.uuid }
    let(:health_data) { { status: 'healthy', uptime: 3600 } }

    it 'returns health status' do
      allow(hosting_service).to receive(:get_health_status).with(server_id).and_return(health_data)

      get "/api/v1/mcp/hosting/servers/#{server_id}/health", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/mcp/hosting/servers/:id/publish' do
    let(:server_id) { SecureRandom.uuid }
    let(:publish_params) do
      {
        category: 'productivity',
        price_usd: 9.99,
        description: 'A great server'
      }
    end

    it 'publishes server to marketplace' do
      allow(hosting_service).to receive(:publish_to_marketplace)
        .with(server_id, hash_including(publish_params))
        .and_return({ published: true })

      post "/api/v1/mcp/hosting/servers/#{server_id}/publish",
           params: publish_params,
           headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/mcp/hosting/servers/:id/unpublish' do
    let(:server_id) { SecureRandom.uuid }

    it 'unpublishes server from marketplace' do
      allow(hosting_service).to receive(:unpublish_from_marketplace)
        .with(server_id)
        .and_return({ published: false })

      post "/api/v1/mcp/hosting/servers/#{server_id}/unpublish", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/mcp/hosting/marketplace' do
    let(:marketplace_results) do
      {
        servers: [
          { id: SecureRandom.uuid, name: 'Public Server 1', category: 'productivity' }
        ],
        total: 1
      }
    end

    it 'browses marketplace servers' do
      allow(hosting_service).to receive(:browse_marketplace)
        .with(hash_including(limit: 50, offset: 0))
        .and_return(marketplace_results)

      get '/api/v1/mcp/hosting/marketplace', headers: headers, as: :json

      expect_success_response
    end

    it 'filters by category and search' do
      expect(hosting_service).to receive(:browse_marketplace)
        .with(hash_including(category: 'productivity', search: 'test'))
        .and_return(marketplace_results)

      get '/api/v1/mcp/hosting/marketplace?category=productivity&search=test', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/mcp/hosting/marketplace/:server_id/subscribe' do
    let(:server_id) { SecureRandom.uuid }

    it 'subscribes to marketplace server' do
      allow(hosting_service).to receive(:subscribe_to_server)
        .with(server_id, subscription_type: 'free')
        .and_return({ subscribed: true })

      post "/api/v1/mcp/hosting/marketplace/#{server_id}/subscribe", headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect_success_response
    end

    it 'accepts subscription_type parameter' do
      expect(hosting_service).to receive(:subscribe_to_server)
        .with(server_id, subscription_type: 'premium')
        .and_return({ subscribed: true })

      post "/api/v1/mcp/hosting/marketplace/#{server_id}/subscribe",
           params: { subscription_type: 'premium' },
           headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/mcp/hosting/subscriptions' do
    let(:subscriptions_list) do
      {
        subscriptions: [
          { id: SecureRandom.uuid, server_name: 'Server 1', status: 'active' }
        ],
        total: 1
      }
    end

    it 'returns user subscriptions' do
      allow(hosting_service).to receive(:get_subscriptions)
        .with(hash_including(limit: 50, offset: 0))
        .and_return(subscriptions_list)

      get '/api/v1/mcp/hosting/subscriptions', headers: headers, as: :json

      expect_success_response
    end

    it 'filters by status' do
      expect(hosting_service).to receive(:get_subscriptions)
        .with(hash_including(status: 'active'))
        .and_return(subscriptions_list)

      get '/api/v1/mcp/hosting/subscriptions?status=active', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'authentication' do
    it 'requires authentication for all endpoints' do
      get '/api/v1/mcp/hosting/servers', as: :json

      expect_error_response('Access token required', 401)
    end
  end
end
