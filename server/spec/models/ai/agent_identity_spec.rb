# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::AgentIdentity, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { should belong_to(:account) }
  end

  describe "validations" do
    subject { build(:ai_agent_identity, account: account) }

    it { should validate_presence_of(:agent_id) }
    it { should validate_presence_of(:public_key) }
    it { should validate_presence_of(:encrypted_private_key) }
    it "generates key_fingerprint from public_key" do
      identity = build(:ai_agent_identity, account: account, key_fingerprint: nil)
      identity.valid?
      expect(identity.key_fingerprint).to be_present
    end
    it { should validate_presence_of(:algorithm) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:algorithm).in_array(%w[ed25519]) }
    it { should validate_inclusion_of(:status).in_array(%w[active rotated revoked]) }

    it "validates uniqueness of key_fingerprint" do
      existing = create(:ai_agent_identity, account: account)
      duplicate = build(:ai_agent_identity, account: account, key_fingerprint: existing.key_fingerprint)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key_fingerprint]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let!(:active_identity) { create(:ai_agent_identity, account: account, status: "active") }
    let!(:revoked_identity) { create(:ai_agent_identity, :revoked, account: account) }
    let!(:rotated_identity) { create(:ai_agent_identity, :rotated, account: account) }

    it ".active returns only active identities" do
      expect(described_class.active).to include(active_identity)
      expect(described_class.active).not_to include(revoked_identity)
    end

    it ".revoked returns only revoked identities" do
      expect(described_class.revoked).to include(revoked_identity)
      expect(described_class.revoked).not_to include(active_identity)
    end

    it ".rotated returns only rotated identities" do
      expect(described_class.rotated).to include(rotated_identity)
    end

    it ".for_agent scopes by agent_id" do
      results = described_class.for_agent(active_identity.agent_id)
      expect(results).to include(active_identity)
      expect(results).not_to include(revoked_identity)
    end

    it ".expiring_soon returns identities expiring within given window" do
      expiring = create(:ai_agent_identity, :expiring_soon, account: account)
      expect(described_class.expiring_soon(7.days)).to include(expiring)
      expect(described_class.expiring_soon(7.days)).not_to include(active_identity)
    end

    it ".not_expired excludes expired identities" do
      expired = create(:ai_agent_identity, :expired, account: account)
      expect(described_class.not_expired).not_to include(expired)
      expect(described_class.not_expired).to include(active_identity)
    end
  end

  describe "instance methods" do
    describe "#usable?" do
      it "returns true for active, non-expired identities" do
        identity = build(:ai_agent_identity, status: "active", expires_at: 1.year.from_now)
        expect(identity.usable?).to be true
      end

      it "returns false for revoked identities" do
        identity = build(:ai_agent_identity, :revoked)
        expect(identity.usable?).to be false
      end

      it "returns false for expired identities" do
        identity = build(:ai_agent_identity, :expired, status: "active")
        expect(identity.usable?).to be false
      end

      it "returns true for rotated identities within overlap window" do
        identity = build(:ai_agent_identity, :rotated)
        expect(identity.usable?).to be true
      end

      it "returns false for rotated identities past overlap window" do
        identity = build(:ai_agent_identity, status: "rotated", rotation_overlap_until: 1.hour.ago)
        expect(identity.usable?).to be false
      end
    end
  end

  describe "callbacks" do
    it "auto-generates fingerprint from public key" do
      identity = build(:ai_agent_identity, account: account, key_fingerprint: nil)
      identity.valid?
      expect(identity.key_fingerprint).to eq(Digest::SHA256.hexdigest(identity.public_key))
    end
  end
end
