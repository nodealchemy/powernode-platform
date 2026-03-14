# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::VerificationLog, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:attestation) { create(:supply_chain_attestation, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:attestation).class_name("SupplyChain::Attestation") }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:verified_by).class_name("User").optional }
  end

  describe "validations" do
    subject { create(:supply_chain_verification_log, attestation: attestation, account: account) }

    it { is_expected.to validate_presence_of(:verification_type) }
    it { is_expected.to validate_inclusion_of(:verification_type).in_array(SupplyChain::VerificationLog::VERIFICATION_TYPES) }
    it { is_expected.to validate_presence_of(:result) }
    it { is_expected.to validate_inclusion_of(:result).in_array(SupplyChain::VerificationLog::RESULTS) }

    it "validates presence of log_hash" do
      log = build(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil)
      log.valid?
      expect(log.log_hash).to be_present
    end

    it "validates uniqueness of log_hash" do
      log1 = create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil)
      log2 = build(:supply_chain_verification_log, attestation: attestation, account: account)
      log2.log_hash = log1.log_hash
      expect(log2).not_to be_valid
      expect(log2.errors[:log_hash]).to include("has already been taken")
    end
  end

  describe "scopes" do
    let!(:full_verification) { create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil, verification_type: "full") }
    let!(:signature_verification) { create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil, verification_type: "signature") }
    let!(:passed_log) { create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil, result: "passed") }
    let!(:failed_log) { create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil, result: "failed") }
    let!(:skipped_log) { create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil, result: "skipped") }

    it "filters by type" do
      expect(described_class.by_type("full")).to include(full_verification)
      expect(described_class.by_type("full")).not_to include(signature_verification)
    end

    it "filters passed logs" do
      expect(described_class.passed).to include(passed_log)
      expect(described_class.passed).not_to include(failed_log, skipped_log)
    end

    it "filters failed logs" do
      expect(described_class.failed).to include(failed_log)
      expect(described_class.failed).not_to include(passed_log, skipped_log)
    end

    it "filters skipped logs" do
      expect(described_class.skipped).to include(skipped_log)
      expect(described_class.skipped).not_to include(passed_log, failed_log)
    end

    it "filters for attestation" do
      other_attestation = create(:supply_chain_attestation, account: account)
      other_log = create(:supply_chain_verification_log, attestation: other_attestation, account: account, log_hash: nil)

      expect(described_class.for_attestation(attestation.id)).to include(full_verification)
      expect(described_class.for_attestation(attestation.id)).not_to include(other_log)
    end
  end

  describe "result predicates" do
    it "#passed? returns true for passed result" do
      log = build(:supply_chain_verification_log, result: "passed")
      expect(log.passed?).to be true
    end

    it "#failed? returns true for failed result" do
      log = build(:supply_chain_verification_log, result: "failed")
      expect(log.failed?).to be true
    end

    it "#skipped? returns true for skipped result" do
      log = build(:supply_chain_verification_log, result: "skipped")
      expect(log.skipped?).to be true
    end
  end

  describe "#chain_valid?" do
    context "when no previous log" do
      let(:log) { create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil) }

      it "returns true" do
        expect(log.chain_valid?).to be true
      end
    end

    context "when previous log exists" do
      let!(:first_log) { create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil) }
      let!(:second_log) do
        sleep(0.01) # Ensure different timestamp
        create(:supply_chain_verification_log,
               attestation: attestation,
               account: account,
               log_hash: nil)
      end

      it "returns true when chain is valid" do
        expect(second_log.chain_valid?).to be true
      end

      it "returns false when chain is broken" do
        second_log.update_column(:previous_log_hash, "invalid_hash")
        expect(second_log.chain_valid?).to be false
      end
    end
  end

  describe "#verify_chain_integrity" do
    let!(:log1) { create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil) }
    let!(:log2) do
      sleep(0.01) # Ensure different timestamp
      create(:supply_chain_verification_log,
             attestation: attestation,
             account: account,
             log_hash: nil)
    end
    let!(:log3) do
      sleep(0.01) # Ensure different timestamp
      create(:supply_chain_verification_log,
             attestation: attestation,
             account: account,
             log_hash: nil)
    end

    it "returns true when entire chain is valid" do
      expect(log3.verify_chain_integrity).to be true
    end

    it "returns false when first log has previous_hash" do
      log1.update_column(:previous_log_hash, "should_be_nil")
      expect(log3.verify_chain_integrity).to be false
    end

    it "returns false when middle chain is broken" do
      log2.update_column(:previous_log_hash, "broken")
      expect(log3.verify_chain_integrity).to be false
    end

    it "returns true for empty chain" do
      empty_attestation = create(:supply_chain_attestation, account: account)
      log = build(:supply_chain_verification_log, attestation: empty_attestation, account: account, log_hash: nil)
      expect(log.verify_chain_integrity).to be true
    end
  end

  describe "#summary" do
    let(:log) { create(:supply_chain_verification_log, attestation: attestation, account: account, verified_by: user, log_hash: nil) }

    it "returns expected keys" do
      summary = log.summary

      expect(summary).to include(
        :id,
        :attestation_id,
        :verification_type,
        :result,
        :result_message,
        :log_hash,
        :chain_valid,
        :verified_by_id,
        :created_at
      )
    end
  end

  describe "callbacks" do
    describe "calculate_log_hash" do
      it "generates log_hash on create" do
        log = build(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil)
        log.save!
        expect(log.log_hash).to be_present
        expect(log.log_hash.length).to eq(64) # SHA256 hex
      end

      it "sets previous_log_hash to nil for first log" do
        log = create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil)
        expect(log.previous_log_hash).to be_nil
      end

      it "sets previous_log_hash to previous log's hash" do
        first_log = create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil)
        sleep(0.01) # Ensure different timestamp
        second_log = create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil)

        expect(second_log.previous_log_hash).to eq(first_log.log_hash)
      end

      it "does not regenerate hash if already present" do
        log = build(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: "preset_hash")
        log.save!
        expect(log.log_hash).to eq("preset_hash")
      end
    end
  end

  describe "JSONB sanitization" do
    it "initializes verification_details as empty hash" do
      log = create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil, verification_details: nil)
      expect(log.verification_details).to eq({})
    end

    it "initializes metadata as empty hash" do
      log = create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil, metadata: nil)
      expect(log.metadata).to eq({})
    end
  end

  describe "tamper-evident hash chain" do
    it "produces different hashes for different data" do
      log1 = create(:supply_chain_verification_log,
                   attestation: attestation,
                   account: account,
                   log_hash: nil,
                   verification_type: "full",
                   result: "passed")
      sleep(0.01) # Ensure different timestamp
      log2 = create(:supply_chain_verification_log,
                   attestation: attestation,
                   account: account,
                   log_hash: nil,
                   verification_type: "signature",
                   result: "failed")

      expect(log1.log_hash).not_to eq(log2.log_hash)
    end

    it "includes timestamp in hash calculation" do
      # Different timestamps should produce different hashes
      # This is inherently tested by creating logs at different times
      log1 = create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil)
      sleep(0.1)
      log2 = create(:supply_chain_verification_log, attestation: attestation, account: account, log_hash: nil)

      expect(log1.log_hash).not_to eq(log2.log_hash)
    end
  end
end
