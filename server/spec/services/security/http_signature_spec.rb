# frozen_string_literal: true

require "rails_helper"
require "openssl"
require "base64"

RSpec.describe Security::HttpSignature do
  let(:secret) { "super-secret-signing-key" }
  let(:data)   { "POST\n/v1/webhooks\n{\"event\":\"ping\"}" }

  describe ".hexdigest" do
    it "computes a lowercase hex HMAC matching a hand-rolled OpenSSL digest" do
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, data)

      result = described_class.hexdigest(secret: secret, data: data)

      expect(result).to eq(expected)
      expect(result).to match(/\A[0-9a-f]+\z/)
    end

    it "honors an explicit algorithm" do
      expected = OpenSSL::HMAC.hexdigest("SHA512", secret, data)

      expect(described_class.hexdigest(secret: secret, data: data, algorithm: "sha512")).to eq(expected)
    end

    it "is deterministic for the same secret + data" do
      a = described_class.hexdigest(secret: secret, data: data)
      b = described_class.hexdigest(secret: secret, data: data)

      expect(a).to eq(b)
    end

    it "changes when the data changes" do
      a = described_class.hexdigest(secret: secret, data: data)
      b = described_class.hexdigest(secret: secret, data: "#{data}-tampered")

      expect(a).not_to eq(b)
    end
  end

  describe ".base64digest" do
    it "computes a strict (padded) Base64 HMAC matching a hand-rolled OpenSSL digest" do
      raw = OpenSSL::HMAC.digest("SHA256", secret, data)
      expected = Base64.strict_encode64(raw)

      result = described_class.base64digest(secret: secret, data: data)

      expect(result).to eq(expected)
      expect(result).not_to include("\n")
    end

    it "differs from the hex encoding of the same input" do
      hex = described_class.hexdigest(secret: secret, data: data)
      b64 = described_class.base64digest(secret: secret, data: data)

      expect(b64).not_to eq(hex)
    end
  end

  describe ".sign" do
    it "returns a bare hex digest by default (no prefix)" do
      expect(described_class.sign(secret: secret, data: data))
        .to eq(described_class.hexdigest(secret: secret, data: data))
    end

    it "prepends a '<prefix>=' scheme when given a prefix (Slack/Meta style)" do
      digest = described_class.hexdigest(secret: secret, data: data)

      expect(described_class.sign(secret: secret, data: data, prefix: "sha256"))
        .to eq("sha256=#{digest}")
    end

    it "supports :base64 encoding" do
      expect(described_class.sign(secret: secret, data: data, encoding: :base64))
        .to eq(described_class.base64digest(secret: secret, data: data))
    end
  end

  describe ".verify" do
    it "returns true for a signature it produced (hex)" do
      provided = described_class.sign(secret: secret, data: data)

      expect(described_class.verify(secret: secret, data: data, provided: provided)).to be(true)
    end

    it "returns true for a prefixed signature when the same prefix is supplied" do
      provided = described_class.sign(secret: secret, data: data, prefix: "v0")

      expect(
        described_class.verify(secret: secret, data: data, provided: provided, prefix: "v0")
      ).to be(true)
    end

    it "returns true for a base64 signature when verified with :base64" do
      provided = described_class.sign(secret: secret, data: data, encoding: :base64)

      expect(
        described_class.verify(secret: secret, data: data, provided: provided, encoding: :base64)
      ).to be(true)
    end

    it "returns false when the data was tampered with" do
      provided = described_class.sign(secret: secret, data: data)

      expect(
        described_class.verify(secret: secret, data: "#{data}!", provided: provided)
      ).to be(false)
    end

    it "returns false when the secret differs" do
      provided = described_class.sign(secret: secret, data: data)

      expect(
        described_class.verify(secret: "wrong-secret", data: data, provided: provided)
      ).to be(false)
    end

    it "returns false for a nil provided signature" do
      expect(described_class.verify(secret: secret, data: data, provided: nil)).to be(false)
    end
  end

  describe ".secure_compare" do
    it "returns true for identical strings" do
      expect(described_class.secure_compare("abc123", "abc123")).to be(true)
    end

    it "returns false for differing strings" do
      expect(described_class.secure_compare("abc123", "abc124")).to be(false)
    end

    it "returns false (never raises) when either argument is nil" do
      expect(described_class.secure_compare(nil, "abc")).to be(false)
      expect(described_class.secure_compare("abc", nil)).to be(false)
      expect(described_class.secure_compare(nil, nil)).to be(false)
    end

    it "coerces non-string arguments before comparing" do
      expect(described_class.secure_compare(123, "123")).to be(true)
    end
  end

  describe "algorithm normalization" do
    it "treats 'sha256', 'SHA-256' and 'hmac-sha256' as the same digest" do
      canonical = described_class.hexdigest(secret: secret, data: data, algorithm: "sha256")

      expect(described_class.hexdigest(secret: secret, data: data, algorithm: "SHA-256")).to eq(canonical)
      expect(described_class.hexdigest(secret: secret, data: data, algorithm: "hmac-sha256")).to eq(canonical)
    end

    it "raises ArgumentError for an unsupported algorithm rather than silently downgrading" do
      expect do
        described_class.hexdigest(secret: secret, data: data, algorithm: "md5")
      end.to raise_error(ArgumentError, /Unsupported HMAC algorithm/)
    end
  end
end
