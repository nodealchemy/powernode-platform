# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::SbomComponent, type: :model do
  let(:account) { create(:account) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:sbom).class_name("SupplyChain::Sbom") }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:vulnerabilities).class_name("SupplyChain::SbomVulnerability").dependent(:destroy) }
    it { is_expected.to have_many(:license_detections).class_name("SupplyChain::LicenseDetection").dependent(:destroy) }
    it { is_expected.to have_many(:license_violations).class_name("SupplyChain::LicenseViolation").dependent(:destroy) }
    it { is_expected.to have_one(:attribution).class_name("SupplyChain::Attribution").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:supply_chain_sbom_component, sbom: sbom, account: account) }

    it { is_expected.to validate_presence_of(:purl) }

    it "validates uniqueness of purl scoped to sbom_id" do
      first = create(:supply_chain_sbom_component, sbom: sbom, account: account, purl: "pkg:npm/test@1.0.0")
      duplicate = build(:supply_chain_sbom_component, sbom: sbom, account: account, purl: "pkg:npm/test@1.0.0")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:purl]).to include("has already been taken")

      # Different SBOM should be valid
      other_sbom = create(:supply_chain_sbom, account: account)
      different_sbom_component = build(:supply_chain_sbom_component, sbom: other_sbom, account: account, purl: "pkg:npm/test@1.0.0")
      expect(different_sbom_component).to be_valid
    end

    # Note: name and ecosystem are auto-filled from PURL by before_validation callback.
    # These tests verify the validation exists by using an invalid PURL that doesn't
    # parse to valid name/ecosystem values.
    it "validates presence of name (not auto-filled by invalid purl)" do
      component = build(:supply_chain_sbom_component, sbom: sbom, account: account, purl: "invalid", name: nil, ecosystem: "npm")
      expect(component).not_to be_valid
      expect(component.errors[:name]).to include("can't be blank")
    end

    it "validates presence of ecosystem (not auto-filled by invalid purl)" do
      component = build(:supply_chain_sbom_component, sbom: sbom, account: account, purl: "invalid", ecosystem: nil, name: "test")
      expect(component).not_to be_valid
      expect(component.errors[:ecosystem]).to include("can't be blank")
    end
    it { is_expected.to validate_inclusion_of(:ecosystem).in_array(SupplyChain::SbomComponent::ECOSYSTEMS) }
    it { is_expected.to validate_presence_of(:dependency_type) }
    it { is_expected.to validate_inclusion_of(:dependency_type).in_array(SupplyChain::SbomComponent::DEPENDENCY_TYPES) }
    it { is_expected.to validate_numericality_of(:depth).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:risk_score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
  end

  describe "scopes" do
    let!(:npm_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, ecosystem: "npm") }
    let!(:gem_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, ecosystem: "gem") }
    let!(:direct_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, dependency_type: "direct", depth: 0) }
    let!(:transitive_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, dependency_type: "transitive", depth: 2) }
    let!(:dev_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, dependency_type: "dev") }
    let!(:vulnerable_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, has_known_vulnerabilities: true) }
    let!(:safe_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, has_known_vulnerabilities: false) }
    let!(:outdated_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, is_outdated: true) }
    let!(:high_risk_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, risk_score: 85) }
    let!(:low_risk_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, risk_score: 20) }
    let!(:mit_licensed) { create(:supply_chain_sbom_component, sbom: sbom, account: account, license_spdx_id: "MIT") }
    let!(:unlicensed) { create(:supply_chain_sbom_component, sbom: sbom, account: account, license_spdx_id: nil) }

    it "filters by ecosystem" do
      expect(described_class.by_ecosystem("npm")).to include(npm_component)
      expect(described_class.by_ecosystem("npm")).not_to include(gem_component)
    end

    it "filters direct dependencies" do
      expect(described_class.direct).to include(direct_component)
      expect(described_class.direct).not_to include(transitive_component)
    end

    it "filters transitive dependencies" do
      expect(described_class.transitive).to include(transitive_component)
      expect(described_class.transitive).not_to include(direct_component)
    end

    it "filters dev dependencies" do
      expect(described_class.dev_dependencies).to include(dev_component)
      expect(described_class.dev_dependencies).not_to include(direct_component)
    end

    it "filters vulnerable components" do
      expect(described_class.vulnerable).to include(vulnerable_component)
      expect(described_class.vulnerable).not_to include(safe_component)
    end

    it "filters outdated components" do
      expect(described_class.outdated).to include(outdated_component)
    end

    it "filters high risk components" do
      expect(described_class.high_risk).to include(high_risk_component)
      expect(described_class.high_risk).not_to include(low_risk_component)
    end

    it "filters by license" do
      expect(described_class.by_license("MIT")).to include(mit_licensed)
      expect(described_class.by_license("MIT")).not_to include(unlicensed)
    end

    it "filters unlicensed components" do
      expect(described_class.unlicensed).to include(unlicensed)
      expect(described_class.unlicensed).not_to include(mit_licensed)
    end

    it "orders by risk descending" do
      ordered = described_class.ordered_by_risk
      expect(ordered.first.risk_score).to be >= ordered.last.risk_score
    end

    it "orders by depth ascending" do
      ordered = described_class.ordered_by_depth
      expect(ordered.first.depth).to be <= ordered.last.depth
    end
  end

  describe "dependency type predicates" do
    describe "#direct?" do
      it "returns true for direct dependencies" do
        component = build(:supply_chain_sbom_component, dependency_type: "direct")
        expect(component.direct?).to be true
      end

      it "returns false for transitive dependencies" do
        component = build(:supply_chain_sbom_component, dependency_type: "transitive")
        expect(component.direct?).to be false
      end
    end

    describe "#transitive?" do
      it "returns true for transitive dependencies" do
        component = build(:supply_chain_sbom_component, dependency_type: "transitive")
        expect(component.transitive?).to be true
      end

      it "returns false for direct dependencies" do
        component = build(:supply_chain_sbom_component, dependency_type: "direct")
        expect(component.transitive?).to be false
      end
    end

    describe "#dev?" do
      it "returns true for dev dependencies" do
        component = build(:supply_chain_sbom_component, dependency_type: "dev")
        expect(component.dev?).to be true
      end
    end
  end

  describe "#vulnerable?" do
    it "returns true when has_known_vulnerabilities is true" do
      component = build(:supply_chain_sbom_component, has_known_vulnerabilities: true)
      expect(component.vulnerable?).to be true
    end

    it "returns false when has_known_vulnerabilities is false" do
      component = build(:supply_chain_sbom_component, has_known_vulnerabilities: false)
      expect(component.vulnerable?).to be false
    end
  end

  describe "#outdated?" do
    it "returns true when is_outdated is true" do
      component = build(:supply_chain_sbom_component, is_outdated: true)
      expect(component.outdated?).to be true
    end

    it "returns false when is_outdated is false" do
      component = build(:supply_chain_sbom_component, is_outdated: false)
      expect(component.outdated?).to be false
    end
  end

  describe "license compliance methods" do
    describe "#license_compliant?" do
      it "returns true when status is compliant" do
        component = build(:supply_chain_sbom_component, license_compliance_status: "compliant")
        expect(component.license_compliant?).to be true
      end

      it "returns false when status is non_compliant" do
        component = build(:supply_chain_sbom_component, license_compliance_status: "non_compliant")
        expect(component.license_compliant?).to be false
      end
    end

    describe "#needs_license_review?" do
      it "returns true when status is review_required" do
        component = build(:supply_chain_sbom_component, license_compliance_status: "review_required")
        expect(component.needs_license_review?).to be true
      end

      it "returns true when status is unknown" do
        component = build(:supply_chain_sbom_component, license_compliance_status: "unknown")
        expect(component.needs_license_review?).to be true
      end

      it "returns false when status is compliant" do
        component = build(:supply_chain_sbom_component, license_compliance_status: "compliant")
        expect(component.needs_license_review?).to be false
      end
    end
  end

  describe "#full_name" do
    it "returns name with namespace" do
      component = build(:supply_chain_sbom_component, namespace: "@myorg", name: "mypackage")
      expect(component.full_name).to eq("@myorg/mypackage")
    end

    it "returns name without namespace" do
      component = build(:supply_chain_sbom_component, namespace: nil, name: "mypackage")
      expect(component.full_name).to eq("mypackage")
    end
  end

  describe "#versioned_name" do
    it "returns full name with version" do
      component = build(:supply_chain_sbom_component, name: "lodash", version: "4.17.21", namespace: nil)
      expect(component.versioned_name).to eq("lodash@4.17.21")
    end

    it "handles missing version" do
      component = build(:supply_chain_sbom_component, name: "lodash", version: nil, namespace: nil)
      expect(component.versioned_name).to eq("lodash@unknown")
    end
  end

  describe "#calculate_risk_score" do
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, dependency_type: "direct", depth: 0) }

    it "calculates risk based on vulnerabilities" do
      create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "critical")
      create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "high")

      component.reload
      component.calculate_risk_score

      expect(component.risk_score).to be >= 30 # 20 (critical) + 10 (high)
    end

    it "adds license risk for non-compliant licenses" do
      component.license_compliance_status = "non_compliant"
      component.calculate_risk_score
      expect(component.risk_score).to be >= 20
    end

    it "adds risk for outdated components" do
      component.is_outdated = true
      component.calculate_risk_score
      expect(component.risk_score).to be >= 15
    end

    it "adds risk for transitive depth" do
      component.update!(dependency_type: "transitive", depth: 3)
      component.calculate_risk_score
      expect(component.risk_score).to be >= 9 # 3 * 3 = 9
    end

    it "caps risk score at 100" do
      component.license_compliance_status = "non_compliant"
      component.is_outdated = true
      5.times do
        create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "critical")
      end
      component.reload
      component.calculate_risk_score
      expect(component.risk_score).to be <= 100
    end
  end

  describe "#critical_vulnerabilities" do
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }

    it "returns only critical vulnerabilities" do
      critical = create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "critical")
      high = create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "high")

      expect(component.critical_vulnerabilities).to include(critical)
      expect(component.critical_vulnerabilities).not_to include(high)
    end
  end

  describe "#high_vulnerabilities" do
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }

    it "returns only high vulnerabilities" do
      critical = create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "critical")
      high = create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "high")

      expect(component.high_vulnerabilities).to include(high)
      expect(component.high_vulnerabilities).not_to include(critical)
    end
  end

  describe "#summary" do
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, license_spdx_id: "MIT") }

    it "returns a summary hash with expected keys" do
      summary = component.summary

      expect(summary).to include(
        :id,
        :purl,
        :name,
        :version,
        :ecosystem,
        :dependency_type,
        :depth,
        :license,
        :license_compliant,
        :vulnerable,
        :vulnerability_count,
        :risk_score
      )
    end
  end

  describe "#to_cyclonedx" do
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, license_spdx_id: "MIT") }

    it "returns CycloneDX format" do
      cdx = component.to_cyclonedx

      expect(cdx).to include("type", "bom-ref", "name", "version", "purl", "licenses", "properties")
      expect(cdx["licenses"]).to be_an(Array)
    end
  end

  describe "#to_spdx" do
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, license_spdx_id: "MIT") }

    it "returns SPDX format" do
      spdx = component.to_spdx

      expect(spdx).to include("SPDXID", "name", "versionInfo", "downloadLocation", "licenseConcluded", "externalRefs")
      expect(spdx["licenseConcluded"]).to eq("MIT")
    end
  end

  describe "PURL parsing callback" do
    it "parses ecosystem from purl" do
      component = build(:supply_chain_sbom_component,
                       sbom: sbom,
                       account: account,
                       purl: "pkg:npm/@scope/package@1.0.0",
                       ecosystem: nil,
                       name: "package")
      component.save!

      expect(component.ecosystem).to eq("npm")
    end

    it "parses namespace from purl" do
      component = build(:supply_chain_sbom_component,
                       sbom: sbom,
                       account: account,
                       purl: "pkg:npm/@scope/package@1.0.0",
                       namespace: nil,
                       name: "package",
                       ecosystem: "npm")
      component.save!

      expect(component.namespace).to eq("@scope")
    end

    it "parses version from purl" do
      component = build(:supply_chain_sbom_component,
                       sbom: sbom,
                       account: account,
                       purl: "pkg:npm/lodash@4.17.21",
                       version: nil,
                       name: "lodash",
                       ecosystem: "npm")
      component.save!

      expect(component.version).to eq("4.17.21")
    end

    it "maps pypi to pip ecosystem" do
      component = build(:supply_chain_sbom_component,
                       sbom: sbom,
                       account: account,
                       purl: "pkg:pypi/requests@2.28.0",
                       ecosystem: nil,
                       name: "requests")
      component.save!

      expect(component.ecosystem).to eq("pip")
    end
  end

  describe "JSONB sanitization" do
    it "initializes metadata as empty hash" do
      component = create(:supply_chain_sbom_component, sbom: sbom, account: account, metadata: nil)
      component.reload
      expect(component.metadata).to eq({})
    end

    it "initializes properties as empty hash" do
      component = create(:supply_chain_sbom_component, sbom: sbom, account: account, properties: nil)
      component.reload
      expect(component.properties).to eq({})
    end
  end

  describe "after_save callback" do
    it "calls update_sbom_counters when has_known_vulnerabilities changes" do
      fresh_sbom = create(:supply_chain_sbom, :no_vulnerabilities, account: account)
      component = create(:supply_chain_sbom_component, sbom: fresh_sbom, account: account, has_known_vulnerabilities: false)

      # Verify the callback method is called when the flag changes
      expect(component).to receive(:update_sbom_counters).and_call_original
      component.update!(has_known_vulnerabilities: true)
    end

    it "does not call update_sbom_counters when has_known_vulnerabilities is unchanged" do
      fresh_sbom = create(:supply_chain_sbom, :no_vulnerabilities, account: account)
      component = create(:supply_chain_sbom_component, sbom: fresh_sbom, account: account, has_known_vulnerabilities: false)

      # Update something else - callback should not fire
      expect(component).not_to receive(:update_sbom_counters)
      component.update!(risk_score: 50)
    end

    it "update_sbom_counters method updates vulnerability_count correctly" do
      fresh_sbom = create(:supply_chain_sbom, :no_vulnerabilities, account: account)
      component = create(:supply_chain_sbom_component, sbom: fresh_sbom, account: account, has_known_vulnerabilities: false)

      # Create a vulnerability
      create(:supply_chain_sbom_vulnerability, sbom: fresh_sbom, component: component, account: account)

      # Verify vulnerability exists
      expect(fresh_sbom.vulnerabilities.count).to eq(1)

      # Call the private method directly
      component.send(:update_sbom_counters)

      # The method should have updated the sbom's vulnerability_count
      expect(fresh_sbom.reload.vulnerability_count).to eq(1)
    end
  end
end
