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
  end
end
