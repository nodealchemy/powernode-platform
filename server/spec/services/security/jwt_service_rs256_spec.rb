# frozen_string_literal: true

require "rails_helper"

# RS256 signing path + rotation grace, exercised through Security::JwtService.
# The active/previous keys resolve through Security::JwtKeyStore; here the store
# starts empty so the ENV keypair is active, then a rotation makes it the previous
# (grace) key.
RSpec.describe Security::JwtService, "RS256 signing + rotation grace" do
  let(:env_key) { OpenSSL::PKey::RSA.generate(2048) }

  before do
    allow(Rails.application.config).to receive(:jwt_algorithm).and_return("RS256")
    # config.jwt_private_key/public_key aren't assigned in the HS256 test env;
    # stub JwtKeyStore's env-PEM fallback seam instead (see jwt_key_store_spec).
    allow(Security::JwtKeyStore).to receive(:env_private_pem).and_return(env_key.to_pem)
    allow(Security::JwtKeyStore).to receive(:env_public_pem).and_return(env_key.public_key.to_pem)
    # Isolate from blacklist DB state — this spec covers signing/verification only.
    allow(Security::JwtBlacklistService).to receive(:blacklisted?).and_return(false)
    Security::JwtKeyStore.clear_cache!
  end

  after { Security::JwtKeyStore.clear_cache! }

  it "signs with RS256 and verifies with the active public key" do
    token = described_class.encode({ sub: "u1", type: "access" })

    header = JWT.decode(token, nil, false).last
    expect(header["alg"]).to eq("RS256")
    expect(described_class.decode(token)[:sub]).to eq("u1")
  end

  it "still verifies an in-flight token signed with the PREVIOUS key during grace" do
    old_token = described_class.encode({ sub: "u1", type: "access" }) # signed with the (now ENV) active key
    Security::JwtKeyStore.rotate!(grace_hours: 24)                     # ENV key becomes the previous key
    Security::JwtKeyStore.clear_cache!

    # The active key is now the rotated one; the old token must verify via the grace key.
    expect(described_class.decode(old_token)[:sub]).to eq("u1")
  end

  it "rejects an old-key token once the grace window has elapsed" do
    # Long exp so token expiry doesn't mask the grace-window rejection under test.
    old_token = described_class.encode({ sub: "u1", type: "access" }, 48.hours.from_now)
    Security::JwtKeyStore.rotate!(grace_hours: 24)
    Security::JwtKeyStore.clear_cache!

    travel_to(25.hours.from_now) do
      expect { described_class.decode(old_token) }.to raise_error(StandardError, /Invalid token/)
    end
  end

  it "still verifies an in-flight token across TWO overlapping rotations (grace keyring)" do
    old_token = described_class.encode({ sub: "u1", type: "access" })
    Security::JwtKeyStore.rotate!(grace_hours: 24) # retire the signing key
    Security::JwtKeyStore.rotate!(grace_hours: 24) # rotate again within grace
    Security::JwtKeyStore.clear_cache!

    # The original key is two generations back but still inside its grace window.
    expect(described_class.decode(old_token)[:sub]).to eq("u1")
  end

  it "rejects a token signed by an unrelated key" do
    foreign = OpenSSL::PKey::RSA.generate(2048)
    bad = JWT.encode(
      { sub: "x", exp: 1.hour.from_now.to_i,
        iss: Rails.application.config.jwt_issuer, aud: Rails.application.config.jwt_audience },
      foreign, "RS256"
    )

    expect { described_class.decode(bad) }.to raise_error(StandardError, /Invalid token/)
  end
end
