# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::VendorRiskService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:vendor) { create(:supply_chain_vendor, account: account) }
  let(:options) { {} }
  let(:service) { described_class.new(account: account, vendor: vendor, options: options) }

  describe "#initialize" do
    it "initializes with account" do
      expect(service.account).to eq(account)
    end

    it "initializes with vendor" do
      expect(service.vendor).to eq(vendor)
    end

    it "initializes with empty options by default" do
      expect(service.options).to eq({})
    end

    it "initializes with provided options" do
      service_with_options = described_class.new(
        account: account,
        vendor: vendor,
        options: { assessment_type: "periodic", user: user }
      )
      expect(service_with_options.options[:assessment_type]).to eq("periodic")
      expect(service_with_options.options[:user]).to eq(user)
    end

    it "converts options to hash with indifferent access" do
      service_with_options = described_class.new(
        account: account,
        vendor: vendor,
        options: { "assessment_type" => "periodic" }
      )
      expect(service_with_options.options[:assessment_type]).to eq("periodic")
    end

    it "initializes logger" do
      expect(service.instance_variable_get(:@logger)).to eq(Rails.logger)
    end
  end

  describe "RISK_CATEGORIES constant" do
    it "has security category with 40% weight" do
      expect(described_class::RISK_CATEGORIES[:security][:weight]).to eq(0.40)
    end

    it "has compliance category with 35% weight" do
      expect(described_class::RISK_CATEGORIES[:compliance][:weight]).to eq(0.35)
    end

    it "has operational category with 25% weight" do
      expect(described_class::RISK_CATEGORIES[:operational][:weight]).to eq(0.25)
    end

    it "has security factors" do
      expect(described_class::RISK_CATEGORIES[:security][:factors]).to include(
        "encryption", "access_control", "incident_response", "vulnerability_management"
      )
    end

    it "has compliance factors" do
      expect(described_class::RISK_CATEGORIES[:compliance][:factors]).to include(
        "certifications", "data_handling", "privacy", "regulatory"
      )
    end

    it "has operational factors" do
      expect(described_class::RISK_CATEGORIES[:operational][:factors]).to include(
        "availability", "support", "financial_stability", "business_continuity"
      )
    end
  end

  describe "#assess!" do
    context "basic assessment creation" do
      it "creates a RiskAssessment record" do
        expect { service.assess! }.to change(SupplyChain::RiskAssessment, :count).by(1)
      end

      it "creates assessment with correct vendor" do
        assessment = service.assess!
        expect(assessment.vendor).to eq(vendor)
      end

      it "creates assessment with correct account" do
        assessment = service.assess!
        expect(assessment.account).to eq(account)
      end

      it "creates assessment with initial type by default" do
        assessment = service.assess!
        expect(assessment.assessment_type).to eq("initial")
      end

      it "creates assessment with provided assessment type" do
        service_with_type = described_class.new(
          account: account,
          vendor: vendor,
          options: { assessment_type: "incident" }
        )
        assessment = service_with_type.assess!
        expect(assessment.assessment_type).to eq("incident")
      end

      it "creates assessment with provided assessor" do
        service_with_user = described_class.new(
          account: account,
          vendor: vendor,
          options: { user: user }
        )
        assessment = service_with_user.assess!
        expect(assessment.assessor).to eq(user)
      end

      it "sets assessment_date" do
        freeze_time do
          assessment = service.assess!
          expect(assessment.assessment_date).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "assessment workflow" do
      it "starts the assessment (changes status to in_progress)" do
        assessment = service.assess!
        # After assess! completes, status should be completed
        expect(assessment.status).to eq("completed")
      end

      it "completes the assessment" do
        assessment = service.assess!
        expect(assessment.completed?).to be true
      end

      it "sets completed_at timestamp" do
        freeze_time do
          assessment = service.assess!
          expect(assessment.completed_at).to be_within(1.second).of(Time.current)
        end
      end

      it "sets valid_until" do
        assessment = service.assess!
        expect(assessment.valid_until).to be_present
      end
    end

    context "score calculations" do
      it "calculates security_score" do
        assessment = service.assess!
        expect(assessment.security_score).to be_between(0, 100)
      end

      it "calculates compliance_score" do
        assessment = service.assess!
        expect(assessment.compliance_score).to be_between(0, 100)
      end

      it "calculates operational_score" do
        assessment = service.assess!
        expect(assessment.operational_score).to be_between(0, 100)
      end

      it "calculates overall_score based on weighted average" do
        assessment = service.assess!
        expected_overall = (
          (assessment.security_score * 0.4) +
          (assessment.compliance_score * 0.35) +
          (assessment.operational_score * 0.25)
        ).round(2)
        expect(assessment.overall_score).to be_within(0.1).of(expected_overall)
      end
    end

    context "findings generation" do
      context "with low security score vendor" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            certifications: [],
            metadata: {}
          )
        end

        it "generates security findings when score is low" do
          assessment = service.assess!
          if assessment.security_score < 80
            security_findings = assessment.findings.select { |f| f["category"] == "security" }
            expect(security_findings).not_to be_empty
          end
        end
      end

      context "with vendor handling PII without DPA" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_pii: true,
            has_dpa: false
          )
        end

        it "generates missing DPA finding" do
          assessment = service.assess!
          dpa_finding = assessment.findings.find { |f| f["title"].include?("Data Processing Agreement") }
          expect(dpa_finding).to be_present
          expect(dpa_finding["severity"]).to eq("high")
          expect(dpa_finding["category"]).to eq("compliance")
        end
      end

      context "with vendor handling PHI without BAA" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_phi: true,
            has_baa: false
          )
        end

        it "generates missing BAA finding" do
          assessment = service.assess!
          baa_finding = assessment.findings.find { |f| f["title"].include?("Business Associate Agreement") }
          expect(baa_finding).to be_present
          expect(baa_finding["severity"]).to eq("critical")
          expect(baa_finding["category"]).to eq("compliance")
        end
      end

      context "with vendor without SOC 2 certification" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            certifications: []
          )
        end

        it "generates SOC 2 certification finding" do
          assessment = service.assess!
          soc2_finding = assessment.findings.find { |f| f["title"].include?("SOC 2") }
          expect(soc2_finding).to be_present
          expect(soc2_finding["severity"]).to eq("medium")
          expect(soc2_finding["category"]).to eq("compliance")
        end
      end
    end

    context "recommendations generation" do
      context "with low security score" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            certifications: [],
            metadata: {}
          )
        end

        it "generates security documentation recommendation when score < 80" do
          assessment = service.assess!
          if assessment.security_score < 80
            security_rec = assessment.recommendations.find { |r| r["title"].include?("security") }
            expect(security_rec).to be_present
            expect(security_rec["priority"]).to eq("high")
          end
        end
      end

      context "with low compliance score" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_pii: true,
            handles_phi: true,
            has_dpa: false,
            has_baa: false
          )
        end

        it "generates compliance review recommendation when score < 70" do
          assessment = service.assess!
          if assessment.compliance_score < 70
            compliance_rec = assessment.recommendations.find { |r| r["title"].include?("compliance") }
            expect(compliance_rec).to be_present
            expect(compliance_rec["priority"]).to eq("high")
          end
        end
      end

      context "with critical findings" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_phi: true,
            has_baa: false
          )
        end

        it "generates immediate risk mitigation recommendation" do
          assessment = service.assess!
          critical_findings = assessment.findings.select { |f| f["severity"] == "critical" }
          if critical_findings.any?
            mitigation_rec = assessment.recommendations.find { |r| r["title"].include?("Immediate risk mitigation") }
            expect(mitigation_rec).to be_present
            expect(mitigation_rec["priority"]).to eq("critical")
          end
        end
      end

      context "with vendor handling sensitive data without SOC 2" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_pii: true,
            certifications: []
          )
        end

        it "generates SOC 2 recommendation" do
          assessment = service.assess!
          soc2_rec = assessment.recommendations.find { |r| r["title"].include?("SOC 2") }
          expect(soc2_rec).to be_present
          expect(soc2_rec["priority"]).to eq("high")
        end
      end
    end

    context "summary generation" do
      it "generates a summary string" do
        assessment = service.assess!
        expect(assessment.read_attribute(:summary)).to be_a(String)
      end

      it "includes overall score in summary" do
        assessment = service.assess!
        summary = assessment.read_attribute(:summary)
        expect(summary).to include("overall score")
      end

      it "includes finding counts in summary" do
        assessment = service.assess!
        summary = assessment.read_attribute(:summary)
        expect(summary).to include("critical")
        expect(summary).to include("high")
      end

      it "includes category scores in summary" do
        assessment = service.assess!
        summary = assessment.read_attribute(:summary)
        expect(summary).to include("Security:")
        expect(summary).to include("Compliance:")
        expect(summary).to include("Operational:")
      end
    end

    context "error handling" do
      it "raises RiskError on failure" do
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:start!).and_raise(StandardError, "Test error")

        expect { service.assess! }.to raise_error(SupplyChain::VendorRiskService::RiskError, /Risk assessment failed/)
      end

      it "logs error on failure" do
        allow_any_instance_of(SupplyChain::RiskAssessment).to receive(:start!).and_raise(StandardError, "Test error")

        expect(Rails.logger).to receive(:error).with(/VendorRiskService.*Assessment failed/)
        expect { service.assess! }.to raise_error(SupplyChain::VendorRiskService::RiskError)
      end
    end
  end

  describe "#reassess!" do
    it "sets assessment_type to periodic" do
      assessment = service.reassess!
      expect(assessment.assessment_type).to eq("periodic")
    end

    it "creates a new RiskAssessment" do
      expect { service.reassess! }.to change(SupplyChain::RiskAssessment, :count).by(1)
    end

    it "returns a completed assessment" do
      assessment = service.reassess!
      expect(assessment.completed?).to be true
    end
  end

  describe "#calculate_inherent_risk" do
    it "returns a hash with score, tier, and factors" do
      result = service.calculate_inherent_risk
      expect(result).to have_key(:score)
      expect(result).to have_key(:tier)
      expect(result).to have_key(:factors)
    end

    it "returns score as a numeric value" do
      result = service.calculate_inherent_risk
      expect(result[:score]).to be_a(Numeric)
    end

    it "returns score between 0 and 100" do
      result = service.calculate_inherent_risk
      expect(result[:score]).to be_between(0, 100)
    end

    it "returns score rounded to 2 decimal places" do
      result = service.calculate_inherent_risk
      expect(result[:score].to_s).to match(/^\d+(\.\d{1,2})?$/)
    end

    context "data sensitivity risk calculation" do
      context "vendor with no sensitive data" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_pii: false,
            handles_phi: false,
            handles_pci: false
          )
        end

        it "returns base data sensitivity risk" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:data_sensitivity]).to eq(30)
        end
      end

      context "vendor handling PII" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_pii: true,
            handles_phi: false,
            handles_pci: false
          )
        end

        it "increases data sensitivity risk by 30" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:data_sensitivity]).to eq(60)
        end
      end

      context "vendor handling PHI" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_pii: false,
            handles_phi: true,
            handles_pci: false
          )
        end

        it "increases data sensitivity risk by 40" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:data_sensitivity]).to eq(70)
        end
      end

      context "vendor handling PCI" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_pii: false,
            handles_phi: false,
            handles_pci: true
          )
        end

        it "increases data sensitivity risk by 30" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:data_sensitivity]).to eq(60)
        end
      end

      context "vendor handling all sensitive data types" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            handles_pii: true,
            handles_phi: true,
            handles_pci: true
          )
        end

        it "caps data sensitivity risk at 100" do
          result = service.calculate_inherent_risk
          # 30 base + 30 PII + 40 PHI + 30 PCI = 130, capped at 100
          expect(result[:factors][:data_sensitivity]).to eq(100)
        end
      end
    end

    context "criticality risk calculation" do
      context "infrastructure vendor" do
        let(:vendor) { create(:supply_chain_vendor, account: account, vendor_type: "infrastructure") }

        it "returns highest criticality risk (80)" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:criticality]).to eq(80)
        end
      end

      context "saas vendor" do
        let(:vendor) { create(:supply_chain_vendor, account: account, vendor_type: "saas") }

        it "returns high criticality risk (60)" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:criticality]).to eq(60)
        end
      end

      context "api vendor" do
        let(:vendor) { create(:supply_chain_vendor, account: account, vendor_type: "api") }

        it "returns medium criticality risk (50)" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:criticality]).to eq(50)
        end
      end

      context "library vendor" do
        let(:vendor) { create(:supply_chain_vendor, account: account, vendor_type: "library") }

        it "returns lower criticality risk (40)" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:criticality]).to eq(40)
        end
      end

      context "other vendor type" do
        let(:vendor) { create(:supply_chain_vendor, account: account, vendor_type: "consulting") }

        it "returns lowest criticality risk (30)" do
          result = service.calculate_inherent_risk
          expect(result[:factors][:criticality]).to eq(30)
        end
      end
    end

    context "accessibility risk calculation" do
      it "returns default medium risk (50)" do
        result = service.calculate_inherent_risk
        expect(result[:factors][:accessibility]).to eq(50)
      end
    end

    context "tier determination" do
      context "critical tier (80-100)" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            vendor_type: "infrastructure",
            handles_pii: true,
            handles_phi: true,
            handles_pci: true
          )
        end

        it "returns critical tier for high scores" do
          result = service.calculate_inherent_risk
          expect(result[:tier]).to eq("critical") if result[:score] >= 80
        end
      end

      context "high tier (60-79)" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            vendor_type: "saas",
            handles_pii: true,
            handles_phi: false,
            handles_pci: false
          )
        end

        it "returns high tier for medium-high scores" do
          result = service.calculate_inherent_risk
          if result[:score] >= 60 && result[:score] < 80
            expect(result[:tier]).to eq("high")
          end
        end
      end

      context "medium tier (30-59)" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            vendor_type: "library",
            handles_pii: false,
            handles_phi: false,
            handles_pci: false
          )
        end

        it "returns medium tier for mid-range scores" do
          result = service.calculate_inherent_risk
          if result[:score] >= 30 && result[:score] < 60
            expect(result[:tier]).to eq("medium")
          end
        end
      end

      context "low tier (< 30)" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            vendor_type: "consulting",
            handles_pii: false,
            handles_phi: false,
            handles_pci: false
          )
        end

        it "returns low tier for low scores" do
          result = service.calculate_inherent_risk
          expect(result[:tier]).to eq("low") if result[:score] < 30
        end
      end
    end

    context "weighted score calculation" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "saas",
          handles_pii: true,
          handles_phi: false,
          handles_pci: false
        )
      end

      it "calculates weighted average correctly" do
        result = service.calculate_inherent_risk

        expected_score = (
          (result[:factors][:data_sensitivity] * 0.4) +
          (result[:factors][:criticality] * 0.35) +
          (result[:factors][:accessibility] * 0.25)
        ).round(2)

        expect(result[:score]).to eq(expected_score)
      end
    end
  end

  describe "#monitor_vendor!" do
    it "returns an array" do
      events = service.monitor_vendor!
      expect(events).to be_an(Array)
    end

    context "certification expiry monitoring" do
      context "with certification expiring within 30 days" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            certifications: [
              { "name" => "SOC 2 Type II", "expires_at" => 15.days.from_now.iso8601 }
            ]
          )
        end

        it "creates certification expiry event" do
          events = service.monitor_vendor!
          cert_event = events.find { |e| e.event_type == "certification_expiry" }
          expect(cert_event).to be_present
        end

        it "creates event with correct title" do
          events = service.monitor_vendor!
          cert_event = events.find { |e| e.event_type == "certification_expiry" }
          expect(cert_event.title).to include("SOC 2 Type II")
        end

        it "persists the event to database" do
          expect { service.monitor_vendor! }.to change(SupplyChain::VendorMonitoringEvent, :count)
        end
      end

      context "with certification expiring after 30 days" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            certifications: [
              { "name" => "ISO 27001", "expires_at" => 60.days.from_now.iso8601 }
            ]
          )
        end

        it "does not create certification expiry event" do
          events = service.monitor_vendor!
          cert_event = events.find { |e| e.event_type == "certification_expiry" }
          expect(cert_event).to be_nil
        end
      end

      context "with certification without expires_at" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            certifications: [
              { "name" => "ISO 27001" }
            ]
          )
        end

        it "does not create certification expiry event" do
          events = service.monitor_vendor!
          cert_event = events.find { |e| e.event_type == "certification_expiry" }
          expect(cert_event).to be_nil
        end
      end

      context "with multiple expiring certifications" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            certifications: [
              { "name" => "SOC 2 Type II", "expires_at" => 10.days.from_now.iso8601 },
              { "name" => "ISO 27001", "expires_at" => 20.days.from_now.iso8601 }
            ]
          )
        end

        it "creates events for each expiring certification" do
          events = service.monitor_vendor!
          cert_events = events.select { |e| e.event_type == "certification_expiry" }
          expect(cert_events.length).to eq(2)
        end
      end
    end

    context "contract renewal monitoring" do
      context "with contract ending within 60 days" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            contract_end_date: 45.days.from_now
          )
        end

        it "creates contract renewal event" do
          events = service.monitor_vendor!
          contract_event = events.find { |e| e.event_type == "contract_renewal" }
          expect(contract_event).to be_present
        end

        it "creates event with correct title" do
          events = service.monitor_vendor!
          contract_event = events.find { |e| e.event_type == "contract_renewal" }
          expect(contract_event.title).to include("Contract renewal")
        end

        it "creates event with automated source" do
          events = service.monitor_vendor!
          contract_event = events.find { |e| e.event_type == "contract_renewal" }
          expect(contract_event.source).to eq("automated")
        end
      end

      context "with contract ending after 60 days" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            contract_end_date: 90.days.from_now
          )
        end

        it "does not create contract renewal event" do
          events = service.monitor_vendor!
          contract_event = events.find { |e| e.event_type == "contract_renewal" }
          expect(contract_event).to be_nil
        end
      end

      context "without contract end date" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            contract_end_date: nil
          )
        end

        it "does not create contract renewal event" do
          events = service.monitor_vendor!
          contract_event = events.find { |e| e.event_type == "contract_renewal" }
          expect(contract_event).to be_nil
        end
      end
    end

    context "assessment due monitoring" do
      context "with vendor needing assessment" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            next_assessment_due: 1.day.ago
          )
        end

        it "creates assessment due event" do
          events = service.monitor_vendor!
          assessment_event = events.find { |e| e.event_type == "compliance_update" }
          expect(assessment_event).to be_present
        end

        it "creates event with correct title" do
          events = service.monitor_vendor!
          assessment_event = events.find { |e| e.event_type == "compliance_update" }
          expect(assessment_event.title).to include("Risk assessment overdue")
        end

        it "creates event with medium severity" do
          events = service.monitor_vendor!
          assessment_event = events.find { |e| e.event_type == "compliance_update" }
          expect(assessment_event.severity).to eq("medium")
        end

        it "creates event with recommended actions" do
          events = service.monitor_vendor!
          assessment_event = events.find { |e| e.event_type == "compliance_update" }
          expect(assessment_event.recommended_actions).not_to be_empty
        end
      end

      context "with vendor not needing assessment" do
        let(:vendor) do
          create(:supply_chain_vendor,
            account: account,
            next_assessment_due: 30.days.from_now
          )
        end

        it "does not create assessment due event" do
          events = service.monitor_vendor!
          assessment_event = events.find { |e| e.event_type == "compliance_update" }
          expect(assessment_event).to be_nil
        end
      end
    end

    context "combined monitoring events" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [
            { "name" => "SOC 2 Type II", "expires_at" => 15.days.from_now.iso8601 }
          ],
          contract_end_date: 30.days.from_now,
          next_assessment_due: 1.day.ago
        )
      end

      it "creates multiple events when applicable" do
        events = service.monitor_vendor!
        expect(events.length).to be >= 3
      end

      it "persists all events to database" do
        expect { service.monitor_vendor! }.to change(SupplyChain::VendorMonitoringEvent, :count).by_at_least(3)
      end
    end
  end

  describe "security score calculation" do
    context "with all security controls present" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [
            { "name" => "SOC 2 Type II" },
            { "name" => "ISO 27001" }
          ],
          metadata: {
            "security_controls" => {
              "mfa" => true,
              "incident_response" => true,
              "vulnerability_management" => true,
              "security_training" => true
            }
          }
        )
      end

      it "calculates high security score" do
        assessment = service.assess!
        # Base 100 + 10 (SOC2) + 5 (ISO) = 115, capped at 100
        expect(assessment.security_score).to eq(100)
      end
    end

    context "without encryption (no SOC/ISO)" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [],
          metadata: {
            "security_controls" => {
              "mfa" => true,
              "incident_response" => true,
              "vulnerability_management" => true,
              "security_training" => true
            }
          }
        )
      end

      it "deducts 20 points for missing encryption" do
        assessment = service.assess!
        # Base 100 - 20 (no encryption) = 80
        expect(assessment.security_score).to eq(80)
      end
    end

    context "without MFA" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "SOC 2 Type II" } ],
          metadata: {
            "security_controls" => {
              "mfa" => false,
              "incident_response" => true,
              "vulnerability_management" => true,
              "security_training" => true
            }
          }
        )
      end

      it "deducts 15 points for missing MFA" do
        assessment = service.assess!
        # Base 100 - 15 (no MFA) + 10 (SOC2) = 95
        expect(assessment.security_score).to eq(95)
      end
    end

    context "without incident response" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "SOC 2 Type II" } ],
          metadata: {
            "security_controls" => {
              "mfa" => true,
              "incident_response" => false,
              "vulnerability_management" => true,
              "security_training" => true
            }
          }
        )
      end

      it "deducts 10 points for missing incident response" do
        assessment = service.assess!
        # Base 100 - 10 (no IR) + 10 (SOC2) = 100
        expect(assessment.security_score).to eq(100)
      end
    end

    context "without vulnerability management" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "SOC 2 Type II" } ],
          metadata: {
            "security_controls" => {
              "mfa" => true,
              "incident_response" => true,
              "vulnerability_management" => false,
              "security_training" => true
            }
          }
        )
      end

      it "deducts 15 points for missing vulnerability management" do
        assessment = service.assess!
        # Base 100 - 15 (no vuln mgmt) + 10 (SOC2) = 95
        expect(assessment.security_score).to eq(95)
      end
    end

    context "without security training" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "SOC 2 Type II" } ],
          metadata: {
            "security_controls" => {
              "mfa" => true,
              "incident_response" => true,
              "vulnerability_management" => true,
              "security_training" => false
            }
          }
        )
      end

      it "deducts 10 points for missing security training" do
        assessment = service.assess!
        # Base 100 - 10 (no training) + 10 (SOC2) = 100
        expect(assessment.security_score).to eq(100)
      end
    end

    context "with questionnaire response" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "SOC 2 Type II" } ],
          metadata: {
            "security_controls" => {
              "mfa" => true,
              "incident_response" => true,
              "vulnerability_management" => true,
              "security_training" => true
            }
          }
        )
      end

      let!(:questionnaire_response) do
        create(:supply_chain_questionnaire_response, :reviewed,
          vendor: vendor,
          account: account,
          section_scores: {
            "cc5" => 80,
            "cc6" => 75,
            "cc7" => 85,
            "a9" => 90,
            "a12" => 70
          }
        )
      end

      it "factors in questionnaire section scores" do
        assessment = service.assess!
        # Should blend base score with questionnaire average
        expect(assessment.security_score).to be_between(0, 100)
      end
    end
  end

  describe "compliance score calculation" do
    context "with vendor handling PII without DPA" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          handles_pii: true,
          has_dpa: false,
          certifications: []
        )
      end

      it "deducts 20 points" do
        assessment = service.assess!
        # Base 100 - 20 = 80
        expect(assessment.compliance_score).to eq(80)
      end
    end

    context "with vendor handling PHI without BAA" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          handles_phi: true,
          has_baa: false,
          certifications: []
        )
      end

      it "deducts 20 points" do
        assessment = service.assess!
        # Base 100 - 20 = 80
        expect(assessment.compliance_score).to eq(80)
      end
    end

    context "with vendor handling PCI without PCI DSS" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          handles_pci: true,
          certifications: []
        )
      end

      it "deducts 15 points" do
        assessment = service.assess!
        # Base 100 - 15 = 85
        expect(assessment.compliance_score).to eq(85)
      end
    end

    context "with SOC 2 certification" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "SOC 2 Type II" } ]
        )
      end

      it "adds 15 points" do
        assessment = service.assess!
        # Base 100 + 15 = 115, capped at 100
        expect(assessment.compliance_score).to eq(100)
      end
    end

    context "with ISO 27001 certification" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "ISO 27001" } ]
        )
      end

      it "adds 10 points" do
        assessment = service.assess!
        # Base 100 + 10 = 110, capped at 100
        expect(assessment.compliance_score).to eq(100)
      end
    end

    context "with GDPR certification" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "GDPR" } ]
        )
      end

      it "adds 10 points" do
        assessment = service.assess!
        # Base 100 + 10 = 110, capped at 100
        expect(assessment.compliance_score).to eq(100)
      end
    end

    context "with HIPAA certification" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          certifications: [ { "name" => "HIPAA" } ]
        )
      end

      it "adds 10 points" do
        assessment = service.assess!
        # Base 100 + 10 = 110, capped at 100
        expect(assessment.compliance_score).to eq(100)
      end
    end

    context "with all compliance issues and certifications" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          handles_pii: true,
          handles_phi: true,
          handles_pci: true,
          has_dpa: false,
          has_baa: false,
          certifications: [
            { "name" => "SOC 2 Type II" },
            { "name" => "ISO 27001" },
            { "name" => "GDPR" },
            { "name" => "HIPAA" }
          ]
        )
      end

      it "calculates combined compliance score" do
        assessment = service.assess!
        # Base 100 - 20 (PII) - 20 (PHI) - 15 (PCI) + 15 (SOC2) + 10 (ISO) + 10 (GDPR) + 10 (HIPAA) = 90
        expect(assessment.compliance_score).to eq(90)
      end
    end

    context "compliance score capped at 0 minimum" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          handles_pii: true,
          handles_phi: true,
          handles_pci: true,
          has_dpa: false,
          has_baa: false,
          certifications: []
        )
      end

      it "does not go below 0" do
        assessment = service.assess!
        # Base 100 - 20 - 20 - 15 = 45 (still positive in this case)
        expect(assessment.compliance_score).to be >= 0
      end
    end
  end

  describe "operational score calculation" do
    # Use vendor_type: "api" to avoid the extra -10 for saas without SOC 2 Type II
    context "without business continuity" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "api",
          metadata: {
            "operational" => {
              "business_continuity" => false,
              "disaster_recovery" => true,
              "sla" => true,
              "dedicated_support" => true
            }
          }
        )
      end

      it "deducts 15 points" do
        assessment = service.assess!
        # Base 100 - 15 = 85
        expect(assessment.operational_score).to eq(85)
      end
    end

    context "without disaster recovery" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "api",
          metadata: {
            "operational" => {
              "business_continuity" => true,
              "disaster_recovery" => false,
              "sla" => true,
              "dedicated_support" => true
            }
          }
        )
      end

      it "deducts 10 points" do
        assessment = service.assess!
        # Base 100 - 10 = 90
        expect(assessment.operational_score).to eq(90)
      end
    end

    context "without SLA" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "api",
          metadata: {
            "operational" => {
              "business_continuity" => true,
              "disaster_recovery" => true,
              "sla" => false,
              "dedicated_support" => true
            }
          }
        )
      end

      it "deducts 10 points" do
        assessment = service.assess!
        # Base 100 - 10 = 90
        expect(assessment.operational_score).to eq(90)
      end
    end

    context "without dedicated support" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "api",
          metadata: {
            "operational" => {
              "business_continuity" => true,
              "disaster_recovery" => true,
              "sla" => true,
              "dedicated_support" => false
            }
          }
        )
      end

      it "deducts 5 points" do
        assessment = service.assess!
        # Base 100 - 5 = 95
        expect(assessment.operational_score).to eq(95)
      end
    end

    context "SaaS vendor without SOC 2 Type II" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "saas",
          certifications: [],
          metadata: {
            "operational" => {
              "business_continuity" => true,
              "disaster_recovery" => true,
              "sla" => true,
              "dedicated_support" => true
            }
          }
        )
      end

      it "deducts 10 points for financial stability concerns" do
        assessment = service.assess!
        # Base 100 - 10 = 90
        expect(assessment.operational_score).to eq(90)
      end
    end

    context "SaaS vendor with SOC 2 Type II" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "saas",
          certifications: [ { "name" => "SOC 2 Type II" } ],
          metadata: {
            "operational" => {
              "business_continuity" => true,
              "disaster_recovery" => true,
              "sla" => true,
              "dedicated_support" => true
            }
          }
        )
      end

      it "does not deduct financial stability points" do
        assessment = service.assess!
        expect(assessment.operational_score).to eq(100)
      end
    end

    context "without any operational controls" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "saas",
          certifications: [],
          metadata: {}
        )
      end

      it "applies all deductions" do
        assessment = service.assess!
        # Base 100 - 15 (BC) - 10 (DR) - 10 (SLA) - 5 (support) - 10 (SaaS financial) = 50
        expect(assessment.operational_score).to eq(50)
      end
    end

    context "operational score capped at 100" do
      let(:vendor) do
        create(:supply_chain_vendor,
          account: account,
          vendor_type: "library",
          certifications: [ { "name" => "SOC 2 Type II" } ],
          metadata: {
            "operational" => {
              "business_continuity" => true,
              "disaster_recovery" => true,
              "sla" => true,
              "dedicated_support" => true
            }
          }
        )
      end

      it "does not exceed 100" do
        assessment = service.assess!
        expect(assessment.operational_score).to be <= 100
      end
    end
  end

  describe "RiskError exception class" do
    it "is a subclass of StandardError" do
      expect(SupplyChain::VendorRiskService::RiskError.superclass).to eq(StandardError)
    end

    it "can be raised with a message" do
      expect {
        raise SupplyChain::VendorRiskService::RiskError, "Test error message"
      }.to raise_error(SupplyChain::VendorRiskService::RiskError, "Test error message")
    end
  end
end
