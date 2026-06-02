# frozen_string_literal: true

require "rails_helper"
require "openssl"

RSpec.describe Security::MtlsClientVerifier do
  # Build a self-signed Ed25519 CA + a leaf it signs. Mirrors how
  # InternalCaService issues, but inline so this core spec stays independent of
  # the system extension.
  def build_ca(cn)
    key  = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 1
    cert.not_before = Time.now - 3600
    cert.not_after  = Time.now + 3600
    cert.subject    = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer     = cert.subject
    cert.public_key = key
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, nil)
    [ key, cert ]
  end

  def sign_leaf(cn, ca_key, ca_cert, not_after: Time.now + 3600)
    key  = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 2
    cert.not_before = Time.now - 3600
    cert.not_after  = not_after
    cert.subject    = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer     = ca_cert.subject
    cert.public_key = key
    cert.sign(ca_key, nil)
    cert
  end

  let(:our_ca)   { build_ca("Powernode Internal CA") }
  let(:our_key)  { our_ca[0] }
  let(:our_cert) { our_ca[1] }

  it "verifies a leaf signed by the expected anchor and returns its CN" do
    leaf = sign_leaf("fed:abc-123", our_key, our_cert)
    result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ our_cert.to_pem ])

    expect(result.verified?).to be(true)
    expect(result.subject_cn).to eq("fed:abc-123")
  end

  it "REJECTS a leaf signed by a foreign CA (impersonation guard)" do
    foreign_key, foreign_cert = build_ca("Powernode Internal CA") # same CN, different key!
    leaf = sign_leaf("node-instance-uuid", foreign_key, foreign_cert)

    # Anchor is OUR CA; the leaf was signed by the foreign CA that merely
    # cloned our CN — must fail on the SIGNATURE, not be fooled by the name.
    result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ our_cert.to_pem ])

    expect(result.verified?).to be(false)
    expect(result.error).to be_present
  end

  it "rejects an expired leaf" do
    leaf = sign_leaf("fed:expired", our_key, our_cert, not_after: Time.now - 60)
    result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ our_cert.to_pem ])
    expect(result.verified?).to be(false)
  end

  it "rejects a malformed cert PEM" do
    result = described_class.verify(cert_pem: "not a cert", anchors: [ our_cert.to_pem ])
    expect(result.verified?).to be(false)
    expect(result.error).to match(/malformed/)
  end

  it "rejects when no client certificate is presented" do
    result = described_class.verify(cert_pem: "", anchors: [ our_cert.to_pem ])
    expect(result.verified?).to be(false)
  end

  it "fails closed when no usable trust anchor is supplied" do
    leaf = sign_leaf("fed:abc", our_key, our_cert)
    result = described_class.verify(cert_pem: leaf.to_pem, anchors: [ "garbage" ])
    expect(result.verified?).to be(false)
    expect(result.error).to match(/no usable trust anchor/)
  end
end
