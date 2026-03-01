# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::Docker::HostManager do
  let(:account) { create(:account) }
  let(:manager) { described_class.new(account: account) }
  let(:host) { create(:devops_docker_host, account: account) }

  let(:mock_info) do
    {
      "ServerVersion" => "24.0.7",
      "OperatingSystem" => "Ubuntu 22.04",
      "Architecture" => "x86_64",
      "KernelVersion" => "5.15.0-91-generic",
      "MemTotal" => 8_589_934_592,
      "NCPU" => 4,
      "Containers" => 5,
      "Images" => 12,
      "ApiVersion" => "1.45"
    }
  end

  describe '#register_host' do
    let(:host_params) do
      {
        name: "Test Docker Host",
        api_endpoint: "https://docker.example.com:2376",
        environment: "development"
      }
    end

    context 'when connection succeeds' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping).and_return("OK")
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:info).and_return(mock_info)
      end

      it 'creates a new host with connected status' do
        host = manager.register_host(host_params)

        expect(host).to be_persisted
        expect(host.name).to eq("Test Docker Host")
        expect(host.status).to eq("connected")
        expect(host.docker_version).to eq("24.0.7")
        expect(host.os_type).to eq("Ubuntu 22.04")
        expect(host.architecture).to eq("x86_64")
        expect(host.cpu_count).to eq(4)
        expect(host.memory_bytes).to eq(8_589_934_592)
        expect(host.container_count).to eq(5)
        expect(host.image_count).to eq(12)
      end

      it 'sets last_synced_at' do
        host = manager.register_host(host_params)
        expect(host.last_synced_at).to be_present
      end
    end

    context 'when connection fails' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Connection refused"))
      end

      it 'creates host with error status' do
        host = manager.register_host(host_params)

        expect(host).to be_persisted
        expect(host.status).to eq("error")
      end
    end

    context 'with invalid params' do
      it 'raises RecordInvalid for missing name' do
        expect {
          manager.register_host(api_endpoint: "https://docker.example.com:2376", environment: "development")
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe '#test_connection' do
    context 'when connection succeeds' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping).and_return("OK")
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:info).and_return(mock_info)
      end

      it 'returns success result with host info' do
        result = manager.test_connection(host)

        expect(result[:success]).to be true
        expect(result[:server_version]).to eq("24.0.7")
        expect(result[:os]).to eq("Ubuntu 22.04")
        expect(result[:cpus]).to eq(4)
      end

      it 'calls record_success! on host' do
        expect(host).to receive(:record_success!)
        manager.test_connection(host)
      end
    end

    context 'when connection fails' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping)
          .and_raise(Devops::Docker::ApiClient::ConnectionError.new("Connection refused"))
      end

      it 'returns failure result' do
        result = manager.test_connection(host)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Connection failed")
      end

      it 'calls record_failure! on host' do
        expect(host).to receive(:record_failure!)
        manager.test_connection(host)
      end
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Unauthorized"))
      end

      it 'returns failure result' do
        result = manager.test_connection(host)

        expect(result[:success]).to be false
        expect(result[:error]).to eq("Unauthorized")
      end
    end
  end

  describe '#sync_host' do
    let(:mock_containers) do
      [
        {
          "Id" => "abc123",
          "Names" => ["/nginx"],
          "Image" => "nginx:latest",
          "ImageID" => "sha256:def456",
          "State" => "running",
          "Status" => "Up 2 hours",
          "Ports" => [{ "IP" => "0.0.0.0", "PrivatePort" => 80, "PublicPort" => 8080, "Type" => "tcp" }],
          "Mounts" => [],
          "NetworkSettings" => { "Networks" => {} },
          "Labels" => {},
          "Command" => "nginx -g 'daemon off;'"
        }
      ]
    end

    let(:mock_images) do
      [
        {
          "Id" => "sha256:img001",
          "RepoTags" => ["nginx:latest"],
          "RepoDigests" => [],
          "Size" => 187_000_000,
          "VirtualSize" => 187_000_000,
          "Containers" => 1,
          "Labels" => {},
          "Created" => Time.current.to_i
        }
      ]
    end

    context 'when sync succeeds' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_list).and_return(mock_containers)
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_list).and_return(mock_images)
      end

      it 'upserts containers' do
        result = manager.sync_host(host)

        expect(result[:success]).to be true
        expect(result[:containers]).to eq(1)
        expect(host.docker_containers.count).to eq(1)

        container = host.docker_containers.first
        expect(container.docker_container_id).to eq("abc123")
        expect(container.name).to eq("nginx")
        expect(container.state).to eq("running")
      end

      it 'upserts images' do
        result = manager.sync_host(host)

        expect(result[:images]).to eq(1)
        expect(host.docker_images.count).to eq(1)

        image = host.docker_images.first
        expect(image.docker_image_id).to eq("sha256:img001")
        expect(image.repo_tags).to eq(["nginx:latest"])
      end

      it 'removes stale containers not in remote' do
        create(:devops_docker_container, docker_host: host, docker_container_id: "stale_id")

        manager.sync_host(host)

        expect(host.docker_containers.find_by(docker_container_id: "stale_id")).to be_nil
      end

      it 'removes stale images not in remote' do
        create(:devops_docker_image, docker_host: host, docker_image_id: "sha256:stale")

        manager.sync_host(host)

        expect(host.docker_images.find_by(docker_image_id: "sha256:stale")).to be_nil
      end

      it 'updates host counts and sync timestamp' do
        manager.sync_host(host)

        host.reload
        expect(host.container_count).to eq(1)
        expect(host.image_count).to eq(1)
        expect(host.last_synced_at).to be_present
        expect(host.status).to eq("connected")
        expect(host.consecutive_failures).to eq(0)
      end
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_list)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Connection timeout"))
      end

      it 'returns failure result' do
        result = manager.sync_host(host)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Connection timeout")
      end

      it 'records failure on host' do
        expect(host).to receive(:record_failure!)
        manager.sync_host(host)
      end
    end
  end

  describe '#remove_host' do
    it 'destroys the host' do
      host_id = host.id
      manager.remove_host(host)

      expect(Devops::DockerHost.find_by(id: host_id)).to be_nil
    end

    it 'returns success' do
      result = manager.remove_host(host)
      expect(result[:success]).to be true
    end

    it 'destroys associated containers and images' do
      create(:devops_docker_container, docker_host: host)
      create(:devops_docker_image, docker_host: host)

      manager.remove_host(host)

      expect(Devops::DockerContainer.where(docker_host_id: host.id).count).to eq(0)
      expect(Devops::DockerImage.where(docker_host_id: host.id).count).to eq(0)
    end
  end
end
