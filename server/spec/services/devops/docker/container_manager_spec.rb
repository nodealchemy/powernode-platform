# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::Docker::ContainerManager do
  let(:account) { create(:account) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }
  let(:user) { create(:user, account: account) }
  let(:manager) { described_class.new(host: host, user: user) }
  let(:container) { create(:devops_docker_container, :running, docker_host: host) }

  let(:mock_inspect_data) do
    {
      "Id" => container.docker_container_id,
      "Name" => "/#{container.name}",
      "Image" => "sha256:abc123",
      "State" => {
        "Status" => "running",
        "StartedAt" => Time.current.iso8601,
        "FinishedAt" => "0001-01-01T00:00:00Z"
      },
      "Config" => {
        "Image" => "nginx:latest",
        "Cmd" => ["nginx", "-g", "daemon off;"],
        "Labels" => {}
      },
      "RestartCount" => 0
    }
  end

  describe '#create_container' do
    let(:create_result) { { "Id" => "new_container_id", "Warnings" => [] } }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_create).and_return(create_result)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_inspect).and_return(
        mock_inspect_data.merge("Id" => "new_container_id", "Name" => "/test-app")
      )
    end

    it 'calls API to create container' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_create)
        .with("test-app", { Image: "nginx:latest" })
        .and_return(create_result)

      manager.create_container(name: "test-app", image: "nginx:latest")
    end

    it 'creates an activity record' do
      expect {
        manager.create_container(name: "test-app", image: "nginx:latest")
      }.to change(Devops::DockerActivity, :count).by(1)

      activity = Devops::DockerActivity.last
      expect(activity.activity_type).to eq("create")
      expect(activity.status).to eq("completed")
      expect(activity.triggered_by).to eq(user)
    end

    it 'syncs the new container' do
      manager.create_container(name: "test-app", image: "nginx:latest")

      new_container = host.docker_containers.find_by(docker_container_id: "new_container_id")
      expect(new_container).to be_present
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_create)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Image not found"))
      end

      it 'marks activity as failed and re-raises' do
        expect {
          manager.create_container(name: "test-app", image: "nonexistent:latest")
        }.to raise_error(Devops::Docker::ApiClient::ApiError)

        activity = Devops::DockerActivity.last
        expect(activity.status).to eq("failed")
      end
    end
  end

  describe '#start_container' do
    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_start).and_return(nil)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_inspect).and_return(mock_inspect_data)
    end

    it 'creates an activity and calls the API' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_start)
        .with(container.docker_container_id)

      manager.start_container(container)

      activity = Devops::DockerActivity.last
      expect(activity.activity_type).to eq("start")
      expect(activity.status).to eq("completed")
      expect(activity.container).to eq(container)
    end

    it 'refreshes container state' do
      manager.start_container(container)
      container.reload
      expect(container.last_seen_at).to be_present
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_start)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Container already started"))
      end

      it 'marks activity as failed and re-raises' do
        expect {
          manager.start_container(container)
        }.to raise_error(Devops::Docker::ApiClient::ApiError)

        activity = Devops::DockerActivity.last
        expect(activity.status).to eq("failed")
      end
    end
  end

  describe '#stop_container' do
    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_stop).and_return(nil)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_inspect).and_return(
        mock_inspect_data.merge("State" => { "Status" => "exited", "StartedAt" => 1.hour.ago.iso8601, "FinishedAt" => Time.current.iso8601 })
      )
    end

    it 'creates activity with timeout param' do
      manager.stop_container(container, timeout: 30)

      activity = Devops::DockerActivity.last
      expect(activity.activity_type).to eq("stop")
      expect(activity.params).to include("timeout" => 30)
      expect(activity.status).to eq("completed")
    end

    it 'calls API with container id and timeout' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_stop)
        .with(container.docker_container_id, 30)

      manager.stop_container(container, timeout: 30)
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_stop)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Container not running"))
      end

      it 'marks activity as failed' do
        expect {
          manager.stop_container(container)
        }.to raise_error(Devops::Docker::ApiClient::ApiError)

        expect(Devops::DockerActivity.last.status).to eq("failed")
      end
    end
  end

  describe '#restart_container' do
    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_restart).and_return(nil)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_inspect).and_return(mock_inspect_data)
    end

    it 'creates activity and calls API' do
      manager.restart_container(container)

      activity = Devops::DockerActivity.last
      expect(activity.activity_type).to eq("restart")
      expect(activity.status).to eq("completed")
    end

    it 'passes timeout to API' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_restart)
        .with(container.docker_container_id, 15)

      manager.restart_container(container, timeout: 15)
    end
  end

  describe '#remove_container' do
    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_remove).and_return(nil)
    end

    it 'removes container without force by default' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_remove)
        .with(container.docker_container_id, force: false)

      manager.remove_container(container)
    end

    it 'removes container with force when specified' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_remove)
        .with(container.docker_container_id, force: true)

      manager.remove_container(container, force: true)
    end

    it 'destroys the container record' do
      container_id = container.id

      manager.remove_container(container)

      expect(Devops::DockerContainer.find_by(id: container_id)).to be_nil
    end

    it 'creates activity record' do
      manager.remove_container(container)

      activity = Devops::DockerActivity.last
      expect(activity.activity_type).to eq("remove")
      expect(activity.status).to eq("completed")
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_remove)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Conflict"))
      end

      it 'marks activity as failed and does not destroy record' do
        expect {
          manager.remove_container(container)
        }.to raise_error(Devops::Docker::ApiClient::ApiError)

        expect(container.reload).to be_present
      end
    end
  end

  describe '#container_logs' do
    it 'passes through to API client' do
      opts = { tail: "50", stdout: true }
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_logs)
        .with(container.docker_container_id, opts)
        .and_return("log output")

      result = manager.container_logs(container, opts)
      expect(result).to eq("log output")
    end
  end

  describe '#container_stats' do
    it 'passes through to API client' do
      stats_data = { "cpu_stats" => {}, "memory_stats" => {} }
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:container_stats)
        .with(container.docker_container_id, stream: false)
        .and_return(stats_data)

      result = manager.container_stats(container)
      expect(result).to eq(stats_data)
    end
  end
end
