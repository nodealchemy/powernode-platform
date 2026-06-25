# frozen_string_literal: true

require "rails_helper"

# Security::JwtKeyStore — store-backed RS256 signing keypair with multi-generation
# rotation + grace. The in-process key cache is module-level, so clear it around
# every example to prevent state from one example bleeding into the next.
RSpec.describe Security::JwtKeyStore, type: :service do
  before { described_class.clear_cache! }
  after  { described_class.clear_cache! }

  # A stable "ENV" keypair to fall back to when the store is empty. The config
  # accessors (config.jwt_private_key/public_key) are only assigned under RS256 in
  # production, so they don't exist to stub in the HS256 test env — stub the
  # module's own env-PEM readers, which is exactly the fallback seam.
  let(:env_key) { OpenSSL::PKey::RSA.generate(2048) }

  before do
    allow(described_class).to receive(:env_private_pem).and_return(env_key.to_pem)
    allow(described_class).to receive(:env_public_pem).and_return(env_key.public_key.to_pem)
  end

  describe "ENV fallback (store empty, never rotated)" do
    it "returns the ENV keypair as the active keypair" do
      expect(described_class.active_private_key_pem).to eq(env_key.to_pem)
      expect(described_class.active_public_key_pem).to eq(env_key.public_key.to_pem)
    end

    it "reports no grace keys and no active grace window" do
      expect(described_class.grace_public_pems).to be_empty
      expect(described_class.within_grace?).to be(false)
    end

    it "is not considered populated until a rotation occurs" do
      expect(described_class.store_populated?).to be(false)
    end

    it "never outages: a store read failure falls back to the ENV key" do
      allow(Security::SecretStore).to receive(:read).and_raise(StandardError, "store down")
      expect(described_class.active_private_key_pem).to eq(env_key.to_pem)
    end
  end

  describe "#rotate!" do
    it "replaces the active keypair with a freshly generated, valid RSA keypair" do
      before_pub = described_class.active_public_key_pem
      described_class.rotate!(grace_hours: 24)
      after_pub = described_class.active_public_key_pem

      expect(after_pub).not_to eq(before_pub)
      expect { OpenSSL::PKey::RSA.new(described_class.active_private_key_pem) }.not_to raise_error
      # active keypair private/public must be a matching pair (single-row write)
      priv = OpenSSL::PKey::RSA.new(described_class.active_private_key_pem)
      expect(priv.public_key.to_pem).to eq(described_class.active_public_key_pem)
      expect(described_class.store_populated?).to be(true)
    end

    it "retains the prior public key in the grace keyring" do
      described_class.rotate!(grace_hours: 24)
      expect(described_class.grace_public_pems).to include(env_key.public_key.to_pem)
      expect(described_class.within_grace?).to be(true)
    end

    it "drops grace keys once their window has elapsed" do
      described_class.rotate!(grace_hours: 24)
      described_class.clear_cache!

      travel_to(25.hours.from_now) do
        expect(described_class.within_grace?).to be(false)
        expect(described_class.grace_public_pems).to be_empty
      end
    end

    # HIGH-2 regression: a second rotation inside the grace window must NOT evict
    # the first retired key — both generations stay verifiable until each expires.
    it "keeps MULTIPLE retired keys across overlapping rotations" do
      described_class.rotate!(grace_hours: 24)        # retires env_key
      gen1_pub = described_class.active_public_key_pem # the first rotated key
      described_class.rotate!(grace_hours: 24)        # retires gen1, env_key still in grace

      ring = described_class.grace_public_pems
      expect(ring).to include(env_key.public_key.to_pem)
      expect(ring).to include(gen1_pub)
    end

    it "prunes already-expired keyring entries on the next rotation" do
      described_class.rotate!(grace_hours: 1)
      described_class.clear_cache!
      travel_to(2.hours.from_now) do
        described_class.rotate!(grace_hours: 24) # env_key entry now expired → pruned
        # only the just-retired key (the 1h-grace rotation's key) remains
        expect(described_class.grace_public_pems).not_to include(env_key.public_key.to_pem)
        expect(described_class.grace_public_pems.size).to eq(1)
      end
    end

    it "caps the verification keyring length (bounds per-token verify cost)" do
      future = 10.hours.from_now.iso8601
      oversized = Array.new(described_class::MAX_KEYRING_ENTRIES + 5) do |i|
        { "pem" => "pem-#{i}", "expires_at" => future }
      end
      Security::SecretStore.write(account: nil, scope: described_class::SCOPE,
                                  key: described_class::VERIFICATION_KEYRING, value: oversized.to_json)
      described_class.clear_cache!

      described_class.rotate!(grace_hours: 24)

      ring = JSON.parse(Security::SecretStore.read(account: nil, scope: described_class::SCOPE,
                                                   key: described_class::VERIFICATION_KEYRING))
      expect(ring.size).to eq(described_class::MAX_KEYRING_ENTRIES)
    end

    it "returns metadata only — never key material" do
      meta = described_class.rotate!(grace_hours: 24)
      expect(meta.keys).to contain_exactly(:rotated_at, :grace_ends_at)
      expect(meta.values.map(&:to_s).join).not_to include("PRIVATE KEY")
    end

    it "persists the rotation durably (survives an in-process cache clear)" do
      described_class.rotate!(grace_hours: 24)
      rotated_pub = described_class.active_public_key_pem
      described_class.clear_cache!
      expect(described_class.active_public_key_pem).to eq(rotated_pub)
    end
  end

  # HIGH-1 regression: the verification-candidate set used after an active-key miss
  # must include the freshly-read active key, so a worker whose cache lags a
  # rotation still accepts tokens signed with the NEW key.
  describe ".grace_verification_pems" do
    it "includes the current active key plus all in-grace retired keys" do
      described_class.rotate!(grace_hours: 24)
      active = described_class.active_public_key_pem
      pems = described_class.grace_verification_pems
      expect(pems).to include(active)
      expect(pems).to include(env_key.public_key.to_pem)
    end

    it "force-refreshes a stale cache so a just-rotated active key is picked up" do
      # Prime this 'worker' cache with the pre-rotation active key.
      stale = described_class.active_public_key_pem
      # Simulate another process rotating: write a new active keypair directly.
      new_key = OpenSSL::PKey::RSA.generate(2048)
      Security::SecretStore.write(account: nil, scope: described_class::SCOPE,
                                  key: described_class::ACTIVE_KEYPAIR,
                                  value: { "private" => new_key.to_pem, "public" => new_key.public_key.to_pem }.to_json)
      # Without a forced refresh the cache would still return `stale`; the miss path must surface the new key.
      expect(described_class.grace_verification_pems).to include(new_key.public_key.to_pem)
      expect(stale).not_to eq(new_key.public_key.to_pem)
    end
  end
end
