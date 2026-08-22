# frozen_string_literal: true

require "rails_helper"
require "openssl"

# IMP-01a02b0c — the identity primitive three subsystems now key on. A subject
# DN is a name a CA chooses for itself; only this value distinguishes two roots.
RSpec.describe Security::CaFingerprint do
  def build_root(cn)
    key  = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 1
    cert.not_before = Time.now - 60
    cert.not_after  = Time.now + 3600
    cert.subject    = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer     = cert.subject
    cert.public_key = key
    cert.sign(key, nil)
    cert
  end

  it "returns the DER SHA-256 as sha256:<64 lowercase hex>" do
    cert = build_root("Powernode Internal CA ops-hub")

    expect(described_class.of(cert))
      .to eq("sha256:#{OpenSSL::Digest::SHA256.hexdigest(cert.to_der)}")
    expect(described_class.of(cert)).to match(/\Asha256:[0-9a-f]{64}\z/)
  end

  it "separates two roots that share a subject DN but not a key" do
    a = build_root("Powernode Internal CA (local-dev)")
    b = build_root("Powernode Internal CA (local-dev)")

    expect(a.subject.to_s).to eq(b.subject.to_s)
    expect(described_class.of(a)).not_to eq(described_class.of(b))
  end

  it "is stable across a PEM round-trip, so a re-fetched CA matches" do
    cert = build_root("Powernode Internal CA ops-hub")

    expect(described_class.of_pem(cert.to_pem)).to eq(described_class.of(cert))
    expect(described_class.of_pem("#{cert.to_pem.strip}\n\n")).to eq(described_class.of(cert))
  end

  # Callers assembling trust material treat nil as "not identifiable" and KEEP
  # the material rather than dropping it, so these must not raise.
  it "returns nil rather than raising for anything that is not a certificate" do
    expect(described_class.of(nil)).to be_nil
    expect(described_class.of("not a cert")).to be_nil
    expect(described_class.of_pem(nil)).to be_nil
    expect(described_class.of_pem("")).to be_nil
    expect(described_class.of_pem("-----BEGIN CERTIFICATE-----\nnonsense\n-----END CERTIFICATE-----")).to be_nil
  end
end
