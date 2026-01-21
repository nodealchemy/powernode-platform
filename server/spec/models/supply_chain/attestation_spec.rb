# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::Attestation, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:sbom).class_name("SupplyChain::Sbom").optional }
    it { is_expected.to belong_to(:signing_key).class_name("SupplyChain::SigningKey").optional }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to have_one(:build_provenance).class_name("SupplyChain::BuildProvenance").dependent(:destroy) }
    it { is_expected.to have_many(:verification_logs).class_name("SupplyChain::VerificationLog").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:supply_chain_attestation, account: account) }

    it { is_expected.to validate_presence_of(:attestation_type) }
    it { is_expected.to validate_presence_of(:subject_name) }
    it { is_expected.to validate_presence_of(:subject_digest) }
    it { is_expected.to validate_inclusion_of(:attestation_type).in_array(SupplyChain::Attestation::ATTESTATION_TYPES) }
    it { is_expected.to validate_inclusion_of(:slsa_level).in_array(SupplyChain::Attestation::SLSA_LEVELS).allow_nil }
  end

  describe "scopes" do
    let!(:signed) { create(:supply_chain_attestation, account: account, signature: "sig123") }
    let!(:unsigned) { create(:supply_chain_attestation, account: account, signature: nil) }
    let!(:verified) { create(:supply_chain_attestation, account: account, verification_status: "verified") }
    let!(:unverified) { create(:supply_chain_attestation, account: account, verification_status: "pending") }

    it "filters signed attestations" do
      expect(described_class.signed).to include(signed)
      expect(described_class.signed).not_to include(unsigned)
    end

    it "filters verified attestations" do
      expect(described_class.verified).to include(verified)
      expect(described_class.verified).not_to include(unverified)
    end
  end

  describe "#signed?" do
    it "returns true when signature is present" do
      attestation = build(:supply_chain_attestation, signature: "sig123")
      expect(attestation.signed?).to be true
    end

    it "returns false when signature is nil" do
      attestation = build(:supply_chain_attestation, signature: nil)
      expect(attestation.signed?).to be false
    end
  end

  describe "#verified?" do
    it "returns true when verification_status is verified" do
      attestation = build(:supply_chain_attestation, verification_status: "verified")
      expect(attestation.verified?).to be true
    end

    it "returns false for other statuses" do
      attestation = build(:supply_chain_attestation, verification_status: "pending")
      expect(attestation.verified?).to be false
    end
  end

  describe "#logged_to_rekor?" do
    it "returns true when rekor_log_id is present" do
      attestation = build(:supply_chain_attestation, rekor_log_id: "12345")
      expect(attestation.logged_to_rekor?).to be true
    end

    it "returns false when rekor_log_id is nil" do
      attestation = build(:supply_chain_attestation, rekor_log_id: nil)
      expect(attestation.logged_to_rekor?).to be false
    end
  end

  describe "#slsa_compliant?" do
    it "returns true for valid SLSA level" do
      attestation = build(:supply_chain_attestation, slsa_level: 2, signature: "sig", verification_status: "verified")
      expect(attestation.slsa_compliant?(2)).to be true
    end

    it "returns false for higher SLSA level requirement" do
      attestation = build(:supply_chain_attestation, slsa_level: 1)
      expect(attestation.slsa_compliant?(2)).to be false
    end
  end
end
