# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::RiskCalculationService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  # Use a fully "clean" SBOM to avoid supply_chain_score contributions in most tests
  # This is signed, NTIA compliant, and will have an attestation created below
  let(:sbom) { create(:supply_chain_sbom, :signed, :ntia_compliant, account: account, metadata: {}) }
  let!(:attestation) { create(:supply_chain_attestation, account: account, sbom: sbom) }
  let(:service) { described_class.new(sbom: sbom) }

  describe "#initialize" do
    it "initializes with sbom" do
      expect(service.sbom).to eq(sbom)
    end

    it "initializes logger" do
      expect(service.instance_variable_get(:@logger)).to eq(Rails.logger)
    end
  end

  describe "#calculate!" do
    context "with empty SBOM" do
      it "calculates zero risk score for empty vulnerabilities" do
        result = service.calculate!

        expect(sbom.reload.risk_score).to eq(0)
        expect(sbom.metadata["risk_breakdown"]["vulnerability_score"]).to eq(0)
      end

      it "calculates zero risk score for empty components" do
        result = service.calculate!

        expect(sbom.reload.metadata["risk_breakdown"]["license_score"]).to eq(0)
        expect(sbom.metadata["risk_breakdown"]["dependency_score"]).to eq(0)
      end

      it "stores risk_calculated_at timestamp" do
        freeze_time do
          service.calculate!
          expect(sbom.reload.metadata["risk_calculated_at"]).to eq(Time.current.iso8601)
        end
      end

      it "returns the calculated overall score" do
        result = service.calculate!
        expect(result).to eq(sbom.reload.risk_score)
      end
    end

    context "with vulnerabilities" do
      context "critical vulnerabilities" do
        before do
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          create_list(:supply_chain_sbom_vulnerability, 2,
                     sbom: sbom, component: component, account: account, severity: "critical")
        end

        it "applies critical weight (25 per vuln)" do
          service.calculate!
          vulnerability_score = sbom.reload.metadata["risk_breakdown"]["vulnerability_score"]
          expect(vulnerability_score).to eq(50) # 2 * 25
        end

        it "applies 40% weight to vulnerability score in overall calculation" do
          service.calculate!
          expected_overall = (50 * 0.4).round(2)
          expect(sbom.reload.risk_score).to eq(expected_overall)
        end
      end

      context "high vulnerabilities" do
        before do
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          create_list(:supply_chain_sbom_vulnerability, 3,
                     sbom: sbom, component: component, account: account, severity: "high")
        end

        it "applies high weight (15 per vuln)" do
          service.calculate!
          vulnerability_score = sbom.reload.metadata["risk_breakdown"]["vulnerability_score"]
          expect(vulnerability_score).to eq(45) # 3 * 15
        end
      end

      context "medium vulnerabilities" do
        before do
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          create_list(:supply_chain_sbom_vulnerability, 4,
                     sbom: sbom, component: component, account: account, severity: "medium")
        end

        it "applies medium weight (5 per vuln)" do
          service.calculate!
          vulnerability_score = sbom.reload.metadata["risk_breakdown"]["vulnerability_score"]
          expect(vulnerability_score).to eq(20) # 4 * 5
        end
      end

      context "low vulnerabilities" do
        before do
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          create_list(:supply_chain_sbom_vulnerability, 5,
                     sbom: sbom, component: component, account: account, severity: "low")
        end

        it "applies low weight (1 per vuln)" do
          service.calculate!
          vulnerability_score = sbom.reload.metadata["risk_breakdown"]["vulnerability_score"]
          expect(vulnerability_score).to eq(5) # 5 * 1
        end
      end

      context "mixed severity vulnerabilities" do
        before do
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          create(:supply_chain_sbom_vulnerability,
                sbom: sbom, component: component, account: account, severity: "critical")
          create(:supply_chain_sbom_vulnerability,
                sbom: sbom, component: component, account: account, severity: "high")
          create(:supply_chain_sbom_vulnerability,
                sbom: sbom, component: component, account: account, severity: "medium")
          create(:supply_chain_sbom_vulnerability,
                sbom: sbom, component: component, account: account, severity: "low")
        end

        it "calculates combined penalty correctly" do
          service.calculate!
          vulnerability_score = sbom.reload.metadata["risk_breakdown"]["vulnerability_score"]
          expected = (1 * 25) + (1 * 15) + (1 * 5) + (1 * 1) # 46
          expect(vulnerability_score).to eq(expected)
        end
      end

      context "unfixed critical vulnerabilities" do
        before do
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          create_list(:supply_chain_sbom_vulnerability, 2,
                     sbom: sbom,
                     component: component,
                     account: account,
                     severity: "critical",
                     remediation_status: "open",
                     fixed_version: nil)
        end

        it "applies extra penalty (10 per unfixed critical)" do
          service.calculate!
          vulnerability_score = sbom.reload.metadata["risk_breakdown"]["vulnerability_score"]
          # 2 critical (25 each) + 2 unfixed penalty (10 each)
          expected = (2 * 25) + (2 * 10) # 70
          expect(vulnerability_score).to eq(expected)
        end
      end

      context "fixed critical vulnerabilities" do
        before do
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          create_list(:supply_chain_sbom_vulnerability, 2,
                     sbom: sbom,
                     component: component,
                     account: account,
                     severity: "critical",
                     remediation_status: "open",
                     fixed_version: "1.2.3")
        end

        it "does not apply extra penalty when fix is available" do
          service.calculate!
          vulnerability_score = sbom.reload.metadata["risk_breakdown"]["vulnerability_score"]
          # 2 critical (25 each), no unfixed penalty
          expect(vulnerability_score).to eq(50) # 2 * 25
        end
      end

      context "vulnerability score capped at 100" do
        before do
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          # Create enough critical vulnerabilities to exceed 100
          create_list(:supply_chain_sbom_vulnerability, 10,
                     sbom: sbom, component: component, account: account, severity: "critical")
        end

        it "caps vulnerability score at 100" do
          service.calculate!
          vulnerability_score = sbom.reload.metadata["risk_breakdown"]["vulnerability_score"]
          expect(vulnerability_score).to eq(100)
        end
      end
    end

    context "with license risks" do
      context "strong copyleft licenses" do
        before do
          # Use GPL-3.0-only SPDX ID so the callback sets is_strong_copyleft correctly
          license = create(:supply_chain_license, :gpl_3)
          create_list(:supply_chain_sbom_component, 2,
                     sbom: sbom, account: account, license_spdx_id: license.spdx_id)
        end

        it "applies strong copyleft weight (20 per component)" do
          service.calculate!
          license_score = sbom.reload.metadata["risk_breakdown"]["license_score"]
          expect(license_score).to eq(40) # 2 * 20
        end
      end

      context "weak copyleft licenses" do
        before do
          license = create(:supply_chain_license,
                          spdx_id: "LGPL-3.0-only",
                          category: "weak_copyleft",
                          is_copyleft: true,
                          is_strong_copyleft: false)
          create_list(:supply_chain_sbom_component, 3,
                     sbom: sbom, account: account, license_spdx_id: license.spdx_id)
        end

        it "applies weak copyleft weight (10 per component)" do
          service.calculate!
          license_score = sbom.reload.metadata["risk_breakdown"]["license_score"]
          expect(license_score).to eq(30) # 3 * 10
        end
      end

      context "unknown licenses" do
        before do
          # Components with blank license_spdx_id
          create_list(:supply_chain_sbom_component, 2,
                     sbom: sbom, account: account, license_spdx_id: nil)
        end

        it "applies unknown license weight (15 per component)" do
          service.calculate!
          license_score = sbom.reload.metadata["risk_breakdown"]["license_score"]
          expect(license_score).to eq(30) # 2 * 15
        end
      end

      context "permissive licenses" do
        before do
          license = create(:supply_chain_license, :permissive)
          create_list(:supply_chain_sbom_component, 3,
                     sbom: sbom, account: account, license_spdx_id: license.spdx_id)
        end

        it "does not apply penalty for permissive licenses" do
          service.calculate!
          license_score = sbom.reload.metadata["risk_breakdown"]["license_score"]
          expect(license_score).to eq(0)
        end
      end

      context "license violations" do
        before do
          # Create actual license violations with status "open"
          component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
          policy = create(:supply_chain_license_policy, account: account)
          create_list(:supply_chain_license_violation, 2,
                     sbom: sbom, sbom_component: component,
                     license_policy: policy, account: account, status: "open")
        end

        it "applies non-compliant weight (25 per violation)" do
          service.calculate!
          license_score = sbom.reload.metadata["risk_breakdown"]["license_score"]
          expect(license_score).to eq(50) # 2 * 25
        end
      end

      context "license score capped at 100" do
        before do
          # Use GPL-3.0-only SPDX ID so the callback sets is_strong_copyleft correctly
          license = create(:supply_chain_license, :gpl_3)
          # Create enough components to exceed 100 (10 * 20 = 200, capped at 100)
          create_list(:supply_chain_sbom_component, 10,
                     sbom: sbom, account: account, license_spdx_id: license.spdx_id)
        end

        it "caps license score at 100" do
          service.calculate!
          license_score = sbom.reload.metadata["risk_breakdown"]["license_score"]
          expect(license_score).to eq(100)
        end
      end
    end

    context "with dependency risks" do
      context "outdated components" do
        context "with 50% outdated ratio" do
          before do
            create_list(:supply_chain_sbom_component, 5,
                       sbom: sbom, account: account, is_outdated: true)
            create_list(:supply_chain_sbom_component, 5,
                       sbom: sbom, account: account, is_outdated: false)
          end

          it "applies proportional outdated penalty" do
            service.calculate!
            dependency_score = sbom.reload.metadata["risk_breakdown"]["dependency_score"]
            # 50% outdated ratio: (0.5 * 10 * 10) = 50
            expect(dependency_score).to eq(50)
          end
        end

        context "with 25% outdated ratio" do
          before do
            create_list(:supply_chain_sbom_component, 1,
                       sbom: sbom, account: account, is_outdated: true)
            create_list(:supply_chain_sbom_component, 3,
                       sbom: sbom, account: account, is_outdated: false)
          end

          it "applies proportional outdated penalty" do
            service.calculate!
            dependency_score = sbom.reload.metadata["risk_breakdown"]["dependency_score"]
            # 25% outdated ratio: (0.25 * 10 * 10) = 25
            expect(dependency_score).to eq(25)
          end
        end
      end

      context "deep transitive dependencies" do
        context "with 40% deep dependencies" do
          before do
            # depth > 3 counts as deep
            create_list(:supply_chain_sbom_component, 4,
                       sbom: sbom, account: account, depth: 4)
            create_list(:supply_chain_sbom_component, 6,
                       sbom: sbom, account: account, depth: 1)
          end

          it "applies proportional deep transitive penalty" do
            service.calculate!
            dependency_score = sbom.reload.metadata["risk_breakdown"]["dependency_score"]
            # 40% deep ratio: (0.4 * 5 * 5) = 10
            expect(dependency_score).to eq(10)
          end
        end
      end

      context "large dependency count" do
        context "with more than 500 components" do
          before do
            create_list(:supply_chain_sbom_component, 501,
                       sbom: sbom, account: account)
          end

          it "applies 10 point penalty" do
            service.calculate!
            dependency_score = sbom.reload.metadata["risk_breakdown"]["dependency_score"]
            expect(dependency_score).to be >= 10
          end
        end

        context "with more than 200 but less than 500 components" do
          before do
            create_list(:supply_chain_sbom_component, 250,
                       sbom: sbom, account: account)
          end

          it "applies 5 point penalty" do
            service.calculate!
            dependency_score = sbom.reload.metadata["risk_breakdown"]["dependency_score"]
            expect(dependency_score).to be >= 5
          end
        end

        context "with less than 200 components" do
          before do
            create_list(:supply_chain_sbom_component, 50,
                       sbom: sbom, account: account)
          end

          it "does not apply count penalty" do
            service.calculate!
            dependency_score = sbom.reload.metadata["risk_breakdown"]["dependency_score"]
            # Should be 0 since no outdated or deep dependencies
            expect(dependency_score).to eq(0)
          end
        end
      end

      context "combined dependency factors" do
        before do
          # 100 total components
          # 20 outdated (20%)
          # 10 deep (depth > 3, 10%)
          # Total < 200 so no count penalty
          create_list(:supply_chain_sbom_component, 20,
                     sbom: sbom, account: account, is_outdated: true, depth: 1)
          create_list(:supply_chain_sbom_component, 10,
                     sbom: sbom, account: account, is_outdated: false, depth: 4)
          create_list(:supply_chain_sbom_component, 70,
                     sbom: sbom, account: account, is_outdated: false, depth: 1)
        end

        it "calculates combined dependency score" do
          service.calculate!
          dependency_score = sbom.reload.metadata["risk_breakdown"]["dependency_score"]
          # outdated: 0.2 * 10 * 10 = 20
          # deep: 0.1 * 5 * 5 = 2.5 (rounds to 3)
          # count: 0 (< 200)
          expected = 20 + 3
          expect(dependency_score).to eq(expected)
        end
      end

      context "dependency score capped at 100" do
        before do
          # All outdated and deep, plus large count
          create_list(:supply_chain_sbom_component, 600,
                     sbom: sbom, account: account, is_outdated: true, depth: 5)
        end

        it "caps dependency score at 100" do
          service.calculate!
          dependency_score = sbom.reload.metadata["risk_breakdown"]["dependency_score"]
          expect(dependency_score).to eq(100)
        end
      end
    end

    context "with supply chain risks" do
      context "unsigned SBOM" do
        before do
          allow(sbom).to receive(:signed?).and_return(false)
        end

        it "applies 15 point penalty for not signed" do
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          expect(supply_chain_score).to be >= 15
        end
      end

      context "signed SBOM" do
        before do
          sbom.update!(signature: "signature_data")
        end

        it "does not apply signing penalty" do
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          # Should have other penalties but not signing penalty
          expect(supply_chain_score).to be < 100
        end
      end

      context "missing attestations" do
        before do
          allow(sbom).to receive_message_chain(:attestations, :empty?).and_return(true)
          sbom.save!
        end

        it "applies 15 point penalty for no attestations" do
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          expect(supply_chain_score).to be >= 15
        end
      end

      context "with attestations" do
        before do
          create(:supply_chain_attestation, sbom: sbom, account: account)
        end

        it "does not apply attestation penalty" do
          # Rebuild service after creating attestation
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          # Should not include attestation penalty
          expect(supply_chain_score).to be < 100
        end
      end

      context "NTIA non-compliant" do
        before do
          sbom.update!(ntia_minimum_compliant: false)
        end

        it "applies 10 point penalty for non-compliance" do
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          expect(supply_chain_score).to be >= 10
        end
      end

      context "NTIA compliant" do
        before do
          sbom.update!(ntia_minimum_compliant: true)
        end

        it "does not apply NTIA penalty" do
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          # Should have other penalties but not NTIA penalty
          expect(supply_chain_score).to be < 100
        end
      end

      context "many direct dependencies" do
        before do
          create_list(:supply_chain_sbom_component, 101,
                     sbom: sbom, account: account, dependency_type: "direct")
        end

        it "applies 10 point penalty for >100 direct deps" do
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          expect(supply_chain_score).to be >= 10
        end
      end

      context "few direct dependencies" do
        before do
          create_list(:supply_chain_sbom_component, 50,
                     sbom: sbom, account: account, dependency_type: "direct")
        end

        it "does not apply direct dependency penalty" do
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          # Should have other penalties but not direct dep penalty
          expect(supply_chain_score).to be < 100
        end
      end

      context "all supply chain issues" do
        before do
          sbom.update!(ntia_minimum_compliant: false)
          allow(sbom).to receive(:signed?).and_return(false)
          allow(sbom).to receive_message_chain(:attestations, :empty?).and_return(true)
          create_list(:supply_chain_sbom_component, 101,
                     sbom: sbom, account: account, dependency_type: "direct")
          sbom.save!
        end

        it "combines all supply chain penalties" do
          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          # 15 (not signed) + 15 (no attestations) + 10 (NTIA) + 10 (direct deps) = 50
          expect(supply_chain_score).to eq(50)
        end
      end

      context "supply chain score capped at 100" do
        it "caps score at 100" do
          sbom.update!(ntia_minimum_compliant: false)
          allow(sbom).to receive(:signed?).and_return(false)
          allow(sbom).to receive_message_chain(:attestations, :empty?).and_return(true)
          create_list(:supply_chain_sbom_component, 101,
                     sbom: sbom, account: account, dependency_type: "direct")
          sbom.save!

          service.calculate!
          supply_chain_score = sbom.reload.metadata["risk_breakdown"]["supply_chain_score"]
          expect(supply_chain_score).to be <= 100
        end
      end
    end

    context "weighted average calculation" do
      before do
        # Create specific scores
        component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
        # Vulnerability score: 2 critical = 50
        create_list(:supply_chain_sbom_vulnerability, 2,
                   sbom: sbom, component: component, account: account, severity: "critical")

        # License score: 2 strong copyleft = 40
        # Use :gpl_3 trait so callback correctly sets is_strong_copyleft
        license = create(:supply_chain_license, :gpl_3)
        create_list(:supply_chain_sbom_component, 2,
                   sbom: sbom, account: account, license_spdx_id: license.spdx_id)

        # Dependency score: 250 components = 5 points
        create_list(:supply_chain_sbom_component, 247,
                   sbom: sbom, account: account, is_outdated: false, depth: 1)

        # Supply chain score: SBOM is signed (0) + has attestation (0) + not NTIA (10) = 10
        sbom.update!(ntia_minimum_compliant: false)
      end

      it "calculates weighted average correctly" do
        service.calculate!
        # Vulnerability: 50 * 0.4 = 20
        # License: 40 * 0.2 = 8
        # Dependency: 5 * 0.2 = 1
        # Supply Chain: 20 * 0.2 = 4
        #   - signed (0) + has attestation (0) + not NTIA (10) + >100 direct deps (10) = 20
        # Total: 33.0
        expected = (50 * 0.4) + (40 * 0.2) + (5 * 0.2) + (20 * 0.2)
        expect(sbom.reload.risk_score).to eq(expected.round(2))
      end
    end

    context "updating component risk scores" do
      let!(:components) do
        [
          create(:supply_chain_sbom_component, sbom: sbom, account: account, risk_score: 0),
          create(:supply_chain_sbom_component, sbom: sbom, account: account, risk_score: 0)
        ]
      end

      before do
        # Add vulnerabilities to first component
        create(:supply_chain_sbom_vulnerability,
              sbom: sbom, component: components[0], account: account, severity: "critical")
      end

      it "updates component risk scores" do
        expect {
          service.calculate!
        }.to change { components[0].reload.risk_score }.from(0)
      end

      it "calls calculate_risk_score on each component" do
        # Use allow_any_instance_of to track calls without strict instance matching
        call_count = 0
        allow_any_instance_of(SupplyChain::SbomComponent).to receive(:calculate_risk_score).and_wrap_original do |method|
          call_count += 1
          method.call
        end

        service.calculate!

        expect(call_count).to eq(components.size)
      end
    end

    context "metadata storage" do
      before do
        component = create(:supply_chain_sbom_component, sbom: sbom, account: account)
        create(:supply_chain_sbom_vulnerability,
              sbom: sbom, component: component, account: account, severity: "high")
      end

      it "stores all four sub-scores in risk_breakdown" do
        service.calculate!
        breakdown = sbom.reload.metadata["risk_breakdown"]

        expect(breakdown).to have_key("vulnerability_score")
        expect(breakdown).to have_key("license_score")
        expect(breakdown).to have_key("dependency_score")
        expect(breakdown).to have_key("supply_chain_score")
      end

      it "preserves existing metadata" do
        sbom.update!(metadata: { "custom_key" => "custom_value" })
        service.calculate!

        expect(sbom.reload.metadata["custom_key"]).to eq("custom_value")
      end

      it "stores risk_calculated_at timestamp" do
        freeze_time do
          service.calculate!
          expect(sbom.reload.metadata["risk_calculated_at"]).to eq(Time.current.iso8601)
        end
      end
    end
  end

  describe "#calculate_contextual_vulnerability_scores" do
    # Use depth: 0 to avoid depth adjustment in most tests (0.3 * depth)
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account, depth: 0) }
    let(:vulnerability) do
      create(:supply_chain_sbom_vulnerability,
            sbom: sbom,
            component: component,
            account: account,
            severity: "high",
            cvss_score: 7.5,
            metadata: {},
            published_at: 60.days.ago)
    end

    before { vulnerability }

    context "base score from CVSS" do
      it "uses cvss_score as base score" do
        service.calculate_contextual_vulnerability_scores
        expect(vulnerability.reload.contextual_score).to eq(7.5)
      end
    end

    context "base score from severity when CVSS is nil" do
      before { vulnerability.update!(cvss_score: nil) }

      it "converts severity to score" do
        service.calculate_contextual_vulnerability_scores
        # High severity = 7.0
        expect(vulnerability.reload.contextual_score).to eq(7.0)
      end

      context "critical severity" do
        before { vulnerability.update!(severity: "critical", cvss_score: nil) }

        it "uses 9.0 for critical" do
          service.calculate_contextual_vulnerability_scores
          expect(vulnerability.reload.contextual_score).to eq(9.0)
        end
      end

      context "medium severity" do
        before { vulnerability.update!(severity: "medium", cvss_score: nil) }

        it "uses 5.0 for medium" do
          service.calculate_contextual_vulnerability_scores
          expect(vulnerability.reload.contextual_score).to eq(5.0)
        end
      end

      context "low severity" do
        before { vulnerability.update!(severity: "low", cvss_score: nil) }

        it "uses 3.0 for low" do
          service.calculate_contextual_vulnerability_scores
          expect(vulnerability.reload.contextual_score).to eq(3.0)
        end
      end
    end

    context "exploit in wild adjustment" do
      before do
        vulnerability.update!(metadata: { "exploit_in_wild" => true })
      end

      it "increases score by 1.5" do
        service.calculate_contextual_vulnerability_scores
        # 7.5 + 1.5 = 9.0
        expect(vulnerability.reload.contextual_score).to eq(9.0)
      end
    end

    context "POC available adjustment" do
      context "from metadata" do
        before do
          vulnerability.update!(metadata: { "poc_available" => true })
        end

        it "increases score by 1.0" do
          service.calculate_contextual_vulnerability_scores
          # 7.5 + 1.0 = 8.5
          expect(vulnerability.reload.contextual_score).to eq(8.5)
        end
      end

      context "from references with exploit keyword" do
        before do
          vulnerability.update!(references: [ "https://example.com/exploit-poc" ])
        end

        it "increases score by 1.0" do
          service.calculate_contextual_vulnerability_scores
          # 7.5 + 1.0 = 8.5
          expect(vulnerability.reload.contextual_score).to eq(8.5)
        end
      end

      context "from references with poc keyword" do
        before do
          vulnerability.update!(references: [ "https://example.com/poc-code" ])
        end

        it "increases score by 1.0" do
          service.calculate_contextual_vulnerability_scores
          # 7.5 + 1.0 = 8.5
          expect(vulnerability.reload.contextual_score).to eq(8.5)
        end
      end
    end

    context "code not reachable adjustment" do
      before do
        vulnerability.update!(metadata: { "code_reachable" => false })
      end

      it "decreases score by 1.0" do
        service.calculate_contextual_vulnerability_scores
        # 7.5 - 1.0 = 6.5
        expect(vulnerability.reload.contextual_score).to eq(6.5)
      end
    end

    context "behind authentication adjustment" do
      before do
        vulnerability.update!(metadata: { "behind_auth" => true })
      end

      it "decreases score by 0.5" do
        service.calculate_contextual_vulnerability_scores
        # 7.5 - 0.5 = 7.0
        expect(vulnerability.reload.contextual_score).to eq(7.0)
      end
    end

    context "dependency depth adjustment" do
      context "depth 0 (direct)" do
        before { component.update!(depth: 0) }

        it "applies no depth adjustment" do
          service.calculate_contextual_vulnerability_scores
          expect(vulnerability.reload.contextual_score).to eq(7.5)
        end
      end

      context "depth 2" do
        before { component.update!(depth: 2) }

        it "decreases score by 0.6 (0.3 * 2)" do
          service.calculate_contextual_vulnerability_scores
          # 7.5 - 0.6 = 6.9
          expect(vulnerability.reload.contextual_score).to eq(6.9)
        end
      end

      context "depth 5" do
        before { component.update!(depth: 5) }

        it "decreases score by 1.5 (0.3 * 5)" do
          service.calculate_contextual_vulnerability_scores
          # 7.5 - 1.5 = 6.0
          expect(vulnerability.reload.contextual_score).to eq(6.0)
        end
      end
    end

    context "recent vulnerability adjustment" do
      context "published within 30 days" do
        before do
          vulnerability.update!(published_at: 15.days.ago)
        end

        it "increases score by 0.5" do
          service.calculate_contextual_vulnerability_scores
          # 7.5 + 0.5 (recent) = 8.0 (depth is 0, so no depth adjustment)
          expect(vulnerability.reload.contextual_score).to eq(8.0)
        end
      end

      context "published more than 30 days ago" do
        before do
          vulnerability.update!(published_at: 60.days.ago)
        end

        it "does not apply age adjustment" do
          service.calculate_contextual_vulnerability_scores
          # 7.5 (no adjustments, depth is 0)
          expect(vulnerability.reload.contextual_score).to eq(7.5)
        end
      end

      context "no published_at date" do
        before do
          vulnerability.update!(published_at: nil)
        end

        it "does not apply age adjustment" do
          service.calculate_contextual_vulnerability_scores
          # 7.5 (no adjustments, depth is 0)
          expect(vulnerability.reload.contextual_score).to eq(7.5)
        end
      end
    end

    context "combined adjustments" do
      before do
        vulnerability.update!(
          cvss_score: 8.0,
          metadata: {
            "exploit_in_wild" => true,
            "poc_available" => true,
            "code_reachable" => true,
            "behind_auth" => true
          },
          published_at: 10.days.ago
        )
        component.update!(depth: 0)
      end

      it "applies all adjustments correctly" do
        service.calculate_contextual_vulnerability_scores
        # 8.0 + 1.5 (exploit) + 1.0 (poc) - 0.5 (auth) + 0.5 (recent) = 10.5 (capped at 10)
        expect(vulnerability.reload.contextual_score).to eq(10.0)
      end
    end

    context "score boundaries" do
      context "score below zero" do
        before do
          vulnerability.update!(
            cvss_score: 2.0,
            metadata: { "code_reachable" => false, "behind_auth" => true }
          )
          component.update!(depth: 10)
        end

        it "caps score at 0" do
          service.calculate_contextual_vulnerability_scores
          # 2.0 - 1.0 (not reachable) - 0.5 (auth) - 3.0 (depth) = -2.5, capped at 0
          expect(vulnerability.reload.contextual_score).to eq(0)
        end
      end

      context "score above 10" do
        before do
          vulnerability.update!(
            cvss_score: 9.5,
            metadata: { "exploit_in_wild" => true, "poc_available" => true },
            published_at: 5.days.ago
          )
          component.update!(depth: 0)
        end

        it "caps score at 10" do
          service.calculate_contextual_vulnerability_scores
          # 9.5 + 1.5 (exploit) + 1.0 (poc) + 0.5 (recent) = 12.5, capped at 10
          expect(vulnerability.reload.contextual_score).to eq(10.0)
        end
      end
    end

    context "context factors storage" do
      before do
        vulnerability.update!(
          metadata: { "exploit_in_wild" => true, "behind_auth" => true },
          fixed_version: "1.2.3",
          published_at: 45.days.ago
        )
        component.update!(depth: 3, dependency_type: "direct")
      end

      it "stores all context factors" do
        service.calculate_contextual_vulnerability_scores
        factors = vulnerability.reload.context_factors

        expect(factors["exploit_in_wild"]).to eq(true)
        expect(factors["poc_available"]).to be_in([ true, false ])
        expect(factors["code_reachable"]).to eq(true)
        expect(factors["behind_auth"]).to eq(true)
        expect(factors["dependency_depth"]).to eq(3)
        expect(factors["is_direct_dependency"]).to eq(true)
        expect(factors["has_fix_available"]).to eq(true)
        expect(factors["age_days"]).to be_a(Integer)
      end

      it "stores is_direct_dependency correctly for direct deps" do
        service.calculate_contextual_vulnerability_scores
        factors = vulnerability.reload.context_factors
        expect(factors["is_direct_dependency"]).to eq(true)
      end

      it "stores is_direct_dependency correctly for transitive deps" do
        component.update!(dependency_type: "transitive")
        service.calculate_contextual_vulnerability_scores
        factors = vulnerability.reload.context_factors
        expect(factors["is_direct_dependency"]).to eq(false)
      end

      it "calculates age_days correctly" do
        freeze_time do
          service.calculate_contextual_vulnerability_scores
          factors = vulnerability.reload.context_factors
          expected_age = (Date.current - vulnerability.published_at.to_date).to_i
          expect(factors["age_days"]).to eq(expected_age)
        end
      end

      it "handles nil published_at for age calculation" do
        vulnerability.update!(published_at: nil)
        service.calculate_contextual_vulnerability_scores
        factors = vulnerability.reload.context_factors
        expect(factors["age_days"]).to be_nil
      end
    end

    context "multiple vulnerabilities" do
      let(:vuln2) do
        create(:supply_chain_sbom_vulnerability,
              sbom: sbom,
              component: component,
              account: account,
              severity: "critical",
              cvss_score: 9.0)
      end

      before { vuln2 }

      it "processes all vulnerabilities" do
        service.calculate_contextual_vulnerability_scores

        expect(vulnerability.reload.contextual_score).to be_present
        expect(vuln2.reload.contextual_score).to be_present
      end

      it "calculates different scores based on factors" do
        vulnerability.update!(metadata: { "exploit_in_wild" => true })
        vuln2.update!(metadata: { "code_reachable" => false })

        service.calculate_contextual_vulnerability_scores

        expect(vulnerability.reload.contextual_score).not_to eq(vuln2.reload.contextual_score)
      end
    end
  end
end
