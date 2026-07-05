# frozen_string_literal: true

require "spec_helper"
require "openssl"

# Regression coverage for the shared Faraday client builder consumed by
# Docker::HostSyncJob, Swarm::ClusterSyncJob, Swarm::HealthCheckJob,
# Swarm::ServiceUpdateJob, and Swarm::StackDeployJob (Docker::HealthCheckJob
# keeps its own copy — see docker/health_check_job_spec.rb — but shares the
# same TLS-parsing helpers).
#
# The internal connection endpoints (Api::V1::Internal::Devops::DockerController
# #connection / SwarmController#connection) render {host_id/cluster_id:,
# api_endpoint:, api_version:, encrypted_tls_credentials:, encryption_key_id:,
# tls_verify:} — NOT the host/port/tls_enabled/client_cert/client_key shape
# #build_docker_client used to read, which produced an all-nil base_url
# ("http://:/") and never enabled TLS even for TLS-only hosts.
RSpec.describe DockerClientConcern do
  let(:including_class) do
    Class.new do
      include DockerClientConcern
      const_set(:DOCKER_API_VERSION, "v1.45")
      public :build_docker_client, :docker_path
    end
  end
  let(:instance) { including_class.new }

  def build_ca(cn)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = cert.subject
    cert.public_key = key
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    [ key, cert ]
  end

  let(:ca) { build_ca("Test Internal CA") }
  let(:client_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:client_cert) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.subject = OpenSSL::X509::Name.parse("/CN=worker-docker-client")
    cert.issuer = ca[1].subject
    cert.public_key = client_key
    cert.sign(ca[0], OpenSSL::Digest.new("SHA256"))
    cert
  end

  describe "#build_docker_client" do
    context "with the real (plaintext) internal API connection shape" do
      let(:connection) do
        {
          "host_id" => "host-1",
          "api_endpoint" => "http://docker-host-1:2376",
          "api_version" => "v1.45",
          "encrypted_tls_credentials" => nil,
          "encryption_key_id" => nil
        }
      end

      it "targets the real api_endpoint host/port instead of an all-nil URL" do
        client = instance.build_docker_client(connection)

        expect(client.url_prefix.host).to eq("docker-host-1")
        expect(client.url_prefix.port).to eq(2376)
        expect(client.url_prefix.scheme).to eq("http")
      end
    end

    context "with a TLS-enabled connection (legacy ca_cert/client_cert/client_key shape)" do
      let(:connection) do
        {
          "api_endpoint" => "https://docker-host-1:2376",
          "encrypted_tls_credentials" => {
            ca_cert: ca[1].to_pem,
            client_cert: client_cert.to_pem,
            client_key: client_key.private_to_pem
          }.to_json,
          "tls_verify" => true
        }
      end

      it "configures the real client cert/key/ca from encrypted_tls_credentials" do
        client = instance.build_docker_client(connection)

        expect(client.ssl.client_cert).to be_a(OpenSSL::X509::Certificate)
        expect(client.ssl.client_key).to be_a(OpenSSL::PKey::PKey)
        expect(client.ssl.ca_file).to be_present
        expect(client.ssl.verify).to be(true)
      end
    end

    context "with a managed-host credential shape (ca_chain_pem/client_cert_pem/client_key_pem)" do
      let(:connection) do
        {
          "api_endpoint" => "https://docker-host-1:2376",
          "encrypted_tls_credentials" => {
            ca_chain_pem: ca[1].to_pem,
            client_cert_pem: client_cert.to_pem,
            client_key_pem: client_key.private_to_pem
          }.to_json
        }
      end

      it "still configures a real client cert/key" do
        client = instance.build_docker_client(connection)

        expect(client.ssl.client_cert).to be_a(OpenSSL::X509::Certificate)
        expect(client.ssl.client_key).to be_a(OpenSSL::PKey::PKey)
      end
    end

    context "with a CA-only credential shape (server-verify-only TLS, no client cert/key)" do
      let(:connection) do
        {
          "api_endpoint" => "https://docker-host-1:2376",
          "encrypted_tls_credentials" => {
            ca_cert: ca[1].to_pem,
            client_cert: nil,
            client_key: nil
          }.to_json
        }
      end

      it "connects without raising, leaving client cert/key unset" do
        client = nil
        expect { client = instance.build_docker_client(connection) }.not_to raise_error
        expect(client.ssl.client_cert).to be_nil
        expect(client.ssl.client_key).to be_nil
        expect(client.ssl.ca_file).to be_present
      end
    end

    context "with an asymmetric credential shape (only one of client_cert/client_key stored)" do
      let(:connection) do
        {
          "api_endpoint" => "https://docker-host-1:2376",
          "encrypted_tls_credentials" => {
            ca_cert: ca[1].to_pem,
            client_cert: client_cert.to_pem,
            client_key: nil
          }.to_json
        }
      end

      it "raises a clear error instead of silently degrading to CA-only" do
        expect { instance.build_docker_client(connection) }.to raise_error(ArgumentError, /client_cert and client_key must both be present/)
      end
    end

    context "with a tcp:// endpoint (managed-host DOCKER_HOST convention)" do
      let(:connection) do
        {
          "api_endpoint" => "tcp://docker-host-1:2376",
          "encrypted_tls_credentials" => {
            ca_cert: ca[1].to_pem,
            client_cert: client_cert.to_pem,
            client_key: client_key.private_to_pem
          }.to_json
        }
      end

      it "rewrites tcp:// to https:// when TLS credentials are present" do
        client = instance.build_docker_client(connection)

        expect(client.url_prefix.scheme).to eq("https")
      end
    end

    context "with a plaintext tcp:// endpoint (no tls_verify, no credentials)" do
      let(:connection) do
        { "api_endpoint" => "tcp://docker-host-1:2375", "tls_verify" => false }
      end

      it "leaves it as http://" do
        client = instance.build_docker_client(connection)

        expect(client.url_prefix.scheme).to eq("http")
      end
    end
  end

  # Regression coverage for IMP-d03772860f73: #build_docker_client bakes
  # DOCKER_API_VERSION into base_url, but every job historically issued
  # requests with an absolute (leading-slash) path — which Faraday resolves
  # by replacing base_url's path entirely (RFC 3986), silently dropping the
  # version segment. #docker_path is the fix: it strips the leading slash so
  # the path is appended instead. These specs hit a real Faraday connection
  # through WebMock (not an instance_double) so the actual URL join is what's
  # under test, not an assumption about how Faraday behaves.
  describe "#docker_path" do
    it "strips a leading slash so the path is appended to base_url instead of replacing it" do
      expect(instance.docker_path("/nodes")).to eq("nodes")
    end

    it "leaves a path with no leading slash unchanged" do
      expect(instance.docker_path("nodes")).to eq("nodes")
    end
  end

  describe "request routing through a client built by #build_docker_client" do
    let(:connection) { { "api_endpoint" => "https://docker-host-1:2376", "tls_verify" => false } }
    let(:client) { instance.build_docker_client(connection) }

    it "drops the baked-in version segment when the request path is absolute (the bug)" do
      stub_request(:get, "https://docker-host-1:2376/nodes").to_return(status: 200, body: "[]")

      response = client.get("/nodes")

      expect(response.status).to eq(200)
      expect(a_request(:get, "https://docker-host-1:2376/v1.45/nodes")).not_to have_been_made
    end

    it "preserves the baked-in version segment when the path is routed through #docker_path" do
      stub_request(:get, "https://docker-host-1:2376/v1.45/nodes").to_return(status: 200, body: "[]")

      response = client.get(instance.docker_path("/nodes"))

      expect(response.status).to eq(200)
    end
  end
end
