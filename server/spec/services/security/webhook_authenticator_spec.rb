# frozen_string_literal: true

# Characterization spec for Security::WebhookAuthenticator.
#
# This is a PURE crypto helper (no DB / no network), so these examples exercise the
# real code paths directly. Every secret, key, signature, and token used here is
# EPHEMERAL and generated in-test via SecureRandom / an in-memory Ed25519 keypair.
# No real credentials are involved, and NO secret/key/signature value is ever
# printed, logged, or otherwise emitted (no puts / p / Rails.logger calls below).
#
# Intent: document CURRENT behavior (happy paths + security-failure paths), not to
# assert what the service "should" do. See the NOTE comments for behaviors that are
# surprising but characterized as-is.

require "rails_helper"
require "openssl"
require "ed25519"

RSpec.describe Security::WebhookAuthenticator do
  # Ephemeral, in-test material only.
  let(:secret)  { SecureRandom.hex(32) }
  let(:payload) { %({"event":"ping","id":"#{SecureRandom.uuid}"}) }

  # A valid HMAC-SHA256 signature for the let(:payload) / let(:secret) above,
  # computed with the same algorithm the service uses, including the default
  # "sha256=" header prefix.
  def valid_hmac_signature(p: payload, s: secret, prefix: "sha256=")
    "#{prefix}#{OpenSSL::HMAC.hexdigest('SHA256', s, p)}"
  end

  describe ".verify_hmac_sha256!" do
    context "with a valid signature" do
      it "returns true without raising" do
        sig = valid_hmac_signature

        expect(
          described_class.verify_hmac_sha256!(payload: payload, signature: sig, secret: secret)
        ).to be(true)
      end

      it "accepts a custom header_prefix when the signature uses it" do
        sig = valid_hmac_signature(prefix: "v1=")

        expect(
          described_class.verify_hmac_sha256!(
            payload: payload, signature: sig, secret: secret, header_prefix: "v1="
          )
        ).to be(true)
      end
    end

    context "with a tampered payload" do
      it "raises AuthenticationError" do
        sig = valid_hmac_signature # computed over the untampered payload

        expect {
          described_class.verify_hmac_sha256!(
            payload: "#{payload}-tampered", signature: sig, secret: secret
          )
        }.to raise_error(described_class::AuthenticationError, "Invalid HMAC-SHA256 signature")
      end
    end

    context "with a wrong/forged signature of the correct length" do
      it "raises AuthenticationError" do
        # Same length as a real "sha256=<64 hex>" signature, but wrong content.
        forged = "sha256=#{'a' * 64}"

        expect {
          described_class.verify_hmac_sha256!(payload: payload, signature: forged, secret: secret)
        }.to raise_error(described_class::AuthenticationError, "Invalid HMAC-SHA256 signature")
      end
    end

    context "with the wrong secret" do
      it "raises AuthenticationError" do
        sig = valid_hmac_signature(s: SecureRandom.hex(32)) # signed with a different secret

        expect {
          described_class.verify_hmac_sha256!(payload: payload, signature: sig, secret: secret)
        }.to raise_error(described_class::AuthenticationError, "Invalid HMAC-SHA256 signature")
      end
    end

    context "with a signature missing the expected header_prefix" do
      it "raises AuthenticationError (prefix is part of the compared string)" do
        # Bare hex digest, no "sha256=" prefix -> expected string includes the prefix,
        # so the comparison fails.
        bare = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)

        expect {
          described_class.verify_hmac_sha256!(payload: payload, signature: bare, secret: secret)
        }.to raise_error(described_class::AuthenticationError)
      end
    end

    context "with blank inputs" do
      it "returns false (not raise) when payload is blank" do
        expect(
          described_class.verify_hmac_sha256!(payload: "", signature: valid_hmac_signature, secret: secret)
        ).to be(false)
      end

      it "returns false (not raise) when signature is blank" do
        expect(
          described_class.verify_hmac_sha256!(payload: payload, signature: "", secret: secret)
        ).to be(false)
      end

      it "returns false (not raise) when secret is blank" do
        expect(
          described_class.verify_hmac_sha256!(payload: payload, signature: valid_hmac_signature, secret: "")
        ).to be(false)
      end
    end

    it "delegates the comparison to a constant-time comparator" do
      # Characterize that verification routes through secure_compare rather than ==.
      # We assert the comparator is consulted with the expected + provided signatures.
      sig = valid_hmac_signature
      expected = sig.dup

      expect(described_class).to receive(:secure_compare)
        .with(expected, sig)
        .and_call_original

      described_class.verify_hmac_sha256!(payload: payload, signature: sig, secret: secret)
    end
  end

  describe ".verify_ed25519!" do
    let(:signing_key) { Ed25519::SigningKey.generate }       # ephemeral, in-memory keypair
    let(:verify_key)  { signing_key.verify_key }
    let(:public_key_hex) { verify_key.to_bytes.unpack1("H*") }
    let(:timestamp) { Time.current.to_i.to_s }

    # The service verifies the signature over "#{timestamp}#{payload}".
    def sign_message(p: payload, ts: timestamp, sk: signing_key)
      sk.sign("#{ts}#{p}").unpack1("H*")
    end

    context "with a valid signature and fresh timestamp" do
      it "returns true without raising" do
        sig_hex = sign_message

        expect(
          described_class.verify_ed25519!(
            payload: payload, signature: sig_hex, timestamp: timestamp, public_key: public_key_hex
          )
        ).to be(true)
      end
    end

    context "with a signature over the wrong message" do
      it "raises AuthenticationError (signature does not match payload+timestamp)" do
        sig_hex = sign_message(p: "#{payload}-tampered")

        expect {
          described_class.verify_ed25519!(
            payload: payload, signature: sig_hex, timestamp: timestamp, public_key: public_key_hex
          )
        }.to raise_error(described_class::AuthenticationError, /Invalid Ed25519 signature/)
      end
    end

    context "with a signature from a different (wrong) key" do
      it "raises AuthenticationError" do
        other_key = Ed25519::SigningKey.generate
        sig_hex = sign_message(sk: other_key) # signed by other_key, verified with our key

        expect {
          described_class.verify_ed25519!(
            payload: payload, signature: sig_hex, timestamp: timestamp, public_key: public_key_hex
          )
        }.to raise_error(described_class::AuthenticationError, /Invalid Ed25519 signature/)
      end
    end

    context "with a malformed (non-hex) signature" do
      it "raises AuthenticationError" do
        expect {
          described_class.verify_ed25519!(
            payload: payload, signature: "not-hex-zzz", timestamp: timestamp, public_key: public_key_hex
          )
        }.to raise_error(described_class::AuthenticationError, /Invalid Ed25519 signature/)
      end
    end

    context "with a stale timestamp" do
      it "raises AuthenticationError from the timestamp check before signature verification" do
        stale_ts = (Time.current.to_i - (described_class::MAX_TIME_SKEW + 60)).to_s
        # Even a valid signature over the stale message must be rejected on timestamp.
        sig_hex = sign_message(ts: stale_ts)

        expect {
          described_class.verify_ed25519!(
            payload: payload, signature: sig_hex, timestamp: stale_ts, public_key: public_key_hex
          )
        }.to raise_error(described_class::AuthenticationError, "Request timestamp too old or in the future")
      end
    end

    context "with blank inputs" do
      it "returns false (not raise) when payload is blank" do
        expect(
          described_class.verify_ed25519!(
            payload: "", signature: sign_message, timestamp: timestamp, public_key: public_key_hex
          )
        ).to be(false)
      end

      it "returns false (not raise) when signature is blank" do
        expect(
          described_class.verify_ed25519!(
            payload: payload, signature: "", timestamp: timestamp, public_key: public_key_hex
          )
        ).to be(false)
      end

      it "returns false (not raise) when public_key is blank" do
        expect(
          described_class.verify_ed25519!(
            payload: payload, signature: sign_message, timestamp: timestamp, public_key: ""
          )
        ).to be(false)
      end
    end
  end

  describe ".verify_timestamp!" do
    it "returns true for the current timestamp" do
      expect(described_class.verify_timestamp!(Time.current.to_i)).to be(true)
    end

    it "accepts an integer timestamp at the lower skew boundary (now - MAX_TIME_SKEW)" do
      ts = Time.current.to_i - described_class::MAX_TIME_SKEW

      expect(described_class.verify_timestamp!(ts)).to be(true)
    end

    it "accepts a string timestamp" do
      expect(described_class.verify_timestamp!(Time.current.to_i.to_s)).to be(true)
    end

    it "raises AuthenticationError for a timestamp older than MAX_TIME_SKEW" do
      ts = Time.current.to_i - (described_class::MAX_TIME_SKEW + 1)

      expect {
        described_class.verify_timestamp!(ts)
      }.to raise_error(described_class::AuthenticationError, "Request timestamp too old or in the future")
    end

    it "raises AuthenticationError for a timestamp too far in the future" do
      ts = Time.current.to_i + (described_class::MAX_TIME_SKEW + 1)

      expect {
        described_class.verify_timestamp!(ts)
      }.to raise_error(described_class::AuthenticationError, "Request timestamp too old or in the future")
    end

    it "honors an explicit max_skew override" do
      ts = Time.current.to_i - 30

      # Within default skew, but outside a tighter 10s override.
      expect(described_class.verify_timestamp!(ts, max_skew: 60)).to be(true)
      expect {
        described_class.verify_timestamp!(ts, max_skew: 10)
      }.to raise_error(described_class::AuthenticationError)
    end

    it "returns nil (no-op) for a blank timestamp" do
      # NOTE: a blank timestamp short-circuits the replay-protection check.
      expect(described_class.verify_timestamp!(nil)).to be_nil
      expect(described_class.verify_timestamp!("")).to be_nil
    end
  end

  describe ".verify_telegram_token!" do
    let(:token) { SecureRandom.hex(24) } # ephemeral secret token

    it "returns true when the request token matches the expected token" do
      expect(
        described_class.verify_telegram_token!(request_token: token, expected_token: token.dup)
      ).to be(true)
    end

    it "raises AuthenticationError when the tokens differ" do
      expect {
        described_class.verify_telegram_token!(
          request_token: SecureRandom.hex(24), expected_token: token
        )
      }.to raise_error(described_class::AuthenticationError, "Invalid Telegram secret token")
    end

    it "returns false (not raise) when the request token is blank" do
      expect(
        described_class.verify_telegram_token!(request_token: "", expected_token: token)
      ).to be(false)
    end

    it "returns false (not raise) when the expected token is blank" do
      expect(
        described_class.verify_telegram_token!(request_token: token, expected_token: "")
      ).to be(false)
    end

    it "delegates the comparison to a constant-time comparator" do
      expected = token.dup

      expect(described_class).to receive(:secure_compare)
        .with(token, expected)
        .and_call_original

      described_class.verify_telegram_token!(request_token: token, expected_token: expected)
    end
  end

  describe ".sign_webhook" do
    it "produces a sha256-prefixed signature that verify_hmac_sha256! accepts (round-trip)" do
      signature = described_class.sign_webhook(payload: payload, secret: secret)

      expect(signature).to start_with("sha256=")
      expect(
        described_class.verify_hmac_sha256!(payload: payload, signature: signature, secret: secret)
      ).to be(true)
    end

    it "matches a hand-rolled OpenSSL HMAC digest" do
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}"

      expect(described_class.sign_webhook(payload: payload, secret: secret)).to eq(expected)
    end

    it "raises ArgumentError for an unsupported algorithm" do
      expect {
        described_class.sign_webhook(payload: payload, secret: secret, algorithm: :hmac_sha512)
      }.to raise_error(ArgumentError, /Unsupported algorithm/)
    end
  end

  describe ".generate_token" do
    it "returns a non-blank urlsafe-base64 token" do
      token = described_class.generate_token

      expect(token).to be_present
      expect(token).to match(%r{\A[A-Za-z0-9_-]+\z}) # urlsafe base64 alphabet, no padding
    end

    it "honors the requested byte length (urlsafe_base64(n) encodes n random bytes)" do
      # SecureRandom.urlsafe_base64(n) returns ceil(4*n/3) chars for n random bytes.
      token = described_class.generate_token(length: 16)

      expect(token.length).to eq(((4.0 * 16) / 3).ceil)
    end

    it "returns unique tokens across calls" do
      expect(described_class.generate_token).not_to eq(described_class.generate_token)
    end
  end

  describe ".valid_hmac_sha256?" do
    it "returns true for a valid signature" do
      expect(
        described_class.valid_hmac_sha256?(payload: payload, signature: valid_hmac_signature, secret: secret)
      ).to be(true)
    end

    it "returns false (does not raise) for a forged signature" do
      forged = valid_hmac_signature(p: "#{payload}x")

      expect(
        described_class.valid_hmac_sha256?(payload: payload, signature: forged, secret: secret)
      ).to be(false)
    end

    it "returns false for blank inputs" do
      expect(described_class.valid_hmac_sha256?(payload: payload, signature: "", secret: secret)).to be(false)
      expect(described_class.valid_hmac_sha256?(payload: "", signature: valid_hmac_signature, secret: secret)).to be(false)
      expect(described_class.valid_hmac_sha256?(payload: payload, signature: valid_hmac_signature, secret: "")).to be(false)
    end

    it "honors a custom (or empty) header_prefix" do
      bare = valid_hmac_signature(prefix: "")

      expect(
        described_class.valid_hmac_sha256?(payload: payload, signature: bare, secret: secret, header_prefix: "")
      ).to be(true)
      expect(
        described_class.valid_hmac_sha256?(payload: payload, signature: bare, secret: secret)
      ).to be(false)
    end
  end

  describe ".sign_timestamped / .verify_timestamped" do
    it "produces a t=<ts>,v1=<hex> header that round-trips through verify_timestamped" do
      header = described_class.sign_timestamped(payload: payload, secret: secret)

      expect(header).to match(/\At=\d+,v1=[0-9a-f]{64}\z/)
      expect(
        described_class.verify_timestamped(payload: payload, header: header, secret: secret)
      ).to be(true)
    end

    it "rejects a header signed with a different secret" do
      header = described_class.sign_timestamped(payload: payload, secret: SecureRandom.hex(32))

      expect(
        described_class.verify_timestamped(payload: payload, header: header, secret: secret)
      ).to be(false)
    end

    it "rejects a tampered payload" do
      header = described_class.sign_timestamped(payload: payload, secret: secret)

      expect(
        described_class.verify_timestamped(payload: "#{payload}x", header: header, secret: secret)
      ).to be(false)
    end

    it "rejects a stale timestamp outside max_skew" do
      stale_ts = Time.current.to_i - 3600
      sig = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{stale_ts}.#{payload}")
      header = "t=#{stale_ts},v1=#{sig}"

      expect(
        described_class.verify_timestamped(payload: payload, header: header, secret: secret)
      ).to be(false)
    end

    it "rejects malformed headers and blank inputs" do
      expect(described_class.verify_timestamped(payload: payload, header: "garbage", secret: secret)).to be(false)
      expect(described_class.verify_timestamped(payload: payload, header: "", secret: secret)).to be(false)
      expect(described_class.verify_timestamped(payload: payload, header: "t=1,v1=abc", secret: "")).to be(false)
    end
  end

  describe ".generate_signing_secret" do
    it "returns a whsig-prefixed urlsafe secret by default" do
      value = described_class.generate_signing_secret

      expect(value).to match(/\Awhsig_[A-Za-z0-9_\-=]+\z/)
    end

    it "honors a custom prefix and returns unique values" do
      expect(described_class.generate_signing_secret(prefix: "whsec")).to start_with("whsec_")
      expect(described_class.generate_signing_secret).not_to eq(described_class.generate_signing_secret)
    end
  end
end
