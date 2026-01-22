# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::RiskAssessment, type: :model do
  let(:account) { create(:account) }
  let(:vendor) { create(:supply_chain_vendor, account: account) }
  let(:user) { create(:user, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:vendor).class_name("SupplyChain::Vendor") }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:assessor).class_name("User").optional }
    it { is_expected.to have_many(:questionnaire_responses).class_name("SupplyChain::QuestionnaireResponse").dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:supply_chain_risk_assessment, vendor: vendor, account: account) }

    it { is_expected.to validate_presence_of(:assessment_type) }
    it { is_expected.to validate_inclusion_of(:assessment_type).in_array(SupplyChain::RiskAssessment::ASSESSMENT_TYPES) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::RiskAssessment::STATUSES) }
    it { is_expected.to validate_numericality_of(:security_score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
    it { is_expected.to validate_numericality_of(:compliance_score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
    it { is_expected.to validate_numericality_of(:operational_score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
    it { is_expected.to validate_numericality_of(:overall_score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
  end

  describe "scopes" do
    let!(:draft_assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, status: "draft") }
    let!(:in_progress_assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, status: "in_progress") }
    let!(:pending_assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, status: "pending_review") }
    let!(:completed_assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, status: "completed", valid_until: 1.year.from_now) }
    let!(:expired_assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, status: "expired") }
    let!(:initial_assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, assessment_type: "initial") }
    let!(:periodic_assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, assessment_type: "periodic") }
    let!(:expiring_soon_assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, status: "completed", valid_until: 15.days.from_now) }

    it "filters by status" do
      expect(described_class.by_status("draft")).to include(draft_assessment)
      expect(described_class.by_status("draft")).not_to include(completed_assessment)
    end

    it "filters draft assessments" do
      expect(described_class.draft).to include(draft_assessment)
    end

    it "filters in_progress assessments" do
      expect(described_class.in_progress).to include(in_progress_assessment)
    end

    it "filters pending_review assessments" do
      expect(described_class.pending_review).to include(pending_assessment)
    end

    it "filters completed assessments" do
      expect(described_class.completed).to include(completed_assessment)
    end

    it "filters expired assessments" do
      expect(described_class.expired).to include(expired_assessment)
    end

    it "filters by assessment type" do
      expect(described_class.by_type("initial")).to include(initial_assessment)
      expect(described_class.by_type("initial")).not_to include(periodic_assessment)
    end

    it "filters initial assessments" do
      expect(described_class.initial).to include(initial_assessment)
    end

    it "filters periodic assessments" do
      expect(described_class.periodic).to include(periodic_assessment)
    end

    it "filters valid assessments" do
      expect(described_class.valid).to include(completed_assessment)
      expect(described_class.valid).not_to include(expired_assessment)
    end

    it "filters expiring_soon assessments" do
      expect(described_class.expiring_soon(30)).to include(expiring_soon_assessment)
      expect(described_class.expiring_soon(30)).not_to include(completed_assessment)
    end
  end

  describe "status predicates" do
    it "#draft? returns true for draft status" do
      assessment = build(:supply_chain_risk_assessment, status: "draft")
      expect(assessment.draft?).to be true
    end

    it "#in_progress? returns true for in_progress status" do
      assessment = build(:supply_chain_risk_assessment, status: "in_progress")
      expect(assessment.in_progress?).to be true
    end

    it "#pending_review? returns true for pending_review status" do
      assessment = build(:supply_chain_risk_assessment, status: "pending_review")
      expect(assessment.pending_review?).to be true
    end

    it "#completed? returns true for completed status" do
      assessment = build(:supply_chain_risk_assessment, status: "completed")
      expect(assessment.completed?).to be true
    end

    it "#expired? returns true for expired status" do
      assessment = build(:supply_chain_risk_assessment, status: "expired")
      expect(assessment.expired?).to be true
    end
  end

  describe "assessment type predicates" do
    it "#initial? returns true for initial type" do
      assessment = build(:supply_chain_risk_assessment, assessment_type: "initial")
      expect(assessment.initial?).to be true
    end

    it "#periodic? returns true for periodic type" do
      assessment = build(:supply_chain_risk_assessment, assessment_type: "periodic")
      expect(assessment.periodic?).to be true
    end

    it "#incident? returns true for incident type" do
      assessment = build(:supply_chain_risk_assessment, assessment_type: "incident")
      expect(assessment.incident?).to be true
    end

    it "#renewal? returns true for renewal type" do
      assessment = build(:supply_chain_risk_assessment, assessment_type: "renewal")
      expect(assessment.renewal?).to be true
    end
  end

  describe "#currently_valid?" do
    it "returns true for completed assessment with no expiry" do
      assessment = build(:supply_chain_risk_assessment, status: "completed", valid_until: nil)
      expect(assessment.currently_valid?).to be true
    end

    it "returns true for completed assessment with future expiry" do
      assessment = build(:supply_chain_risk_assessment, status: "completed", valid_until: 1.year.from_now)
      expect(assessment.currently_valid?).to be true
    end

    it "returns false for completed assessment with past expiry" do
      assessment = build(:supply_chain_risk_assessment, status: "completed", valid_until: 1.day.ago)
      expect(assessment.currently_valid?).to be false
    end

    it "returns false for non-completed assessment" do
      assessment = build(:supply_chain_risk_assessment, status: "draft", valid_until: 1.year.from_now)
      expect(assessment.currently_valid?).to be false
    end
  end

  describe "#expiring_soon?" do
    it "returns true when within threshold" do
      assessment = build(:supply_chain_risk_assessment, valid_until: 15.days.from_now)
      expect(assessment.expiring_soon?(30)).to be true
    end

    it "returns false when beyond threshold" do
      assessment = build(:supply_chain_risk_assessment, valid_until: 60.days.from_now)
      expect(assessment.expiring_soon?(30)).to be false
    end

    it "returns false when no expiry set" do
      assessment = build(:supply_chain_risk_assessment, valid_until: nil)
      expect(assessment.expiring_soon?).to be false
    end
  end

  describe "#days_until_expiry" do
    it "returns days until expiry" do
      assessment = build(:supply_chain_risk_assessment, valid_until: 30.days.from_now)
      expect(assessment.days_until_expiry).to be_within(1).of(30)
    end

    it "returns nil when no expiry" do
      assessment = build(:supply_chain_risk_assessment, valid_until: nil)
      expect(assessment.days_until_expiry).to be_nil
    end
  end

  describe "findings management" do
    let(:assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, findings: []) }

    describe "#finding_count" do
      it "returns the number of findings" do
        assessment.update!(findings: [{ id: "1" }, { id: "2" }])
        expect(assessment.finding_count).to eq(2)
      end

      it "returns 0 when findings is nil" do
        # Build a new instance and test the method handles nil gracefully
        # (can't use update_column due to DB NOT NULL constraint)
        new_assessment = build(:supply_chain_risk_assessment, vendor: vendor, account: account)
        new_assessment.findings = nil
        expect(new_assessment.finding_count).to eq(0)
      end
    end

    describe "#critical_findings" do
      it "returns only critical findings" do
        assessment.update!(findings: [
                             { "id" => "1", "severity" => "critical" },
                             { "id" => "2", "severity" => "high" }
                           ])
        expect(assessment.critical_findings.length).to eq(1)
      end
    end

    describe "#high_findings" do
      it "returns only high findings" do
        assessment.update!(findings: [
                             { "id" => "1", "severity" => "critical" },
                             { "id" => "2", "severity" => "high" }
                           ])
        expect(assessment.high_findings.length).to eq(1)
      end
    end

    describe "#open_findings" do
      it "returns only open findings" do
        assessment.update!(findings: [
                             { "id" => "1", "status" => "open" },
                             { "id" => "2", "status" => "resolved" }
                           ])
        expect(assessment.open_findings.length).to eq(1)
      end
    end

    describe "#add_finding" do
      it "adds a finding" do
        assessment.add_finding(title: "Test Finding", severity: "high", description: "Description")
        expect(assessment.finding_count).to eq(1)
        expect(assessment.findings.first).to include("title" => "Test Finding")
      end

      it "assigns a UUID" do
        assessment.add_finding(title: "Test", severity: "medium", description: "Desc")
        expect(assessment.findings.first["id"]).to be_present
      end
    end

    describe "#resolve_finding" do
      before do
        assessment.add_finding(title: "Test", severity: "high", description: "Desc")
      end

      it "marks finding as resolved" do
        finding_id = assessment.findings.first["id"]
        assessment.resolve_finding(finding_id, resolution: "Fixed the issue")

        resolved = assessment.findings.find { |f| f["id"] == finding_id }
        expect(resolved["status"]).to eq("resolved")
        expect(resolved["resolution"]).to eq("Fixed the issue")
        expect(resolved["resolved_at"]).to be_present
      end
    end
  end

  describe "#recommendation_count" do
    let(:assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account) }

    it "returns the number of recommendations" do
      assessment.update!(recommendations: [{ id: "1" }, { id: "2" }])
      expect(assessment.recommendation_count).to eq(2)
    end
  end

  describe "#add_recommendation" do
    let(:assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, recommendations: []) }

    it "adds a recommendation" do
      assessment.add_recommendation(title: "Recommendation", priority: "high", description: "Do this")
      expect(assessment.recommendation_count).to eq(1)
    end
  end

  describe "#add_evidence" do
    let(:assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, evidence: []) }

    it "adds evidence" do
      assessment.add_evidence(name: "SOC2 Report", type: "document", url: "https://example.com/soc2.pdf")
      expect(assessment.evidence.length).to eq(1)
      expect(assessment.evidence.first).to include("name" => "SOC2 Report")
    end
  end

  describe "#risk_level" do
    it "returns critical for score 80-100" do
      assessment = build(:supply_chain_risk_assessment, overall_score: 85)
      expect(assessment.risk_level).to eq("critical")
    end

    it "returns high for score 60-79" do
      assessment = build(:supply_chain_risk_assessment, overall_score: 70)
      expect(assessment.risk_level).to eq("high")
    end

    it "returns medium for score 30-59" do
      assessment = build(:supply_chain_risk_assessment, overall_score: 45)
      expect(assessment.risk_level).to eq("medium")
    end

    it "returns low for score below 30" do
      assessment = build(:supply_chain_risk_assessment, overall_score: 20)
      expect(assessment.risk_level).to eq("low")
    end
  end

  describe "state transitions" do
    let(:assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account, status: "draft") }

    describe "#start!" do
      it "changes status to in_progress" do
        assessment.start!
        expect(assessment.status).to eq("in_progress")
      end

      it "sets assessment_date" do
        assessment.start!
        expect(assessment.assessment_date).to be_present
      end
    end

    describe "#submit_for_review!" do
      it "changes status to pending_review" do
        assessment.submit_for_review!
        expect(assessment.status).to eq("pending_review")
      end
    end

    describe "#complete!" do
      it "changes status to completed" do
        assessment.complete!
        expect(assessment.status).to eq("completed")
      end

      it "sets completed_at" do
        assessment.complete!
        expect(assessment.completed_at).to be_present
      end

      it "sets valid_until based on months param" do
        assessment.complete!(6)
        expect(assessment.valid_until).to be_within(1.day).of(6.months.from_now)
      end
    end

    describe "#expire!" do
      it "changes status to expired" do
        assessment.expire!
        expect(assessment.status).to eq("expired")
      end
    end
  end

  describe "#summary" do
    let(:assessment) { create(:supply_chain_risk_assessment, vendor: vendor, account: account) }

    it "returns expected keys" do
      summary = assessment.summary

      expect(summary).to include(
        :id,
        :vendor_id,
        :vendor_name,
        :assessment_type,
        :status,
        :scores,
        :risk_level,
        :finding_count,
        :critical_finding_count,
        :open_finding_count,
        :recommendation_count,
        :assessment_date,
        :completed_at,
        :valid_until,
        :is_valid,
        :created_at
      )
    end
  end

  describe "callbacks" do
    describe "calculate_overall_score" do
      it "calculates weighted average score" do
        assessment = build(:supply_chain_risk_assessment,
                          vendor: vendor,
                          account: account,
                          security_score: 80,
                          compliance_score: 60,
                          operational_score: 40,
                          overall_score: 0)
        assessment.save!

        # 80 * 0.4 + 60 * 0.35 + 40 * 0.25 = 32 + 21 + 10 = 63
        expect(assessment.overall_score).to eq(63)
      end

      it "recalculates when scores change" do
        assessment = create(:supply_chain_risk_assessment, vendor: vendor, account: account, security_score: 50, compliance_score: 50, operational_score: 50)
        original_score = assessment.overall_score

        assessment.update!(security_score: 80)
        expect(assessment.overall_score).not_to eq(original_score)
      end
    end
  end

  describe "JSONB sanitization" do
    it "initializes findings as empty array" do
      assessment = create(:supply_chain_risk_assessment, vendor: vendor, account: account, findings: nil)
      expect(assessment.findings).to eq([])
    end

    it "initializes recommendations as empty array" do
      assessment = create(:supply_chain_risk_assessment, vendor: vendor, account: account, recommendations: nil)
      expect(assessment.recommendations).to eq([])
    end

    it "initializes evidence as empty array" do
      assessment = create(:supply_chain_risk_assessment, vendor: vendor, account: account, evidence: nil)
      expect(assessment.evidence).to eq([])
    end

    it "initializes metadata as empty hash" do
      assessment = create(:supply_chain_risk_assessment, vendor: vendor, account: account, metadata: nil)
      expect(assessment.metadata).to eq({})
    end
  end
end
