# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Docker::Containers', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['docker.containers.read']) }
  let(:user_with_manage) { create(:user, account: account, permissions: ['docker.containers.read', 'docker.containers.manage', 'docker.containers.create', 'docker.containers.delete', 'docker.containers.logs']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }

  let(:mock_inspect_data) do
    {
      "Id" => "abc123",
      "Name" => "/test-container",
      "State" => { "Status" => "running", "StartedAt" => Time.current.iso8601, "FinishedAt" => "0001-01-01T00:00:00Z" },
      "Config" => { "Image" => "nginx:latest", "Cmd" => ["nginx"], "Labels" => {} },
      "RestartCount" => 0
    }
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/containers' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      create_list(:devops_docker_container, 3, :running, docker_host: host)
    end

    it 'returns list of containers' do
      get "/api/v1/devops/docker/hosts/#{host.id}/containers", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
      expect(response_data['data']['items'].length).to eq(3)
    end

    it 'filters by state' do
      create(:devops_docker_container, :stopped, docker_host: host)

      get "/api/v1/devops/docker/hosts/#{host.id}/containers?state=exited",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      states = response_data['data']['items'].map { |c| c['state'] }
      expect(states.uniq).to eq(['exited'])
    end

    it 'searches by name' do
      create(:devops_docker_container, docker_host: host, name: 'my-nginx-app')

      get "/api/v1/devops/docker/hosts/#{host.id}/containers?q=nginx",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      names = response_data['data']['items'].map { |c| c['name'] }
      expect(names).to include('my-nginx-app')
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get "/api/v1/devops/docker/hosts/#{host.id}/containers", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/containers/:id' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:container) { create(:devops_docker_container, :running, docker_host: host) }

    it 'returns container details' do
      get "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['container']['id']).to eq(container.id)
      expect(response_data['data']['container']['name']).to eq(container.name)
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/containers' do
    let(:headers) { auth_headers_for(user_with_manage) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_create)
        .and_return({ "Id" => "new123", "Warnings" => [] })
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_inspect)
        .and_return(mock_inspect_data.merge("Id" => "new123"))
    end

    it 'creates a new container' do
      post "/api/v1/devops/docker/hosts/#{host.id}/containers",
           params: { container: { name: 'test-container', image: 'nginx:latest' } },
           headers: headers, as: :json

      expect_success_response
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_create)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Image not found"))
      end

      it 'returns error' do
        post "/api/v1/devops/docker/hosts/#{host.id}/containers",
             params: { container: { name: 'test', image: 'nonexistent' } },
             headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/containers/:id/start' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:container) { create(:devops_docker_container, :stopped, docker_host: host) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_start).and_return(nil)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_inspect).and_return(mock_inspect_data)
    end

    it 'starts the container' do
      post "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}/start",
           headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['container']).to be_present
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/containers/:id/stop' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:container) { create(:devops_docker_container, :running, docker_host: host) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_stop).and_return(nil)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_inspect).and_return(
        mock_inspect_data.merge("State" => { "Status" => "exited", "StartedAt" => 1.hour.ago.iso8601, "FinishedAt" => Time.current.iso8601 })
      )
    end

    it 'stops the container' do
      post "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}/stop",
           headers: headers, as: :json

      expect_success_response
    end

    it 'accepts timeout parameter' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_stop)

      post "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}/stop",
           params: { timeout: 30 },
           headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/containers/:id/restart' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:container) { create(:devops_docker_container, :running, docker_host: host) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_restart).and_return(nil)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_inspect).and_return(mock_inspect_data)
    end

    it 'restarts the container' do
      post "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}/restart",
           headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'DELETE /api/v1/devops/docker/hosts/:host_id/containers/:id' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:container) { create(:devops_docker_container, docker_host: host) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_remove).and_return(nil)
    end

    it 'removes the container' do
      container_id = container.id

      delete "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container_id}",
             headers: headers, as: :json

      expect_success_response
      expect(Devops::DockerContainer.find_by(id: container_id)).to be_nil
    end

    it 'supports force removal' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_remove)
        .with(container.docker_container_id, force: true)

      delete "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}",
             params: { force: 'true' },
             headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/containers/:id/logs' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:container) { create(:devops_docker_container, :running, docker_host: host) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_logs)
        .and_return("2024-01-01 log line 1\n2024-01-01 log line 2")
    end

    it 'returns container logs' do
      get "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}/logs",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['logs']).to be_present
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/containers/:id/stats' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:container) { create(:devops_docker_container, :running, docker_host: host) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_stats)
        .and_return({ "cpu_stats" => {}, "memory_stats" => {} })
    end

    it 'returns container stats' do
      get "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}/stats",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['stats']).to be_present
    end
  end
end
