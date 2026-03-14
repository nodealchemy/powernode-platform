# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::SbomDiff, type: :model do
  let(:account) { create(:account) }
  let(:base_sbom) { create(:supply_chain_sbom, account: account, risk_score: 50.0) }
  let(:target_sbom) { create(:supply_chain_sbom, account: account, risk_score: 60.0) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:base_sbom).class_name("SupplyChain::Sbom") }
    it { is_expected.to belong_to(:target_sbom).class_name("SupplyChain::Sbom") }
  end

  describe "validations" do
    subject { build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom) }

    it "validates uniqueness of base_sbom_id scoped to target_sbom_id" do
      create(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
      duplicate = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base_sbom_id]).to include("has already been taken")
    end

    describe "custom validation: sboms_belong_to_same_account" do
      it "is valid when both SBOMs belong to the same account" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        expect(diff).to be_valid
      end

      it "is invalid when SBOMs belong to different accounts" do
        other_account = create(:account)
        other_sbom = create(:supply_chain_sbom, account: other_account)
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: other_sbom)

        expect(diff).not_to be_valid
        expect(diff.errors[:base]).to include("SBOMs must belong to the same account")
      end

      it "skips validation when base_sbom is nil" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: nil, target_sbom: target_sbom)
        diff.valid?
        expect(diff.errors[:base]).not_to include("SBOMs must belong to the same account")
      end

      it "skips validation when target_sbom is nil" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: nil)
        diff.valid?
        expect(diff.errors[:base]).not_to include("SBOMs must belong to the same account")
      end
    end
  end

  describe "scopes" do
    let!(:recent_diff) { create(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom, created_at: 1.hour.ago) }
    let!(:old_diff) do
      new_target = create(:supply_chain_sbom, account: account)
      create(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: new_target, created_at: 1.week.ago)
    end
    let!(:diff_with_changes) do
      new_target = create(:supply_chain_sbom, account: account)
      create(:supply_chain_sbom_diff, :with_changes, account: account, base_sbom: base_sbom, target_sbom: new_target)
    end
    let!(:diff_no_changes) do
      new_target = create(:supply_chain_sbom, account: account)
      create(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: new_target,
        added_count: 0, removed_count: 0, updated_count: 0)
    end
    let!(:diff_with_new_vulns) do
      new_target = create(:supply_chain_sbom, account: account)
      create(:supply_chain_sbom_diff, :with_new_vulnerabilities, account: account, base_sbom: base_sbom, target_sbom: new_target)
    end
    let!(:diff_no_new_vulns) do
      new_target = create(:supply_chain_sbom, account: account)
      create(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: new_target,
        new_vulnerabilities: [])
    end
    let!(:diff_risk_up) do
      new_target = create(:supply_chain_sbom, account: account)
      create(:supply_chain_sbom_diff, :risk_increased, account: account, base_sbom: base_sbom, target_sbom: new_target)
    end
    let!(:diff_risk_down) do
      new_target = create(:supply_chain_sbom, account: account)
      create(:supply_chain_sbom_diff, :risk_decreased, account: account, base_sbom: base_sbom, target_sbom: new_target)
    end

    describe ".recent" do
      it "orders by created_at descending" do
        results = described_class.recent
        expect(results.first.created_at).to be >= results.last.created_at
      end
    end

    describe ".with_changes" do
      it "includes diffs with added components" do
        expect(described_class.with_changes).to include(diff_with_changes)
      end

      it "excludes diffs with no changes" do
        expect(described_class.with_changes).not_to include(diff_no_changes)
      end
    end

    describe ".with_new_vulnerabilities" do
      it "includes diffs with new vulnerabilities" do
        expect(described_class.with_new_vulnerabilities).to include(diff_with_new_vulns)
      end

      it "excludes diffs without new vulnerabilities" do
        expect(described_class.with_new_vulnerabilities).not_to include(diff_no_new_vulns)
      end
    end

    describe ".risk_increased" do
      it "includes diffs with positive risk delta" do
        expect(described_class.risk_increased).to include(diff_risk_up)
      end

      it "excludes diffs with negative risk delta" do
        expect(described_class.risk_increased).not_to include(diff_risk_down)
      end
    end

    describe ".risk_decreased" do
      it "includes diffs with negative risk delta" do
        expect(described_class.risk_decreased).to include(diff_risk_down)
      end

      it "excludes diffs with positive risk delta" do
        expect(described_class.risk_decreased).not_to include(diff_risk_up)
      end
    end
  end

  describe "callbacks" do
    describe "before_validation: set_account_from_base_sbom" do
      it "sets account from base_sbom when account is nil" do
        diff = described_class.new(base_sbom: base_sbom, target_sbom: target_sbom)
        diff.valid?
        expect(diff.account).to eq(base_sbom.account)
      end

      it "does not override existing account" do
        other_account = create(:account)
        diff = described_class.new(account: other_account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.valid?
        expect(diff.account).to eq(other_account)
      end

      it "does not fail when base_sbom is nil" do
        diff = described_class.new(target_sbom: target_sbom)
        expect { diff.valid? }.not_to raise_error
      end
    end

    describe "before_save: sanitize_jsonb_fields" do
      # Note: Database has NOT NULL constraints, so we test the callback behavior
      # by building records and verifying the callback sets proper defaults

      it "ensures added_components defaults to empty array" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.added_components = nil
        diff.run_callbacks(:save) { false } # run callbacks without saving
        expect(diff.added_components).to eq([])
      end

      it "ensures removed_components defaults to empty array" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.removed_components = nil
        diff.run_callbacks(:save) { false }
        expect(diff.removed_components).to eq([])
      end

      it "ensures updated_components defaults to empty array" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.updated_components = nil
        diff.run_callbacks(:save) { false }
        expect(diff.updated_components).to eq([])
      end

      it "ensures new_vulnerabilities defaults to empty array" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.new_vulnerabilities = nil
        diff.run_callbacks(:save) { false }
        expect(diff.new_vulnerabilities).to eq([])
      end

      it "ensures resolved_vulnerabilities defaults to empty array" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.resolved_vulnerabilities = nil
        diff.run_callbacks(:save) { false }
        expect(diff.resolved_vulnerabilities).to eq([])
      end

      it "ensures metadata defaults to empty hash" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.metadata = nil
        diff.run_callbacks(:save) { false }
        expect(diff.metadata).to eq({})
      end
    end

    describe "after_create: compute_diff" do
      it "is called after record creation" do
        diff = build(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        expect(diff).to receive(:compute_diff)
        diff.save!
      end
    end
  end

  describe "#has_changes?" do
    it "returns true when there are added components" do
      diff = build(:supply_chain_sbom_diff, added_count: 1, removed_count: 0, updated_count: 0)
      expect(diff.has_changes?).to be true
    end

    it "returns true when there are removed components" do
      diff = build(:supply_chain_sbom_diff, added_count: 0, removed_count: 1, updated_count: 0)
      expect(diff.has_changes?).to be true
    end

    it "returns true when there are updated components" do
      diff = build(:supply_chain_sbom_diff, added_count: 0, removed_count: 0, updated_count: 1)
      expect(diff.has_changes?).to be true
    end

    it "returns false when there are no changes" do
      diff = build(:supply_chain_sbom_diff, added_count: 0, removed_count: 0, updated_count: 0)
      expect(diff.has_changes?).to be false
    end
  end

  describe "#has_new_vulnerabilities?" do
    it "returns true when new_vulnerabilities is present and not empty" do
      diff = build(:supply_chain_sbom_diff, new_vulnerabilities: [ { vulnerability_id: "CVE-2024-1234" } ])
      expect(diff.has_new_vulnerabilities?).to be true
    end

    it "returns false when new_vulnerabilities is empty array" do
      diff = build(:supply_chain_sbom_diff, new_vulnerabilities: [])
      expect(diff.has_new_vulnerabilities?).to be false
    end

    it "returns false when new_vulnerabilities is nil" do
      diff = build(:supply_chain_sbom_diff, new_vulnerabilities: nil)
      expect(diff.has_new_vulnerabilities?).to be false
    end
  end

  describe "#has_resolved_vulnerabilities?" do
    it "returns true when resolved_vulnerabilities is present and not empty" do
      diff = build(:supply_chain_sbom_diff, resolved_vulnerabilities: [ { vulnerability_id: "CVE-2023-5678" } ])
      expect(diff.has_resolved_vulnerabilities?).to be true
    end

    it "returns false when resolved_vulnerabilities is empty array" do
      diff = build(:supply_chain_sbom_diff, resolved_vulnerabilities: [])
      expect(diff.has_resolved_vulnerabilities?).to be false
    end

    it "returns false when resolved_vulnerabilities is nil" do
      diff = build(:supply_chain_sbom_diff, resolved_vulnerabilities: nil)
      expect(diff.has_resolved_vulnerabilities?).to be false
    end
  end

  describe "#risk_increased?" do
    it "returns true when risk_delta is positive" do
      diff = build(:supply_chain_sbom_diff, risk_delta: 10.5)
      expect(diff.risk_increased?).to be true
    end

    it "returns false when risk_delta is zero" do
      diff = build(:supply_chain_sbom_diff, risk_delta: 0)
      expect(diff.risk_increased?).to be false
    end

    it "returns false when risk_delta is negative" do
      diff = build(:supply_chain_sbom_diff, risk_delta: -5.5)
      expect(diff.risk_increased?).to be false
    end

    it "returns false when risk_delta is nil" do
      diff = build(:supply_chain_sbom_diff, risk_delta: nil)
      expect(diff.risk_increased?).to be false
    end
  end

  describe "#risk_decreased?" do
    it "returns true when risk_delta is negative" do
      diff = build(:supply_chain_sbom_diff, risk_delta: -10.5)
      expect(diff.risk_decreased?).to be true
    end

    it "returns false when risk_delta is zero" do
      diff = build(:supply_chain_sbom_diff, risk_delta: 0)
      expect(diff.risk_decreased?).to be false
    end

    it "returns false when risk_delta is positive" do
      diff = build(:supply_chain_sbom_diff, risk_delta: 5.5)
      expect(diff.risk_decreased?).to be false
    end

    it "returns false when risk_delta is nil" do
      diff = build(:supply_chain_sbom_diff, risk_delta: nil)
      expect(diff.risk_decreased?).to be false
    end
  end

  describe "#total_changes" do
    it "returns sum of all change counts" do
      diff = build(:supply_chain_sbom_diff, added_count: 3, removed_count: 2, updated_count: 5)
      expect(diff.total_changes).to eq(10)
    end

    it "returns 0 when all counts are 0" do
      diff = build(:supply_chain_sbom_diff, added_count: 0, removed_count: 0, updated_count: 0)
      expect(diff.total_changes).to eq(0)
    end
  end

  describe "#compute_diff" do
    let(:base_sbom) { create(:supply_chain_sbom, account: account, risk_score: 40.0) }
    let(:target_sbom) { create(:supply_chain_sbom, account: account, risk_score: 55.0) }

    context "when components are added" do
      before do
        # Create components only in target SBOM
        create(:supply_chain_sbom_component, sbom: target_sbom, account: account,
          purl: "pkg:npm/new-package@1.0.0", name: "new-package", version: "1.0.0",
          ecosystem: "npm", license_spdx_id: "MIT")
      end

      it "detects added components" do
        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.added_count).to eq(1)
        expect(diff.added_components.first["name"]).to eq("new-package")
        expect(diff.added_components.first["version"]).to eq("1.0.0")
      end
    end

    context "when components are removed" do
      before do
        # Create components only in base SBOM
        create(:supply_chain_sbom_component, sbom: base_sbom, account: account,
          purl: "pkg:npm/old-package@0.9.0", name: "old-package", version: "0.9.0",
          ecosystem: "npm", license_spdx_id: "MIT")
      end

      it "detects removed components" do
        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.removed_count).to eq(1)
        expect(diff.removed_components.first["name"]).to eq("old-package")
        expect(diff.removed_components.first["version"]).to eq("0.9.0")
      end
    end

    context "when components are updated (version changes)" do
      before do
        # Create same component with different versions
        create(:supply_chain_sbom_component, sbom: base_sbom, account: account,
          purl: "pkg:npm/lodash@4.17.20", name: "lodash", version: "4.17.20",
          ecosystem: "npm", namespace: nil, license_spdx_id: "MIT")
        create(:supply_chain_sbom_component, sbom: target_sbom, account: account,
          purl: "pkg:npm/lodash@4.17.21", name: "lodash", version: "4.17.21",
          ecosystem: "npm", namespace: nil, license_spdx_id: "MIT")
      end

      it "detects updated components" do
        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.updated_count).to eq(1)
        expect(diff.updated_components.first["name"]).to eq("lodash")
        expect(diff.updated_components.first["old_version"]).to eq("4.17.20")
        expect(diff.updated_components.first["new_version"]).to eq("4.17.21")
      end
    end

    context "when components remain unchanged" do
      before do
        # Create same component with same version in both SBOMs
        create(:supply_chain_sbom_component, sbom: base_sbom, account: account,
          purl: "pkg:npm/express@4.18.0", name: "express", version: "4.18.0",
          ecosystem: "npm", namespace: nil, license_spdx_id: "MIT")
        create(:supply_chain_sbom_component, sbom: target_sbom, account: account,
          purl: "pkg:npm/express@4.18.0", name: "express", version: "4.18.0",
          ecosystem: "npm", namespace: nil, license_spdx_id: "MIT")
      end

      it "does not count unchanged components" do
        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.added_count).to eq(0)
        expect(diff.removed_count).to eq(0)
        expect(diff.updated_count).to eq(0)
      end
    end

    context "when new vulnerabilities are introduced" do
      let(:component) { create(:supply_chain_sbom_component, sbom: target_sbom, account: account) }

      before do
        # Create vulnerability only in target SBOM
        create(:supply_chain_sbom_vulnerability, sbom: target_sbom, component: component, account: account,
          vulnerability_id: "CVE-2024-12345", severity: "critical", cvss_score: 9.8,
          fixed_version: "2.0.1")
      end

      it "detects new vulnerabilities" do
        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.new_vulnerabilities).to be_present
        expect(diff.new_vulnerabilities.first["vulnerability_id"]).to eq("CVE-2024-12345")
        expect(diff.new_vulnerabilities.first["severity"]).to eq("critical")
        expect(diff.new_vulnerabilities.first["cvss_score"].to_f).to eq(9.8)
      end
    end

    context "when vulnerabilities are resolved" do
      let(:base_component) { create(:supply_chain_sbom_component, sbom: base_sbom, account: account) }

      before do
        # Create vulnerability only in base SBOM
        create(:supply_chain_sbom_vulnerability, sbom: base_sbom, component: base_component, account: account,
          vulnerability_id: "CVE-2023-54321", severity: "high", cvss_score: 7.5,
          fixed_version: "1.5.0")
      end

      it "detects resolved vulnerabilities" do
        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.resolved_vulnerabilities).to be_present
        expect(diff.resolved_vulnerabilities.first["vulnerability_id"]).to eq("CVE-2023-54321")
        expect(diff.resolved_vulnerabilities.first["severity"]).to eq("high")
      end
    end

    context "when risk score changes" do
      it "calculates positive risk delta when risk increases" do
        base_sbom.update!(risk_score: 30.0)
        target_sbom.update!(risk_score: 50.0)

        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.risk_delta).to eq(20.0)
      end

      it "calculates negative risk delta when risk decreases" do
        base_sbom.update!(risk_score: 70.0)
        target_sbom.update!(risk_score: 45.0)

        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.risk_delta).to eq(-25.0)
      end

      it "rounds risk delta to 2 decimal places" do
        base_sbom.update!(risk_score: 33.333)
        target_sbom.update!(risk_score: 66.667)

        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        # 66.667 - 33.333 = 33.334, rounds to 33.33 or 33.34 depending on rounding mode
        expect(diff.risk_delta.to_f).to be_within(0.02).of(33.33)
      end
    end

    context "with complex scenario" do
      let!(:base_comp1) do
        create(:supply_chain_sbom_component, sbom: base_sbom, account: account,
          purl: "pkg:npm/lodash@4.17.20", name: "lodash", version: "4.17.20",
          ecosystem: "npm", namespace: nil, license_spdx_id: "MIT")
      end
      let!(:base_comp2) do
        create(:supply_chain_sbom_component, sbom: base_sbom, account: account,
          purl: "pkg:npm/moment@2.29.0", name: "moment", version: "2.29.0",
          ecosystem: "npm", namespace: nil, license_spdx_id: "MIT")
      end

      before do
        # Updated component: lodash version changed
        create(:supply_chain_sbom_component, sbom: target_sbom, account: account,
          purl: "pkg:npm/lodash@4.17.21", name: "lodash", version: "4.17.21",
          ecosystem: "npm", namespace: nil, license_spdx_id: "MIT")

        # Removed component: moment removed from target
        # (base_comp2 exists only in base)

        # Added component: new package in target
        create(:supply_chain_sbom_component, sbom: target_sbom, account: account,
          purl: "pkg:npm/axios@1.0.0", name: "axios", version: "1.0.0",
          ecosystem: "npm", namespace: nil, license_spdx_id: "MIT")

        # Vulnerability in base
        create(:supply_chain_sbom_vulnerability, sbom: base_sbom, component: base_comp1, account: account,
          vulnerability_id: "CVE-2023-11111", severity: "medium", cvss_score: 5.5)
      end

      it "computes all changes correctly" do
        diff = described_class.new(account: account, base_sbom: base_sbom, target_sbom: target_sbom)
        diff.save!

        expect(diff.added_count).to eq(1)
        expect(diff.removed_count).to eq(1)
        expect(diff.updated_count).to eq(1)
        expect(diff.resolved_vulnerabilities.length).to eq(1)
        expect(diff.total_changes).to eq(3)
      end
    end
  end

  describe "#summary" do
    let(:diff) { create(:supply_chain_sbom_diff, :with_changes, account: account, base_sbom: base_sbom, target_sbom: target_sbom) }

    it "returns a hash with expected keys" do
      summary = diff.summary

      expect(summary).to include(
        :id,
        :base_sbom_id,
        :target_sbom_id,
        :added_count,
        :removed_count,
        :updated_count,
        :new_vulnerability_count,
        :resolved_vulnerability_count,
        :risk_delta,
        :has_changes,
        :created_at
      )
    end

    it "returns correct values" do
      summary = diff.summary

      expect(summary[:id]).to eq(diff.id)
      expect(summary[:base_sbom_id]).to eq(base_sbom.id)
      expect(summary[:target_sbom_id]).to eq(target_sbom.id)
      expect(summary[:has_changes]).to be true
    end

    it "calculates vulnerability counts from arrays" do
      diff = create(:supply_chain_sbom_diff, :with_new_vulnerabilities, :with_resolved_vulnerabilities,
        account: account, base_sbom: base_sbom, target_sbom: target_sbom)

      summary = diff.summary

      expect(summary[:new_vulnerability_count]).to eq(1)
      expect(summary[:resolved_vulnerability_count]).to eq(1)
    end

    it "handles empty vulnerabilities arrays" do
      # Note: DB has NOT NULL constraints, so we test with empty arrays
      diff = create(:supply_chain_sbom_diff, account: account, base_sbom: base_sbom, target_sbom: target_sbom,
        new_vulnerabilities: [], resolved_vulnerabilities: [])

      summary = diff.summary

      expect(summary[:new_vulnerability_count]).to eq(0)
      expect(summary[:resolved_vulnerability_count]).to eq(0)
    end
  end

  describe "#detailed_report" do
    let(:diff) { create(:supply_chain_sbom_diff, :with_changes, :with_new_vulnerabilities,
      account: account, base_sbom: base_sbom, target_sbom: target_sbom) }

    it "returns a hash with summary and details" do
      report = diff.detailed_report

      expect(report).to include(
        :summary,
        :added_components,
        :removed_components,
        :updated_components,
        :new_vulnerabilities,
        :resolved_vulnerabilities
      )
    end

    it "includes summary data" do
      report = diff.detailed_report

      expect(report[:summary]).to be_a(Hash)
      expect(report[:summary][:id]).to eq(diff.id)
    end

    it "includes component change details" do
      report = diff.detailed_report

      expect(report[:added_components]).to eq(diff.added_components)
      expect(report[:removed_components]).to eq(diff.removed_components)
      expect(report[:updated_components]).to eq(diff.updated_components)
    end

    it "includes vulnerability details" do
      report = diff.detailed_report

      expect(report[:new_vulnerabilities]).to eq(diff.new_vulnerabilities)
      expect(report[:resolved_vulnerabilities]).to eq(diff.resolved_vulnerabilities)
    end
  end
end
