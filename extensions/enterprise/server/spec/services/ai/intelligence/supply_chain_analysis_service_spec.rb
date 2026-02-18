# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Intelligence::SupplyChainAnalysisService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  # Helper to create SBOM with components and vulnerabilities
  let(:sbom) do
    SupplyChain::Sbom.create!(
      account: account,
      name: "test-app",
      version: "1.0.0",
      format: "cyclonedx_1_5",
      status: "completed",
      component_count: 0,
      vulnerability_count: 0,
      risk_score: 0
    )
  end

  let(:lodash_component) do
    SupplyChain::SbomComponent.create!(
      sbom: sbom,
      account: account,
      name: "lodash",
      purl: "pkg:npm/lodash@4.17.15",
      version: "4.17.15",
      ecosystem: "npm",
      dependency_type: "direct",
      depth: 0,
      risk_score: 0,
      has_known_vulnerabilities: true,
      license_spdx_id: "MIT",
      license_compliance_status: "compliant"
    )
  end

  let(:express_component) do
    SupplyChain::SbomComponent.create!(
      sbom: sbom,
      account: account,
      name: "express",
      purl: "pkg:npm/express@4.17.1",
      version: "4.17.1",
      ecosystem: "npm",
      dependency_type: "direct",
      depth: 0,
      risk_score: 0,
      has_known_vulnerabilities: false,
      license_spdx_id: "MIT",
      license_compliance_status: "compliant"
    )
  end

  let!(:critical_vuln) do
    SupplyChain::SbomVulnerability.create!(
      sbom: sbom,
      component: lodash_component,
      account: account,
      vulnerability_id: "CVE-2021-23337",
      source: "nvd",
      severity: "critical",
      cvss_score: 9.8,
      remediation_status: "open",
      description: "Lodash prototype pollution vulnerability",
      fixed_version: "4.17.21"
    )
  end

  let!(:high_vuln) do
    SupplyChain::SbomVulnerability.create!(
      sbom: sbom,
      component: lodash_component,
      account: account,
      vulnerability_id: "CVE-2020-28500",
      source: "nvd",
      severity: "high",
      cvss_score: 7.5,
      remediation_status: "open",
      description: "ReDoS vulnerability in lodash",
      fixed_version: "4.17.21"
    )
  end

  let!(:medium_vuln_no_fix) do
    SupplyChain::SbomVulnerability.create!(
      sbom: sbom,
      component: lodash_component,
      account: account,
      vulnerability_id: "CVE-2022-99999",
      source: "nvd",
      severity: "medium",
      cvss_score: 5.3,
      remediation_status: "open",
      description: "Hypothetical medium severity issue",
      fixed_version: nil
    )
  end

  describe "#triage_vulnerabilities" do
    it "prioritizes critical vulnerabilities" do
      result = service.triage_vulnerabilities(sbom_id: sbom.id)

      expect(result[:success]).to be true
      expect(result[:prioritized]).to be_an(Array)
      expect(result[:prioritized].length).to eq(3)

      # Critical should come first (highest priority score)
      first_vuln = result[:prioritized].first
      expect(first_vuln[:severity]).to eq("critical")
      expect(first_vuln[:cve]).to eq("CVE-2021-23337")
    end

    it "considers fix availability" do
      result = service.triage_vulnerabilities(sbom_id: sbom.id)

      fixable = result[:prioritized].select { |v| v[:has_fix] }
      unfixable = result[:prioritized].reject { |v| v[:has_fix] }

      # Vulnerabilities with fixes should be prioritized higher within same severity
      expect(fixable.length).to eq(2)
      expect(unfixable.length).to eq(1)
      expect(unfixable.first[:cve]).to eq("CVE-2022-99999")
    end

    it "returns structured recommendations" do
      result = service.triage_vulnerabilities(sbom_id: sbom.id)

      expect(result[:success]).to be true
      expect(result).to include(:prioritized, :severity_breakdown, :triage_summary)
      expect(result[:severity_breakdown]).to include(:critical, :high, :medium)
    end
  end

  describe "#generate_remediation_plan" do
    it "creates an ai_generated remediation plan" do
      result = service.generate_remediation_plan(sbom_id: sbom.id)

      expect(result[:success]).to be true
      expect(result[:plan_id]).to be_present
      expect(result[:plan_type]).to eq("ai_generated")
      expect(result[:status]).to be_in(%w[draft pending_review])

      plan = SupplyChain::RemediationPlan.find(result[:plan_id])
      expect(plan.sbom).to eq(sbom)
      expect(plan.account).to eq(account)
    end

    it "includes upgrade recommendations" do
      result = service.generate_remediation_plan(sbom_id: sbom.id)

      expect(result[:upgrade_recommendations]).to be_an(Array)
      expect(result[:upgrade_recommendations]).not_to be_empty

      lodash_upgrade = result[:upgrade_recommendations].find { |r| r[:package_name] == "lodash" }
      expect(lodash_upgrade).to be_present
    end

    it "calculates confidence score" do
      result = service.generate_remediation_plan(sbom_id: sbom.id)

      expect(result[:confidence_score]).to be_a(Numeric)
      expect(result[:confidence_score]).to be_between(0.0, 1.0)
    end
  end

  describe "#security_posture" do
    it "returns overall security score" do
      result = service.security_posture(sbom_id: sbom.id)

      expect(result[:success]).to be true
      expect(result[:overall_score]).to be_a(Numeric)
      expect(result[:overall_score]).to be_between(0, 100)
    end

    it "includes breakdown by category" do
      result = service.security_posture(sbom_id: sbom.id)

      expect(result).to include(:breakdown)
      expect(result[:breakdown]).to include(:vulnerability)
      expect(result[:vulnerability_summary]).to include(:critical, :high, :medium)
      expect(result[:vulnerability_summary][:critical]).to eq(1)
      expect(result[:vulnerability_summary][:high]).to eq(1)
      expect(result[:vulnerability_summary][:medium]).to eq(1)
    end
  end
end
