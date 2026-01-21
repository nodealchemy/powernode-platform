# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::Sbom, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:repository).class_name("Devops::Repository").optional }
    it { is_expected.to belong_to(:pipeline_run).class_name("Devops::PipelineRun").optional }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to have_many(:components).class_name("SupplyChain::SbomComponent").dependent(:destroy) }
    it { is_expected.to have_many(:vulnerabilities).class_name("SupplyChain::SbomVulnerability").dependent(:destroy) }
    it { is_expected.to have_many(:diffs).class_name("SupplyChain::SbomDiff").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:supply_chain_sbom, account: account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:format) }
    it { is_expected.to validate_inclusion_of(:format).in_array(SupplyChain::Sbom::FORMATS) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::Sbom::STATUSES) }
  end

  describe "scopes" do
    let!(:cyclonedx_sbom) { create(:supply_chain_sbom, account: account, format: "cyclonedx_1_5") }
    let!(:spdx_sbom) { create(:supply_chain_sbom, account: account, format: "spdx_2_3") }
    let!(:compliant_sbom) { create(:supply_chain_sbom, account: account, ntia_minimum_compliant: true) }
    let!(:non_compliant_sbom) { create(:supply_chain_sbom, account: account, ntia_minimum_compliant: false) }

    it "filters by format" do
      expect(described_class.by_format("cyclonedx_1_5")).to include(cyclonedx_sbom)
      expect(described_class.by_format("cyclonedx_1_5")).not_to include(spdx_sbom)
    end

    it "filters NTIA compliant" do
      expect(described_class.ntia_compliant).to include(compliant_sbom)
      expect(described_class.ntia_compliant).not_to include(non_compliant_sbom)
    end
  end

  describe "#cyclonedx?" do
    it "returns true for CycloneDX formats" do
      sbom = build(:supply_chain_sbom, format: "cyclonedx_1_5")
      expect(sbom.cyclonedx?).to be true
    end

    it "returns false for SPDX formats" do
      sbom = build(:supply_chain_sbom, format: "spdx_2_3")
      expect(sbom.cyclonedx?).to be false
    end
  end

  describe "#spdx?" do
    it "returns true for SPDX formats" do
      sbom = build(:supply_chain_sbom, format: "spdx_2_3")
      expect(sbom.spdx?).to be true
    end

    it "returns false for CycloneDX formats" do
      sbom = build(:supply_chain_sbom, format: "cyclonedx_1_5")
      expect(sbom.spdx?).to be false
    end
  end

  describe "#vulnerability_summary" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }

    before do
      create(:supply_chain_sbom_vulnerability, sbom: sbom, severity: "critical")
      create(:supply_chain_sbom_vulnerability, sbom: sbom, severity: "critical")
      create(:supply_chain_sbom_vulnerability, sbom: sbom, severity: "high")
      create(:supply_chain_sbom_vulnerability, sbom: sbom, severity: "medium")
    end

    it "returns counts by severity" do
      summary = sbom.vulnerability_summary
      expect(summary[:critical]).to eq(2)
      expect(summary[:high]).to eq(1)
      expect(summary[:medium]).to eq(1)
      expect(summary[:low]).to eq(0)
    end
  end
end
