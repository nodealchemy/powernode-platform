# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docker::HostSyncJob do
  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:logger).and_return(Logger.new(nil))
  end

  describe "#execute" do
    let(:host_data) do
      [{ "id" => "host-uuid-1", "name" => "docker-host-1", "api_endpoint" => "https://docker-host-1:2376", "api_version" => "v1.45" }]
    end
    let(:connection_data) do
      { "host" => "docker-host-1", "port" => "2376", "tls_enabled" => false }
    end

    context "when hosts are available" do
      let(:docker_client) { instance_double(Faraday::Connection) }
      let(:containers_response) { instance_double(Faraday::Response, success?: true, body: "[]") }
      let(:images_response) { instance_double(Faraday::Response, success?: true, body: "[]") }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/docker/hosts", auto_sync: true)
          .and_return({ "data" => { "hosts" => host_data } })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/docker/hosts/host-uuid-1/connection")
          .and_return({ "data" => { "connection" => connection_data } })
        allow(Faraday).to receive(:new).and_return(docker_client)
        allow(docker_client).to receive(:get).with("/containers/json?all=true").and_return(containers_response)
        allow(docker_client).to receive(:get).with("/images/json").and_return(images_response)
        allow(api_client).to receive(:post)
          .with("/api/v1/internal/docker/hosts/host-uuid-1/sync_results", hash_including(:containers, :images, :synced_at))
          .and_return({ "data" => { "status" => "ok" } })
      end

      it "syncs all hosts" do
        expect { job.execute }.not_to raise_error
      end

      it "posts sync results to the backend" do
        job.execute

        expect(api_client).to have_received(:post)
          .with("/api/v1/internal/docker/hosts/host-uuid-1/sync_results", hash_including(:containers, :images))
      end
    end

    context "when no hosts are available" do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/docker/hosts", auto_sync: true)
          .and_return({ "data" => { "hosts" => [] } })
      end

      it "completes without error" do
        expect { job.execute }.not_to raise_error
      end
    end

    context "when a host sync fails" do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/docker/hosts", auto_sync: true)
          .and_return({ "data" => { "hosts" => host_data } })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/docker/hosts/host-uuid-1/connection")
          .and_return({ "data" => { "connection" => connection_data } })
        allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed.new("Connection refused"))
      end

      it "handles failure gracefully" do
        expect { job.execute }.not_to raise_error
      end
    end
  end

  describe "job configuration" do
    it "uses the devops_default queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("devops_default")
    end

    it "retries up to 2 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(2)
    end
  end
end
