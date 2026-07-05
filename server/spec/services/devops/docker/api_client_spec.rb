# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe Devops::Docker::ApiClient do
  def build_ca(cn)
    key = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2; cert.serial = 1
    cert.not_before = Time.now - 3600; cert.not_after = Time.now + 3600
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}"); cert.issuer = cert.subject
    cert.public_key = key
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, nil)
    [ key, cert ]
  end

  let(:ca) { build_ca("Test Internal CA") }
  let(:client_key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:client_cert) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2; cert.serial = 2
    cert.not_before = Time.now - 3600; cert.not_after = Time.now + 3600
    cert.subject = OpenSSL::X509::Name.parse("/CN=platform-docker-client")
    cert.issuer = ca[1].subject
    cert.public_key = client_key
    cert.sign(ca[0], nil)
    cert
  end

  let(:account) { create(:account) }

  # System::DockerDaemonProvisionerService#issue_client_tls_pair! (Phase B
  # managed-host auto-registration) stores {ca_chain_pem:, client_cert_pem:,
  # client_key_pem:} into encrypted_tls_credentials — a DIFFERENT key shape
  # than the ca_cert/client_cert/client_key shape Devops::TlsCredentialParams
  # packs for externally-registered hosts. ApiClient must understand both.
  let(:provisioned_host) do
    create(:devops_docker_host, account: account,
      encrypted_tls_credentials: {
        ca_chain_pem: ca[1].to_pem,
        client_cert_pem: client_cert.to_pem,
        client_key_pem: client_key.private_to_pem
      }.to_json)
  end

  let(:external_host) do
    create(:devops_docker_host, account: account,
      encrypted_tls_credentials: {
        ca_cert: ca[1].to_pem,
        client_cert: client_cert.to_pem,
        client_key: client_key.private_to_pem
      }.to_json)
  end

  describe "TLS connection setup" do
    it "configures real client cert/key for provisioner-shaped credentials (ca_chain_pem/client_cert_pem/client_key_pem)" do
      client = described_class.new(provisioned_host)

      conn = nil
      expect { conn = client.send(:connection) }.not_to raise_error
      expect(conn.ssl.client_cert).to be_a(OpenSSL::X509::Certificate)
      expect(conn.ssl.client_key).to be_a(OpenSSL::PKey::PKey)
      expect(conn.ssl.ca_file).to be_present
    end

    it "still configures real client cert/key for legacy externally-registered credentials (ca_cert/client_cert/client_key)" do
      client = described_class.new(external_host)

      conn = nil
      expect { conn = client.send(:connection) }.not_to raise_error
      expect(conn.ssl.client_cert).to be_a(OpenSSL::X509::Certificate)
      expect(conn.ssl.client_key).to be_a(OpenSSL::PKey::PKey)
    end

    # Devops::TlsCredentialParams#build_tls_credentials packs
    # encrypted_tls_credentials whenever tls_ca.present? OR tls_cert.present?
    # OR tls_key.present? — so a host registered with only a CA cert
    # (server-verify-only TLS, no client mutual-auth cert/key) is a
    # legitimately reachable stored shape: {client_cert: nil, client_key: nil}.
    it "connects with server-verify-only TLS when only a CA cert is stored (no client cert/key)" do
      ca_only_host = create(:devops_docker_host, account: account,
        encrypted_tls_credentials: { ca_cert: ca[1].to_pem, client_cert: nil, client_key: nil }.to_json)
      client = described_class.new(ca_only_host)

      conn = nil
      expect { conn = client.send(:connection) }.not_to raise_error
      expect(conn.ssl.client_cert).to be_nil
      expect(conn.ssl.client_key).to be_nil
      expect(conn.ssl.ca_file).to be_present
    end

    it "raises a clear ConnectionError instead of silently degrading when only one of client_cert/client_key is stored" do
      asymmetric_host = create(:devops_docker_host, account: account,
        encrypted_tls_credentials: { ca_cert: ca[1].to_pem, client_cert: client_cert.to_pem, client_key: nil }.to_json)
      client = described_class.new(asymmetric_host)

      expect { client.send(:connection) }.to raise_error(Devops::Docker::ApiClient::ConnectionError, /client_cert and client_key must both be present/)
    end
  end

  # System::DockerDaemonProvisionerService always emits api_endpoint
  # "tcp://[<overlay>]:2376" (DockerHost's format validator explicitly
  # permits the tcp scheme). Faraday's net_http adapter only calls
  # configure_ssl when url.scheme == "https", so a raw tcp:// base_url
  # sends plaintext HTTP straight at dockerd's TLS-only 2376 listener —
  # every managed host would fail every call. External hosts happen to
  # work only because operators type https:// endpoints by convention.
  describe "tcp:// endpoint scheme normalization" do
    it "rewrites a TLS-verified tcp:// endpoint to https:// (managed-host shape)" do
      host = create(:devops_docker_host, account: account,
        api_endpoint: "tcp://[fd00::1]:2376", tls_verify: true)
      client = described_class.new(host)

      conn = client.send(:connection)
      expect(conn.scheme).to eq("https")
    end

    it "rewrites a tcp:// endpoint to https:// when client TLS credentials are present, even if tls_verify is false" do
      host = create(:devops_docker_host, account: account,
        tls_verify: false,
        api_endpoint: "tcp://[fd00::2]:2376",
        encrypted_tls_credentials: {
          ca_chain_pem: ca[1].to_pem,
          client_cert_pem: client_cert.to_pem,
          client_key_pem: client_key.private_to_pem
        }.to_json)
      client = described_class.new(host)

      conn = client.send(:connection)
      expect(conn.scheme).to eq("https")
    end

    it "leaves a genuinely plaintext tcp:// endpoint (no tls_verify, no credentials) as http://" do
      host = create(:devops_docker_host, account: account,
        api_endpoint: "tcp://[fd00::3]:2375", tls_verify: false)
      client = described_class.new(host)

      conn = client.send(:connection)
      expect(conn.scheme).to eq("http")
    end

    it "leaves an https:// endpoint untouched" do
      host = create(:devops_docker_host, account: account,
        api_endpoint: "https://docker-host.example.com:2376")
      client = described_class.new(host)

      conn = client.send(:connection)
      expect(conn.scheme).to eq("https")
    end
  end
end
