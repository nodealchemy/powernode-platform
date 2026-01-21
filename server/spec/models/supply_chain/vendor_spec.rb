# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::Vendor, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to have_many(:risk_assessments).class_name("SupplyChain::RiskAssessment").dependent(:destroy) }
    it { is_expected.to have_many(:questionnaire_responses).class_name("SupplyChain::QuestionnaireResponse").dependent(:destroy) }
    it { is_expected.to have_many(:monitoring_events).class_name("SupplyChain::VendorMonitoringEvent").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:supply_chain_vendor, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:vendor_type) }
    it { is_expected.to validate_inclusion_of(:vendor_type).in_array(SupplyChain::Vendor::VENDOR_TYPES) }
    it { is_expected.to validate_inclusion_of(:risk_tier).in_array(SupplyChain::Vendor::RISK_TIERS) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::Vendor::STATUSES) }
  end

  describe "scopes" do
    let!(:active_vendor) { create(:supply_chain_vendor, account: account, status: "active") }
    let!(:inactive_vendor) { create(:supply_chain_vendor, account: account, status: "inactive") }
    let!(:critical_vendor) { create(:supply_chain_vendor, account: account, risk_tier: "critical") }
    let!(:low_vendor) { create(:supply_chain_vendor, account: account, risk_tier: "low") }

    it "filters active vendors" do
      expect(described_class.active).to include(active_vendor)
      expect(described_class.active).not_to include(inactive_vendor)
    end

    it "filters by risk tier" do
      expect(described_class.by_risk_tier("critical")).to include(critical_vendor)
      expect(described_class.by_risk_tier("critical")).not_to include(low_vendor)
    end
  end

  describe "#calculate_risk_score" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }

    context "with risk assessments" do
      before do
        create(:supply_chain_risk_assessment, vendor: vendor, security_score: 80, compliance_score: 70, operational_score: 90)
      end

      it "calculates weighted average risk score" do
        vendor.calculate_risk_score!
        expect(vendor.risk_score).to be_between(0, 100)
      end
    end

    context "without risk assessments" do
      it "sets default risk score" do
        vendor.calculate_risk_score!
        expect(vendor.risk_score).to eq(50) # default
      end
    end
  end

  describe "#needs_assessment?" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }

    context "with no assessments" do
      it "returns true" do
        expect(vendor.needs_assessment?).to be true
      end
    end

    context "with recent assessment" do
      before do
        create(:supply_chain_risk_assessment, vendor: vendor, completed_at: 1.month.ago)
      end

      it "returns false" do
        expect(vendor.needs_assessment?).to be false
      end
    end

    context "with old assessment" do
      before do
        create(:supply_chain_risk_assessment, vendor: vendor, completed_at: 13.months.ago)
      end

      it "returns true" do
        expect(vendor.needs_assessment?).to be true
      end
    end
  end

  describe "#data_sensitivity" do
    it "returns high for PHI handling" do
      vendor = build(:supply_chain_vendor, handles_phi: true)
      expect(vendor.data_sensitivity).to eq("high")
    end

    it "returns medium for PCI handling" do
      vendor = build(:supply_chain_vendor, handles_pci: true)
      expect(vendor.data_sensitivity).to eq("medium")
    end

    it "returns medium for PII handling" do
      vendor = build(:supply_chain_vendor, handles_pii: true)
      expect(vendor.data_sensitivity).to eq("medium")
    end

    it "returns low for no sensitive data" do
      vendor = build(:supply_chain_vendor, handles_pii: false, handles_phi: false, handles_pci: false)
      expect(vendor.data_sensitivity).to eq("low")
    end
  end
end
