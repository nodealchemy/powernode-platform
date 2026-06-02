# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe Security::MtlsTrust do
  def build_ca(cn)
    key  = OpenSSL::PKey.generate_key("ED25519")
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

  def sign_leaf(cn, ca_key, ca_cert)
    key  = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2; cert.serial = 2
    cert.not_before = Time.now - 3600; cert.not_after = Time.now + 3600
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}"); cert.issuer = ca_cert.subject
    cert.public_key = key
    cert.sign(ca_key, nil)
    cert
  end

  let(:our) { build_ca("Powernode Internal CA") }

  # Override the provider, restoring whatever was injected at boot afterwards.
  around do |example|
    original = described_class.own_ca_provider
    described_class.own_ca_provider = -> { our[1].to_pem }
    example.run
    described_class.own_ca_provider = original
  end

  def req(headers)
    instance_double(ActionDispatch::Request, headers: headers)
  end

  describe ".own_ca_pem (injectable provider)" do
    it "returns the injected CA bundle" do
      expect(described_class.own_ca_pem).to eq(our[1].to_pem)
    end
  end

  describe ".verify_request" do
    it "returns the CN for a cert signed by our CA (full PEM header)" do
      leaf = sign_leaf("node-instance-9", our[0], our[1])
      r = req(described_class::PEM_HEADER => CGI.escape(leaf.to_pem))
      expect(described_class.verify_request(r)).to eq("node-instance-9")
    end

    it "reconstructs a bare-base64 forwarded cert (no BEGIN/END lines)" do
      leaf = sign_leaf("node-instance-9", our[0], our[1])
      bare = leaf.to_pem.gsub(/-----[A-Z ]+-----/, "").gsub(/\s+/, "")
      r = req(described_class::PEM_HEADER => CGI.escape(bare))
      expect(described_class.verify_request(r)).to eq("node-instance-9")
    end

    it "returns nil for a cert signed by a FOREIGN CA that cloned our CN" do
      foreign = build_ca("Powernode Internal CA")
      leaf = sign_leaf("node-instance-9", foreign[0], foreign[1])
      r = req(described_class::PEM_HEADER => CGI.escape(leaf.to_pem))
      expect(described_class.verify_request(r)).to be_nil
    end

    it "returns nil when neither a PEM nor an Info header is present" do
      expect(described_class.verify_request(req({}))).to be_nil
    end

    it "falls back to the proxy-verified Info CN when no PEM is forwarded" do
      # Pre-symmetric posture: Traefik's chain-check (our-CA-only bundle) is
      # authoritative, so the forwarded CN is trusted without a re-verify.
      r = req(described_class::SUBJECT_HEADER => CGI.escape(%(Subject="CN=node-instance-7")))
      expect(described_class.verify_request(r)).to eq("node-instance-7")
    end
  end

  describe ".client_cert_presented?" do
    it "distinguishes cert-present from no-cert (for the cable JWT fallthrough)" do
      expect(described_class.client_cert_presented?(req(described_class::PEM_HEADER => "x"))).to be(true)
      expect(described_class.client_cert_presented?(req(described_class::SUBJECT_HEADER => "y"))).to be(true)
      expect(described_class.client_cert_presented?(req({}))).to be(false)
    end
  end
end
