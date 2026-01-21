# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::License, type: :model do
  describe "validations" do
    subject { build(:supply_chain_license) }

    it { is_expected.to validate_presence_of(:spdx_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:category) }
    it { is_expected.to validate_uniqueness_of(:spdx_id) }
    it { is_expected.to validate_inclusion_of(:category).in_array(SupplyChain::License::CATEGORIES) }
  end

  describe "scopes" do
    let!(:mit) { create(:supply_chain_license, spdx_id: "MIT", category: "permissive", is_copyleft: false) }
    let!(:gpl) { create(:supply_chain_license, spdx_id: "GPL-3.0", category: "copyleft", is_copyleft: true, is_strong_copyleft: true) }
    let!(:lgpl) { create(:supply_chain_license, spdx_id: "LGPL-3.0", category: "weak_copyleft", is_copyleft: true, is_strong_copyleft: false) }
    let!(:agpl) { create(:supply_chain_license, spdx_id: "AGPL-3.0", category: "copyleft", is_copyleft: true, is_network_copyleft: true) }

    it "filters permissive licenses" do
      expect(described_class.permissive).to include(mit)
      expect(described_class.permissive).not_to include(gpl)
    end

    it "filters copyleft licenses" do
      expect(described_class.copyleft).to include(gpl, lgpl, agpl)
      expect(described_class.copyleft).not_to include(mit)
    end

    it "filters strong copyleft licenses" do
      expect(described_class.strong_copyleft).to include(gpl)
      expect(described_class.strong_copyleft).not_to include(lgpl, mit)
    end

    it "filters network copyleft licenses" do
      expect(described_class.network_copyleft).to include(agpl)
      expect(described_class.network_copyleft).not_to include(gpl, mit)
    end
  end

  describe ".find_by_spdx" do
    let!(:license) { create(:supply_chain_license, spdx_id: "Apache-2.0") }

    it "finds license by exact SPDX ID" do
      expect(described_class.find_by_spdx("Apache-2.0")).to eq(license)
    end

    it "returns nil for unknown SPDX ID" do
      expect(described_class.find_by_spdx("Unknown-License")).to be_nil
    end
  end

  describe "#risk_level" do
    it "returns 'none' for public domain" do
      license = build(:supply_chain_license, category: "public_domain")
      expect(license.risk_level).to eq("none")
    end

    it "returns 'low' for permissive" do
      license = build(:supply_chain_license, category: "permissive")
      expect(license.risk_level).to eq("low")
    end

    it "returns 'medium' for weak copyleft" do
      license = build(:supply_chain_license, category: "weak_copyleft")
      expect(license.risk_level).to eq("medium")
    end

    it "returns 'high' for strong copyleft" do
      license = build(:supply_chain_license, category: "copyleft", is_network_copyleft: false)
      expect(license.risk_level).to eq("high")
    end

    it "returns 'critical' for network copyleft" do
      license = build(:supply_chain_license, category: "copyleft", is_network_copyleft: true)
      expect(license.risk_level).to eq("critical")
    end
  end

  describe "#compatible_with?" do
    let(:mit) { build(:supply_chain_license, spdx_id: "MIT", category: "permissive") }
    let(:apache) { build(:supply_chain_license, spdx_id: "Apache-2.0", category: "permissive") }
    let(:gpl) { build(:supply_chain_license, spdx_id: "GPL-3.0", category: "copyleft", is_copyleft: true) }
    let(:agpl) { build(:supply_chain_license, spdx_id: "AGPL-3.0", category: "copyleft", is_copyleft: true) }

    it "permissive licenses are compatible with each other" do
      expect(mit.compatible_with?(apache)).to be true
    end

    it "permissive licenses are compatible with copyleft" do
      expect(mit.compatible_with?(gpl)).to be true
    end

    it "different copyleft licenses are not compatible" do
      expect(gpl.compatible_with?(agpl)).to be false
    end
  end
end
