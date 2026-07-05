# frozen_string_literal: true

require "spec_helper"

RSpec.describe Docker::HealthCheckJob do
  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:logger).and_return(Logger.new(nil))
  end

  describe "#execute" do
    let(:host_data) do
      [{ "id" => "host-uuid-1", "name" => "docker-host-1" }]
    end
    let(:connection_data) do
      { "host_id" => "host-uuid-1", "api_endpoint" => "https://docker-host-1:2376", "api_version" => "v1.45",
        "encrypted_tls_credentials" => nil, "encryption_key_id" => nil, "tls_verify" => true }
    end

    context "when host is healthy" do
      let(:docker_client) { instance_double(Faraday::Connection) }
      let(:ping_response) { instance_double(Faraday::Response, success?: true) }
      let(:info_response) do
        instance_double(Faraday::Response, success?: true, body: {
          "MemTotal" => 8_000_000_000,
          "MemFree" => 4_000_000_000,
          "MemoryLimit" => true
        }.to_json)
      end

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/devops/docker/hosts", auto_sync: true)
          .and_return({ "data" => { "hosts" => host_data } })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/devops/docker/hosts/host-uuid-1/connection")
          .and_return({ "data" => { "connection" => connection_data } })
        allow(Faraday).to receive(:new).and_return(docker_client)
        allow(docker_client).to receive(:get).with("/_ping").and_return(ping_response)
        allow(docker_client).to receive(:get).with("/v1.45/info").and_return(info_response)
        allow(api_client).to receive(:post)
      end

      it "reports success" do
        job.execute

        expect(api_client).to have_received(:post)
          .with("/api/v1/internal/devops/docker/hosts/host-uuid-1/health_results", hash_including(status: "healthy"))
      end
    end

    context "when host ping fails" do
      let(:docker_client) { instance_double(Faraday::Connection) }
      let(:ping_response) { instance_double(Faraday::Response, success?: false, status: 503) }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/devops/docker/hosts", auto_sync: true)
          .and_return({ "data" => { "hosts" => host_data } })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/devops/docker/hosts/host-uuid-1/connection")
          .and_return({ "data" => { "connection" => connection_data } })
        allow(Faraday).to receive(:new).and_return(docker_client)
        allow(docker_client).to receive(:get).with("/_ping").and_return(ping_response)
        allow(api_client).to receive(:post)
      end

      it "reports failure with alerts" do
        job.execute

        expect(api_client).to have_received(:post)
          .with("/api/v1/internal/devops/docker/hosts/host-uuid-1/health_results", hash_including(status: "unhealthy"))
      end
    end

    context "when no hosts are available" do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/devops/docker/hosts", auto_sync: true)
          .and_return({ "data" => { "hosts" => [] } })
      end

      it "completes without error" do
        expect { job.execute }.not_to raise_error
      end
    end

    context "when connection fails" do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/devops/docker/hosts", auto_sync: true)
          .and_return({ "data" => { "hosts" => host_data } })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/devops/docker/hosts/host-uuid-1/connection")
          .and_return({ "data" => { "connection" => connection_data } })
        allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed.new("Connection refused"))
        allow(api_client).to receive(:post)
      end

      it "handles failure gracefully and reports unhealthy" do
        expect { job.execute }.not_to raise_error

        expect(api_client).to have_received(:post)
          .with("/api/v1/internal/devops/docker/hosts/host-uuid-1/health_results", hash_including(status: "unhealthy"))
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

  # #execute above stubs Faraday.new outright, so it never exercises this
  # job's own #build_docker_client (distinct from DockerClientConcern's
  # shared version — see docker_client_concern_spec.rb for that one). Build a
  # real Faraday::Connection here to confirm it targets the real api_endpoint
  # host/port/scheme and does NOT bake an API version segment into base_url
  # (unlike the shared concern method), since this job calls both an
  # unversioned endpoint (/_ping) and a versioned one (/v1.45/info).
  describe "#build_docker_client" do
    let(:connection) do
      {
        "host_id" => "host-uuid-1",
        "api_endpoint" => "https://docker-host-1:2376",
        "encrypted_tls_credentials" => nil,
        "tls_verify" => true
      }
    end

    it "targets the real api_endpoint host/port with no version segment in base_url" do
      client = job.send(:build_docker_client, connection)

      expect(client.url_prefix.host).to eq("docker-host-1")
      expect(client.url_prefix.port).to eq(2376)
      expect(client.url_prefix.scheme).to eq("https")
      expect(client.url_prefix.path).to eq("/")
    end
  end
end
