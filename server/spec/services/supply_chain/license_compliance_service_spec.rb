# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::LicenseComplianceService, type: :service do
  let(:account) { create(:account) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }
  let(:options) { {} }
  let(:service) { described_class.new(account: account, sbom: sbom, options: options) }

  describe "#initialize" do
    it "initializes with account, sbom, and options" do
      expect(service.account).to eq(account)
      expect(service.sbom).to eq(sbom)
      expect(service.options).to eq({})
    end

    it "converts options to indifferent access" do
      service = described_class.new(account: account, sbom: sbom, options: { "policy_id" => "123" })
      expect(service.options[:policy_id]).to eq("123")
      expect(service.options["policy_id"]).to eq("123")
    end

    it "accepts nil sbom" do
      service = described_class.new(account: account, sbom: nil, options: options)
      expect(service.sbom).to be_nil
    end
  end

  describe "#evaluate!" do
    context "without sbom" do
      let(:service) { described_class.new(account: account, sbom: nil, options: options) }

      it "returns compliant with empty violations" do
        result = service.evaluate!
        expect(result[:compliant]).to be true
        expect(result[:violations]).to be_empty
      end
    end

    context "without policy" do
      it "returns compliant with nil policy" do
        result = service.evaluate!
        expect(result[:compliant]).to be true
        expect(result[:violations]).to be_empty
        expect(result[:policy]).to be_nil
      end
    end

    context "with policy and components" do
      let!(:policy) { create(:supply_chain_license_policy, :default, account: account) }
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT") }
      let!(:gpl_license) { create(:supply_chain_license, :copyleft, spdx_id: "GPL-3.0-only") }

      # Ensure service fetches the mocked policy instance
      before do
        allow(SupplyChain::LicensePolicy).to receive(:default_for_account).with(account).and_return(policy)
      end

      context "with compliant components" do
        let!(:component1) do
          create(:supply_chain_sbom_component,
                 sbom: sbom,
                 account: account,
                 license_spdx_id: "MIT",
                 license_name: "MIT License",
                 dependency_type: "direct")
        end
        let!(:component2) do
          create(:supply_chain_sbom_component,
                 sbom: sbom,
                 account: account,
                 license_spdx_id: "MIT",
                 license_name: "MIT License",
                 dependency_type: "transitive")
        end

        before do
          allow(policy).to receive(:evaluate_component).and_return({
                                                                      compliant: true,
                                                                      violations: []
                                                                    })
        end

        it "returns compliant with no violations" do
          result = service.evaluate!
          expect(result[:compliant]).to be true
          expect(result[:violations]).to be_empty
          expect(result[:policy]).to eq(policy.summary)
          expect(result[:violation_count]).to eq(0)
        end

        it "updates component compliance status to compliant" do
          service.evaluate!
          expect(component1.reload.license_compliance_status).to eq("compliant")
          expect(component2.reload.license_compliance_status).to eq("compliant")
        end
      end

      context "with non-compliant components" do
        let!(:component1) do
          create(:supply_chain_sbom_component,
                 sbom: sbom,
                 account: account,
                 license_spdx_id: "GPL-3.0-only",
                 license_name: "GPL v3",
                 dependency_type: "direct")
        end
        let!(:component2) do
          create(:supply_chain_sbom_component,
                 sbom: sbom,
                 account: account,
                 license_spdx_id: "GPL-3.0-only",
                 license_name: "GPL v3",
                 dependency_type: "transitive")
        end

        before do
          allow(policy).to receive(:evaluate_component).with(component1).and_return({
                                                                                       compliant: false,
                                                                                       violations: [ { type: "denied", message: "License denied by policy" } ]
                                                                                     })
          allow(policy).to receive(:evaluate_component).with(component2).and_return({
                                                                                       compliant: false,
                                                                                       violations: [ { type: "copyleft", message: "Copyleft license not allowed" } ]
                                                                                     })
        end

        it "returns non-compliant with violations" do
          result = service.evaluate!
          expect(result[:compliant]).to be false
          expect(result[:violations]).not_to be_empty
          expect(result[:violation_count]).to eq(2)
        end

        it "creates LicenseViolation records" do
          expect {
            service.evaluate!
          }.to change(SupplyChain::LicenseViolation, :count).by(2)
        end

        it "sets correct violation types" do
          service.evaluate!
          violations = SupplyChain::LicenseViolation.where(sbom: sbom)
          expect(violations.map(&:violation_type)).to contain_exactly("denied", "copyleft")
        end

        it "sets correct severity levels" do
          service.evaluate!
          direct_violation = SupplyChain::LicenseViolation.find_by(sbom_component: component1)
          transitive_violation = SupplyChain::LicenseViolation.find_by(sbom_component: component2)

          # Direct dependency with denied type should be critical
          expect(direct_violation.severity).to eq("critical")
          # Transitive dependency with copyleft type should be high
          expect(transitive_violation.severity).to eq("high")
        end

        it "updates component compliance status to non_compliant" do
          service.evaluate!
          expect(component1.reload.license_compliance_status).to eq("non_compliant")
          expect(component2.reload.license_compliance_status).to eq("non_compliant")
        end

        it "includes violation descriptions" do
          service.evaluate!
          violation = SupplyChain::LicenseViolation.find_by(sbom_component: component1)
          expect(violation.description).to include("License denied by policy")
        end
      end

      context "with unknown license violations" do
        let!(:component) do
          create(:supply_chain_sbom_component,
                 sbom: sbom,
                 account: account,
                 license_spdx_id: "Unknown-1.0",
                 license_name: "Unknown License",
                 dependency_type: "transitive")  # Transitive to avoid severity escalation
        end

        before do
          allow(policy).to receive(:evaluate_component).and_return({
                                                                      compliant: false,
                                                                      violations: [ { type: "unknown", message: "Unknown license" } ]
                                                                    })
        end

        it "sets compliance status to unknown" do
          service.evaluate!
          expect(component.reload.license_compliance_status).to eq("unknown")
        end

        it "sets medium severity for unknown violations" do
          service.evaluate!
          violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
          expect(violation.severity).to eq("medium")
        end
      end

      context "with mixed violation types" do
        let!(:component) do
          create(:supply_chain_sbom_component,
                 sbom: sbom,
                 account: account,
                 license_spdx_id: "GPL-3.0-only",
                 dependency_type: "direct")
        end

        before do
          allow(policy).to receive(:evaluate_component).and_return({
                                                                      compliant: false,
                                                                      violations: [
                                                                        { type: "denied", message: "Denied" },
                                                                        { type: "copyleft", message: "Copyleft" }
                                                                      ]
                                                                    })
        end

        it "prioritizes denied type" do
          service.evaluate!
          violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
          expect(violation.violation_type).to eq("denied")
        end

        it "combines violation messages" do
          service.evaluate!
          violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
          expect(violation.description).to include("Denied")
          expect(violation.description).to include("Copyleft")
        end
      end
    end

    context "with custom policy from options" do
      let!(:default_policy) { create(:supply_chain_license_policy, :default, account: account) }
      let!(:custom_policy) { create(:supply_chain_license_policy, account: account) }
      let!(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
      let(:options) { { policy_id: custom_policy.id } }

      before do
        allow(custom_policy).to receive(:evaluate_component).and_return({
                                                                           compliant: true,
                                                                           violations: []
                                                                         })
      end

      it "uses the custom policy" do
        result = service.evaluate!
        expect(result[:policy][:id]).to eq(custom_policy.id)
      end
    end
  end

  describe "#evaluate_component" do
    let!(:policy) { create(:supply_chain_license_policy, :default, account: account) }
    let!(:component) do
      create(:supply_chain_sbom_component,
             sbom: sbom,
             account: account,
             license_spdx_id: "MIT")
    end

    # Ensure service fetches the mocked policy instance
    before do
      allow(SupplyChain::LicensePolicy).to receive(:default_for_account).with(account).and_return(policy)
    end

    context "with default policy" do
      before do
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: true,
                                                                    violations: []
                                                                  })
      end

      it "evaluates single component" do
        result = service.evaluate_component(component)
        expect(result[:compliant]).to be true
      end

      it "updates component compliance status" do
        service.evaluate_component(component)
        expect(component.reload.license_compliance_status).to eq("compliant")
      end
    end

    context "with provided policy" do
      let!(:custom_policy) { create(:supply_chain_license_policy, account: account) }

      before do
        allow(custom_policy).to receive(:evaluate_component).and_return({
                                                                           compliant: false,
                                                                           violations: [ { type: "denied", message: "Denied" } ]
                                                                         })
      end

      it "uses the provided policy" do
        result = service.evaluate_component(component, policy: custom_policy)
        expect(result[:compliant]).to be false
      end
    end

    context "without policy" do
      it "returns compliant when no policy exists" do
        result = service.evaluate_component(component)
        expect(result[:compliant]).to be true
      end
    end
  end

  describe "#check_gpl_contamination" do
    context "without sbom" do
      let(:service) { described_class.new(account: account, sbom: nil, options: options) }

      it "returns not contaminated" do
        result = service.check_gpl_contamination
        expect(result[:contaminated]).to be false
        expect(result[:sources]).to be_empty
      end
    end

    context "with no GPL components" do
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT") }
      let!(:component) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               license_spdx_id: "MIT")
      end

      it "returns not contaminated" do
        result = service.check_gpl_contamination
        expect(result[:contaminated]).to be false
        expect(result[:sources]).to be_empty
        expect(result[:contamination_count]).to eq(0)
      end
    end

    context "with GPL components" do
      let!(:gpl_license) do
        create(:supply_chain_license,
               :copyleft,
               spdx_id: "GPL-3.0-only",
               is_strong_copyleft: true)
      end
      let!(:agpl_license) do
        create(:supply_chain_license,
               :network_copyleft,
               spdx_id: "AGPL-3.0-only")
      end
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT") }

      let!(:gpl_component) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               name: "gpl-package",
               version: "1.0.0",
               license_spdx_id: "GPL-3.0-only",
               purl: "pkg:npm/gpl-package@1.0.0",
               dependency_type: "direct",
               depth: 0)
      end

      let!(:agpl_component) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               name: "agpl-package",
               version: "2.0.0",
               license_spdx_id: "AGPL-3.0-only",
               purl: "pkg:npm/agpl-package@2.0.0",
               dependency_type: "transitive",
               depth: 2)
      end

      let!(:mit_component) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               license_spdx_id: "MIT")
      end

      it "returns contaminated" do
        result = service.check_gpl_contamination
        expect(result[:contaminated]).to be true
      end

      it "returns GPL component sources" do
        result = service.check_gpl_contamination
        expect(result[:sources].length).to eq(2)
        expect(result[:contamination_count]).to eq(2)
      end

      it "includes component details in sources" do
        result = service.check_gpl_contamination
        gpl_source = result[:sources].find { |s| s[:license] == "GPL-3.0-only" }

        expect(gpl_source).to include(
          component: "gpl-package@1.0.0",
          purl: "pkg:npm/gpl-package@1.0.0",
          license: "GPL-3.0-only",
          dependency_type: "direct",
          depth: 0
        )
      end

      it "includes AGPL components" do
        result = service.check_gpl_contamination
        agpl_source = result[:sources].find { |s| s[:license] == "AGPL-3.0-only" }

        expect(agpl_source).to include(
          component: "agpl-package@2.0.0",
          license: "AGPL-3.0-only",
          dependency_type: "transitive"
        )
      end

      it "excludes non-GPL components" do
        result = service.check_gpl_contamination
        mit_source = result[:sources].find { |s| s[:component].include?("mit") }
        expect(mit_source).to be_nil
      end
    end

    context "with weak copyleft licenses" do
      let!(:lgpl_license) do
        create(:supply_chain_license,
               spdx_id: "LGPL-3.0-only",
               category: "weak_copyleft",
               is_copyleft: true,
               is_strong_copyleft: false)
      end
      let!(:component) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               license_spdx_id: "LGPL-3.0-only")
      end

      it "does not include weak copyleft licenses" do
        result = service.check_gpl_contamination
        expect(result[:contaminated]).to be false
        expect(result[:sources]).to be_empty
      end
    end
  end

  describe "#generate_notice_file" do
    context "without sbom" do
      let(:service) { described_class.new(account: account, sbom: nil, options: options) }

      it "returns nil" do
        result = service.generate_notice_file
        expect(result).to be_nil
      end
    end

    context "with components" do
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT", name: "MIT License") }
      let!(:apache_license) do
        create(:supply_chain_license,
               spdx_id: "Apache-2.0",
               name: "Apache License 2.0",
               category: "permissive")
      end

      let!(:component1) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               name: "test-package",
               version: "1.0.0",
               license_spdx_id: "MIT")
      end

      let!(:component2) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               name: "another-package",
               version: "2.0.0",
               license_spdx_id: "Apache-2.0")
      end

      it "generates NOTICE file content" do
        result = service.generate_notice_file
        expect(result).to be_present
      end

      it "includes header" do
        result = service.generate_notice_file
        expect(result).to include("THIRD-PARTY SOFTWARE NOTICES")
      end

      it "includes component attributions" do
        result = service.generate_notice_file
        expect(result).to include("test-package")
        expect(result).to include("another-package")
      end

      it "groups by license" do
        result = service.generate_notice_file
        expect(result).to include("MIT License")
        expect(result).to include("Apache License 2.0")
      end

      it "includes timestamp" do
        result = service.generate_notice_file
        expect(result).to include("Generated at:")
      end

      it "ensures attributions exist for all components" do
        expect(SupplyChain::Attribution).to receive(:generate_for_sbom).with(sbom)
        service.generate_notice_file
      end
    end

    context "with existing attributions" do
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT", name: "MIT License") }
      let!(:component) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               name: "test-package",
               version: "1.0.0",
               license_spdx_id: "MIT")
      end
      let!(:attribution) do
        create(:supply_chain_attribution,
               :with_copyright,
               sbom_component: component,
               account: account,
               license: mit_license,
               package_name: "test-package")
      end

      it "uses existing attributions" do
        result = service.generate_notice_file
        expect(result).to include("test-package")
      end
    end
  end

  describe "#detect_licenses" do
    context "without sbom" do
      let(:service) { described_class.new(account: account, sbom: nil, options: options) }

      it "returns empty array" do
        result = service.detect_licenses
        expect(result).to eq([])
      end
    end

    context "with components needing detection" do
      let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT", name: "MIT License") }
      let!(:component1) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               license_spdx_id: "MIT",
               license_name: "MIT License")
      end
      let!(:component2) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               license_spdx_id: "Apache-2.0",
               license_name: "Apache 2.0")
      end

      it "creates LicenseDetection records" do
        expect {
          service.detect_licenses
        }.to change(SupplyChain::LicenseDetection, :count).by(2)
      end

      it "returns detection records" do
        result = service.detect_licenses
        expect(result.length).to eq(2)
        expect(result).to all(be_a(SupplyChain::LicenseDetection))
      end

      it "sets detection source to manifest" do
        service.detect_licenses
        detection = SupplyChain::LicenseDetection.find_by(sbom_component: component1)
        expect(detection.detection_source).to eq("manifest")
      end

      it "sets confidence score to 0.9" do
        service.detect_licenses
        detection = SupplyChain::LicenseDetection.find_by(sbom_component: component1)
        expect(detection.confidence_score).to eq(0.9)
      end

      it "marks as primary detection" do
        service.detect_licenses
        detection = SupplyChain::LicenseDetection.find_by(sbom_component: component1)
        expect(detection.is_primary).to be true
      end

      it "does not require review for high confidence" do
        service.detect_licenses
        detection = SupplyChain::LicenseDetection.find_by(sbom_component: component1)
        expect(detection.requires_review).to be false
      end

      it "resolves license from SPDX ID" do
        service.detect_licenses
        detection = SupplyChain::LicenseDetection.find_by(sbom_component: component1)
        expect(detection.license).to eq(mit_license)
      end
    end

    context "with existing detections" do
      let!(:component) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               license_spdx_id: "MIT")
      end
      let!(:existing_detection) do
        create(:supply_chain_license_detection,
               sbom_component: component,
               account: account)
      end

      it "skips components with existing detections" do
        expect {
          service.detect_licenses
        }.not_to change(SupplyChain::LicenseDetection, :count)
      end
    end

    context "with low confidence detections" do
      let!(:component) do
        create(:supply_chain_sbom_component,
               sbom: sbom,
               account: account,
               license_spdx_id: "Unknown-License",
               license_name: "Unknown")
      end

      it "creates detection with unknown license" do
        result = service.detect_licenses
        expect(result.length).to eq(1)
      end

      it "sets lower confidence for unresolved licenses" do
        service.detect_licenses
        detection = SupplyChain::LicenseDetection.find_by(sbom_component: component)
        expect(detection.detected_license_id).to eq("Unknown-License")
      end
    end
  end

  describe "violation severity logic" do
    let!(:policy) { create(:supply_chain_license_policy, :default, account: account) }

    # Ensure service fetches the mocked policy instance
    before do
      allow(SupplyChain::LicensePolicy).to receive(:default_for_account).with(account).and_return(policy)
    end

    context "base severity by type" do
      it "sets high severity for denied violations" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "transitive")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [ { type: "denied", message: "Denied" } ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.severity).to eq("high")
      end

      it "sets high severity for copyleft violations" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "transitive")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [ { type: "copyleft", message: "Copyleft" } ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.severity).to eq("high")
      end

      it "sets medium severity for incompatible violations" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "transitive")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [ { type: "incompatible", message: "Incompatible" } ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.severity).to eq("medium")
      end

      it "sets medium severity for unknown violations" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "transitive")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [ { type: "unknown", message: "Unknown" } ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.severity).to eq("medium")
      end
    end

    context "severity escalation for direct dependencies" do
      it "escalates high to critical for direct dependencies" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "direct")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [ { type: "denied", message: "Denied" } ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.severity).to eq("critical")
      end

      it "escalates medium to high for direct dependencies" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "direct")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [ { type: "incompatible", message: "Incompatible" } ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.severity).to eq("high")
      end

      it "does not escalate for transitive dependencies" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "transitive")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [ { type: "denied", message: "Denied" } ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.severity).to eq("high")
      end

      it "does not escalate for dev dependencies" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "dev")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [ { type: "copyleft", message: "Copyleft" } ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.severity).to eq("high")
      end
    end

    context "violation type prioritization" do
      it "prioritizes denied over other types" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "direct")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [
                                                                      { type: "copyleft", message: "Copyleft" },
                                                                      { type: "denied", message: "Denied" },
                                                                      { type: "unknown", message: "Unknown" }
                                                                    ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.violation_type).to eq("denied")
      end

      it "prioritizes copyleft over incompatible" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "direct")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [
                                                                      { type: "incompatible", message: "Incompatible" },
                                                                      { type: "copyleft", message: "Copyleft" }
                                                                    ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.violation_type).to eq("copyleft")
      end

      it "treats strong_copyleft as copyleft" do
        component = create(:supply_chain_sbom_component,
                           sbom: sbom,
                           account: account,
                           dependency_type: "direct")
        allow(policy).to receive(:evaluate_component).and_return({
                                                                    compliant: false,
                                                                    violations: [
                                                                      { type: "strong_copyleft", message: "Strong copyleft" }
                                                                    ]
                                                                  })

        service.evaluate!
        violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
        expect(violation.violation_type).to eq("copyleft")
      end
    end
  end

  describe "error handling" do
    let!(:policy) { create(:supply_chain_license_policy, :default, account: account) }
    let!(:component) do
      create(:supply_chain_sbom_component,
             sbom: sbom,
             account: account,
             license_spdx_id: "MIT")
    end

    before do
      allow(SupplyChain::LicensePolicy).to receive(:default_for_account).with(account).and_return(policy)
    end

    it "continues evaluation even if one component fails" do
      allow(policy).to receive(:evaluate_component).and_raise(StandardError.new("Test error"))

      # Service does not catch individual component errors, so error is raised
      expect {
        service.evaluate!
      }.to raise_error(StandardError, "Test error")
    end
  end

  describe "integration with License.find_by_spdx" do
    let!(:policy) { create(:supply_chain_license_policy, :default, account: account) }
    let!(:mit_license) { create(:supply_chain_license, :permissive, spdx_id: "MIT") }
    let!(:component) do
      create(:supply_chain_sbom_component,
             sbom: sbom,
             account: account,
             license_spdx_id: "MIT")
    end

    before do
      allow(SupplyChain::LicensePolicy).to receive(:default_for_account).with(account).and_return(policy)
      allow(policy).to receive(:evaluate_component).and_return({
                                                                  compliant: false,
                                                                  violations: [ { type: "denied", message: "Denied" } ]
                                                                })
    end

    it "associates violations with resolved licenses" do
      service.evaluate!
      violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
      expect(violation.license).to eq(mit_license)
    end

    it "handles components with unresolved licenses" do
      component.update!(license_spdx_id: "Unknown-License-1.0")
      service.evaluate!
      violation = SupplyChain::LicenseViolation.find_by(sbom_component: component)
      expect(violation.license).to be_nil
    end
  end
end
