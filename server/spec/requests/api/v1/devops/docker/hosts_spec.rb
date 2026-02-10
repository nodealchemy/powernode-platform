# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Docker::Hosts', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['docker.hosts.read']) }
  let(:user_with_manage) { create(:user, account: account, permissions: ['docker.hosts.read', 'docker.hosts.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/docker/hosts' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      create_list(:devops_docker_host, 3, account: account)
    end

    it 'returns list of hosts' do
      get '/api/v1/devops/docker/hosts', headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
      expect(response_data['data']['items'].length).to eq(3)
    end

    it 'filters by status' do
      create(:devops_docker_host, :connected, account: account)

      get "/api/v1/devops/docker/hosts?status=connected",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      statuses = response_data['data']['items'].map { |h| h['status'] }
      expect(statuses.uniq).to eq(['connected'])
    end

    it 'filters by environment' do
      create(:devops_docker_host, account: account, environment: 'production')

      get "/api/v1/devops/docker/hosts?environment=production",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      envs = response_data['data']['items'].map { |h| h['environment'] }
      expect(envs.uniq).to eq(['production'])
    end

    context 'account isolation' do
      let(:other_account) { create(:account) }

      before do
        create(:devops_docker_host, account: other_account)
      end

      it 'does not return hosts from other accounts' do
        get '/api/v1/devops/docker/hosts', headers: headers, as: :json

        expect_success_response
        response_data = json_response
        expect(response_data['data']['items'].length).to eq(3)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/docker/hosts', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:id' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:host) { create(:devops_docker_host, account: account) }

    it 'returns host details' do
      get "/api/v1/devops/docker/hosts/#{host.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['host']['id']).to eq(host.id)
      expect(response_data['data']['host']['name']).to eq(host.name)
    end

    context 'when host belongs to another account' do
      let(:other_account) { create(:account) }
      let(:other_host) { create(:devops_docker_host, account: other_account) }

      it 'returns not found' do
        get "/api/v1/devops/docker/hosts/#{other_host.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/devops/docker/hosts' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:valid_params) do
      {
        host: {
          name: 'New Docker Host',
          api_endpoint: 'https://docker.example.com:2376',
          environment: 'development'
        }
      }
    end

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping).and_return("OK")
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:info).and_return(
        {
          "ServerVersion" => "24.0.7",
          "OperatingSystem" => "Ubuntu 22.04",
          "Architecture" => "x86_64",
          "KernelVersion" => "5.15.0",
          "MemTotal" => 8_589_934_592,
          "NCPU" => 4,
          "Containers" => 0,
          "Images" => 0,
          "ApiVersion" => "1.45"
        }
      )
    end

    it 'creates a new host' do
      post '/api/v1/devops/docker/hosts', params: valid_params, headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['host']['name']).to eq('New Docker Host')
      expect(response_data['data']['host']['status']).to eq('connected')
    end

    it 'returns 422 with invalid params' do
      post '/api/v1/devops/docker/hosts',
           params: { host: { name: '' } },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH /api/v1/devops/docker/hosts/:id' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:host) { create(:devops_docker_host, account: account) }

    it 'updates host successfully' do
      patch "/api/v1/devops/docker/hosts/#{host.id}",
            params: { host: { name: 'Updated Host Name' } },
            headers: headers, as: :json

      expect_success_response
      host.reload
      expect(host.name).to eq('Updated Host Name')
    end
  end

  describe 'DELETE /api/v1/devops/docker/hosts/:id' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:host) { create(:devops_docker_host, account: account) }

    it 'deletes host successfully' do
      host_id = host.id

      delete "/api/v1/devops/docker/hosts/#{host_id}", headers: headers, as: :json

      expect_success_response
      expect(Devops::DockerHost.find_by(id: host_id)).to be_nil
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:id/test_connection' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:host) { create(:devops_docker_host, account: account) }

    context 'when connection succeeds' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping).and_return("OK")
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:info).and_return(
          { "ServerVersion" => "24.0.7", "ApiVersion" => "1.45", "OperatingSystem" => "Ubuntu", "Architecture" => "x86_64",
            "KernelVersion" => "5.15.0", "Containers" => 5, "Images" => 12, "MemTotal" => 8_589_934_592, "NCPU" => 4 }
        )
      end

      it 'returns connection result' do
        post "/api/v1/devops/docker/hosts/#{host.id}/test_connection", headers: headers, as: :json

        expect_success_response
        response_data = json_response
        expect(response_data['data']['connection']['success']).to be true
      end
    end

    context 'when connection fails' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping)
          .and_raise(Devops::Docker::ApiClient::ConnectionError.new("Connection refused"))
      end

      it 'returns failure result' do
        post "/api/v1/devops/docker/hosts/#{host.id}/test_connection", headers: headers, as: :json

        expect_success_response
        response_data = json_response
        expect(response_data['data']['connection']['success']).to be false
      end
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:id/sync' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:host) { create(:devops_docker_host, account: account) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_list).and_return([])
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_list).and_return([])
    end

    it 'syncs host and returns details' do
      post "/api/v1/devops/docker/hosts/#{host.id}/sync", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['host']).to be_present
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:id/health' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:host) { create(:devops_docker_host, :connected, account: account) }

    it 'returns health information' do
      create(:devops_docker_container, :running, docker_host: host)
      create(:devops_docker_event, :critical, docker_host: host)

      get "/api/v1/devops/docker/hosts/#{host.id}/health", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      health = response_data['data']['health']
      expect(health['host_id']).to eq(host.id)
      expect(health['status']).to eq('connected')
      expect(health['container_health']).to be_present
      expect(health['image_stats']).to be_present
      expect(health['recent_events']).to be_present
    end
  end
end
