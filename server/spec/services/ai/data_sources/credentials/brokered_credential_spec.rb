# frozen_string_literal: true

require "rails_helper"

# BrokeredCredential is the immutable value object a broker hands back so the
# EXISTING signer layer (Sigv4Signer / BearerSigner / ...) can consume the
# short-lived material it acquired (AWS STS, an OAuth2 token endpoint, a Vault
# dynamic engine, an S3 presigner) UNCHANGED.
#
# It satisfies the same signer contract as QueryService::VaultCredentialView:
#   #decrypted_api_key    -> primary key/token
#   #decrypted_api_secret -> secret half (may be nil)
#   #[](name)             -> any other field a signer reads off a plain Hash
# plus the lease metadata BrokerCache + the brokers consume:
#   #expires_at  #expired?(skew)  #presigned_url
#
# These specs assert the REAL spelling-resolution order, the pass-through reader,
# the (sleep-free) expiry math, and — critically — that #inspect / #to_s NEVER
# leak the secret material. No DB / Redis is touched: this is a pure value object.
RSpec.describe Ai::DataSources::Credentials::BrokeredCredential, type: :service do
  # ==========================================================================
  # #decrypted_api_key — spelling resolution: api_key | access_key_id | token | key
  # ==========================================================================
  describe "#decrypted_api_key" do
    it "resolves from api_key when present" do
      cred = described_class.new({ "api_key" => "PRIMARY" })
      expect(cred.decrypted_api_key).to eq("PRIMARY")
    end

    it "resolves from access_key_id (AWS spelling) when api_key is absent" do
      cred = described_class.new({ "access_key_id" => "AKIA123" })
      expect(cred.decrypted_api_key).to eq("AKIA123")
    end

    it "resolves from token (OAuth bearer spelling) when api_key/access_key_id are absent" do
      cred = described_class.new({ "token" => "BEARER_TOK" })
      expect(cred.decrypted_api_key).to eq("BEARER_TOK")
    end

    it "resolves from key (generic spelling) as the last fallback" do
      cred = described_class.new({ "key" => "GENERIC" })
      expect(cred.decrypted_api_key).to eq("GENERIC")
    end

    it "honours the precedence order api_key > access_key_id > token > key" do
      cred = described_class.new({ "api_key" => "A", "access_key_id" => "B", "token" => "C", "key" => "D" })
      expect(cred.decrypted_api_key).to eq("A")
    end

    it "falls through to access_key_id when api_key is missing but the lower spellings collide" do
      cred = described_class.new({ "access_key_id" => "B", "token" => "C", "key" => "D" })
      expect(cred.decrypted_api_key).to eq("B")
    end

    it "prefers token over key when only those two are present" do
      cred = described_class.new({ "token" => "C", "key" => "D" })
      expect(cred.decrypted_api_key).to eq("C")
    end

    it "accepts SYMBOL keys (jsonb-tolerant indifferent access)" do
      cred = described_class.new({ api_key: "SYM_PRIMARY" })
      expect(cred.decrypted_api_key).to eq("SYM_PRIMARY")
    end

    it "returns nil when no key spelling is present" do
      cred = described_class.new({ "session_token" => "only_a_session_token" })
      expect(cred.decrypted_api_key).to be_nil
    end

    it "returns nil for an empty material hash" do
      expect(described_class.new({}).decrypted_api_key).to be_nil
    end

    it "treats nil material as an empty hash" do
      expect(described_class.new(nil).decrypted_api_key).to be_nil
    end
  end

  # ==========================================================================
  # #decrypted_api_secret — spelling resolution: api_secret | secret_access_key | secret
  # ==========================================================================
  describe "#decrypted_api_secret" do
    it "resolves from api_secret when present" do
      cred = described_class.new({ "api_secret" => "SECRET" })
      expect(cred.decrypted_api_secret).to eq("SECRET")
    end

    it "resolves from secret_access_key (AWS spelling) when api_secret is absent" do
      cred = described_class.new({ "secret_access_key" => "AWS_SECRET" })
      expect(cred.decrypted_api_secret).to eq("AWS_SECRET")
    end

    it "resolves from secret (generic spelling) as the last fallback" do
      cred = described_class.new({ "secret" => "GENERIC_SECRET" })
      expect(cred.decrypted_api_secret).to eq("GENERIC_SECRET")
    end

    it "honours the precedence order api_secret > secret_access_key > secret" do
      cred = described_class.new({ "api_secret" => "X", "secret_access_key" => "Y", "secret" => "Z" })
      expect(cred.decrypted_api_secret).to eq("X")
    end

    it "prefers secret_access_key over secret when api_secret is absent" do
      cred = described_class.new({ "secret_access_key" => "Y", "secret" => "Z" })
      expect(cred.decrypted_api_secret).to eq("Y")
    end

    it "accepts SYMBOL keys" do
      cred = described_class.new({ secret_access_key: "SYM_AWS_SECRET" })
      expect(cred.decrypted_api_secret).to eq("SYM_AWS_SECRET")
    end

    it "is nil for a token-only scheme (OAuth bearer has no secret half)" do
      cred = described_class.new({ "token" => "BEARER_TOK" })
      expect(cred.decrypted_api_secret).to be_nil
    end

    it "returns nil for an empty material hash" do
      expect(described_class.new({}).decrypted_api_secret).to be_nil
    end
  end

  # ==========================================================================
  # #[] — pass-through for any other field a signer reads off a plain Hash
  # ==========================================================================
  describe "#[] (arbitrary field pass-through)" do
    subject(:cred) do
      described_class.new({ "session_token" => "FwoGZ...SESSION",
        "security_token" => "STS-SECURITY",
        "region" => "us-east-1" })
    end

    it "passes through session_token (AWS STS temp-credential field)" do
      expect(cred["session_token"]).to eq("FwoGZ...SESSION")
    end

    it "passes through security_token (legacy STS field spelling)" do
      expect(cred["security_token"]).to eq("STS-SECURITY")
    end

    it "passes through arbitrary non-secret fields (e.g. region)" do
      expect(cred["region"]).to eq("us-east-1")
    end

    it "accepts a SYMBOL name and reads the same value (indifferent lookup)" do
      expect(cred[:session_token]).to eq("FwoGZ...SESSION")
    end

    it "reads a String value back when the material was given with SYMBOL keys" do
      sym_cred = described_class.new({ session_token: "SYM_SESSION" })
      expect(sym_cred["session_token"]).to eq("SYM_SESSION")
    end

    it "returns nil for an unknown field" do
      expect(cred["nonexistent"]).to be_nil
    end

    it "exposes the canonical fields via #[] too (single source of truth)" do
      keyed = described_class.new({ "access_key_id" => "AKIA", "secret_access_key" => "SK" })
      expect(keyed["access_key_id"]).to eq("AKIA")
      expect(keyed["secret_access_key"]).to eq("SK")
    end
  end

  # ==========================================================================
  # #presigned_url — nil unless set, returns it when set (PresignedUrlBroker)
  # ==========================================================================
  describe "#presigned_url" do
    it "is nil when the broker did not set one" do
      expect(described_class.new({ "api_key" => "k" }).presigned_url).to be_nil
    end

    it "is nil for a wholly empty material hash" do
      expect(described_class.new({}).presigned_url).to be_nil
    end

    it "returns the fully pre-signed URL when set" do
      url = "https://bucket.s3.amazonaws.com/obj?X-Amz-Signature=abc&X-Amz-Expires=900"
      cred = described_class.new({ "presigned_url" => url })
      expect(cred.presigned_url).to eq(url)
    end

    it "is also reachable via #[\"presigned_url\"] (same backing field)" do
      url = "https://bucket.s3.amazonaws.com/obj?X-Amz-Signature=def"
      cred = described_class.new({ "presigned_url" => url })
      expect(cred["presigned_url"]).to eq(url)
      expect(cred["presigned_url"]).to eq(cred.presigned_url)
    end

    it "resolves a presigned_url supplied under a SYMBOL key" do
      url = "https://bucket.s3.amazonaws.com/obj?X-Amz-Signature=ghi"
      cred = described_class.new({ presigned_url: url })
      expect(cred.presigned_url).to eq(url)
    end
  end

  # ==========================================================================
  # #expires_at — absolute lease expiry (Time) or nil; coercion
  # ==========================================================================
  describe "#expires_at" do
    it "is nil when no expiry was supplied" do
      expect(described_class.new({ "token" => "t" }).expires_at).to be_nil
    end

    it "returns the Time it was constructed with" do
      at = 1.hour.from_now
      cred = described_class.new({ "token" => "t" }, expires_at: at)
      expect(cred.expires_at).to eq(at)
    end

    it "coerces a numeric epoch into a Time" do
      epoch = 30.minutes.from_now.to_i
      cred = described_class.new({ "token" => "t" }, expires_at: epoch)
      expect(cred.expires_at).to be_a(Time)
      expect(cred.expires_at.to_i).to eq(epoch)
    end

    it "coerces an ISO8601 string into a Time" do
      iso = 45.minutes.from_now.utc.iso8601
      cred = described_class.new({ "token" => "t" }, expires_at: iso)
      expect(cred.expires_at).to be_a(Time)
      expect(cred.expires_at.utc.iso8601).to eq(iso)
    end

    it "leaves expires_at nil when an unparseable value is supplied (does not raise)" do
      cred = described_class.new({ "token" => "t" }, expires_at: "not-a-date")
      expect(cred.expires_at).to be_nil
    end
  end

  # ==========================================================================
  # #expired?(skew) — sleep-free: construct with a past / future expires_at
  # ==========================================================================
  describe "#expired?" do
    it "is false when there is no expiry (a credential with no lease never expires)" do
      cred = described_class.new({ "token" => "t" })
      expect(cred.expired?).to be(false)
      expect(cred.expired?(3600)).to be(false)
    end

    it "is false for a future expiry with no skew" do
      cred = described_class.new({ "token" => "t" }, expires_at: 10.minutes.from_now)
      expect(cred.expired?).to be(false)
    end

    it "is true for a past expiry" do
      cred = described_class.new({ "token" => "t" }, expires_at: 5.minutes.ago)
      expect(cred.expired?).to be(true)
    end

    it "is true exactly at the expiry boundary (now >= expires_at)" do
      # Freeze time so the boundary comparison is deterministic without sleeping.
      now = Time.current.change(usec: 0)
      cred = described_class.new({ "token" => "t" }, expires_at: now)
      travel_to(now) { expect(cred.expired?).to be(true) }
    end

    it "treats a credential as expired EARLY when within the skew window of expiry" do
      # expires in 30s; a 60s skew makes (expires_at - skew) already in the past.
      cred = described_class.new({ "token" => "t" }, expires_at: 30.seconds.from_now)
      expect(cred.expired?(60)).to be(true)
    end

    it "is NOT expired when the skew window has not yet been reached" do
      # expires in 10 minutes; a 60s skew still leaves 9 minutes of validity.
      cred = described_class.new({ "token" => "t" }, expires_at: 10.minutes.from_now)
      expect(cred.expired?(60)).to be(false)
    end

    it "coerces a non-integer skew via to_i" do
      cred = described_class.new({ "token" => "t" }, expires_at: 30.seconds.from_now)
      expect(cred.expired?("90")).to be(true)
    end
  end

  # ==========================================================================
  # SECURITY: #inspect / #to_s MUST NOT leak material
  # ==========================================================================
  describe "redaction (security)" do
    let(:secret_value) { "TOPSECRET-secret_access_key-VALUE" }
    let(:token_value)  { "BEARER-access-token-VALUE" }
    let(:session_value) { "FwoGZ-session-token-VALUE" }

    subject(:cred) do
      described_class.new(
        {
          "access_key_id" => "AKIA-public-ish",
          "secret_access_key" => secret_value,
          "token" => token_value,
          "session_token" => session_value
        },
        expires_at: 1.hour.from_now
      )
    end

    it "#inspect never contains the secret value" do
      expect(cred.inspect).not_to include(secret_value)
    end

    it "#inspect never contains the token value" do
      expect(cred.inspect).not_to include(token_value)
    end

    it "#inspect never contains the session_token value" do
      expect(cred.inspect).not_to include(session_value)
    end

    it "#to_s never contains the secret value" do
      expect(cred.to_s).not_to include(secret_value)
    end

    it "#to_s never contains the token value" do
      expect(cred.to_s).not_to include(token_value)
    end

    it "string interpolation never leaks the secret (covers `raise cred` / log paths)" do
      interpolated = "credential=#{cred}"
      expect(interpolated).not_to include(secret_value)
      expect(interpolated).not_to include(token_value)
      expect(interpolated).not_to include(session_value)
    end

    it "exposes only the sorted field NAMES (not values) in #inspect" do
      out = cred.inspect
      expect(out).to include("access_key_id")
      expect(out).to include("secret_access_key")
      expect(out).to include("token")
      expect(out).to include("session_token")
      # The names are present but their secret VALUES are not (asserted above).
    end

    it "surfaces the expiry metadata in #inspect (non-sensitive)" do
      expect(cred.inspect).to match(/expires_at=/)
    end

    it "reports expires_at=none in #inspect when there is no lease" do
      expect(described_class.new({ "token" => "t" }).inspect).to include("expires_at=none")
    end

    it "aliases to_s to inspect (identical redacted rendering)" do
      expect(cred.to_s).to eq(cred.inspect)
    end

    it "includes the class name in the redacted rendering" do
      expect(cred.inspect).to include("BrokeredCredential")
    end
  end

  # ==========================================================================
  # Immutability — the value object is frozen and the material cannot be mutated
  # ==========================================================================
  describe "immutability" do
    subject(:cred) { described_class.new({ "api_key" => "k", "session_token" => "s" }) }

    it "is frozen on construction" do
      expect(cred).to be_frozen
    end

    it "does not expose a writer that lets a signer mutate the material" do
      expect(cred).not_to respond_to(:[]=)
    end

    it "does not mutate the caller's original Hash" do
      original = { "api_key" => "k" }
      described_class.new(original)
      expect(original).to eq("api_key" => "k")
    end
  end
end
