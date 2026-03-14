# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::RemediationPlan, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }
  let(:user) { create(:user, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:sbom).class_name("SupplyChain::Sbom") }
    # TODO: Enable when AiWorkflowRun model is created
    # it { is_expected.to belong_to(:workflow_run).class_name("AiWorkflowRun").optional }
    it { is_expected.to belong_to(:created_by).class_name("User").optional }
    it { is_expected.to belong_to(:approved_by).class_name("User").optional }
  end

  describe "validations" do
    subject { build(:supply_chain_remediation_plan, account: account, sbom: sbom) }

    it { is_expected.to validate_presence_of(:plan_type) }
    it { is_expected.to validate_inclusion_of(:plan_type).in_array(SupplyChain::RemediationPlan::PLAN_TYPES) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::RemediationPlan::STATUSES) }

    describe "confidence_score validation" do
      it "allows nil confidence_score" do
        plan = build(:supply_chain_remediation_plan, account: account, sbom: sbom, confidence_score: nil)
        expect(plan).to be_valid
      end

      it "allows confidence_score of 0" do
        plan = build(:supply_chain_remediation_plan, account: account, sbom: sbom, confidence_score: 0)
        expect(plan).to be_valid
      end

      it "allows confidence_score of 1" do
        plan = build(:supply_chain_remediation_plan, account: account, sbom: sbom, confidence_score: 1)
        expect(plan).to be_valid
      end

      it "rejects confidence_score below 0" do
        plan = build(:supply_chain_remediation_plan, account: account, sbom: sbom, confidence_score: -0.1)
        expect(plan).not_to be_valid
        expect(plan.errors[:confidence_score]).to be_present
      end

      it "rejects confidence_score above 1" do
        plan = build(:supply_chain_remediation_plan, account: account, sbom: sbom, confidence_score: 1.1)
        expect(plan).not_to be_valid
        expect(plan.errors[:confidence_score]).to be_present
      end
    end
  end

  describe "scopes" do
    let!(:draft_plan) { create(:supply_chain_remediation_plan, :draft, account: account, sbom: sbom) }
    let!(:pending_plan) { create(:supply_chain_remediation_plan, :pending_review, account: account, sbom: sbom) }
    let!(:approved_plan) { create(:supply_chain_remediation_plan, :approved, account: account, sbom: sbom) }
    let!(:rejected_plan) { create(:supply_chain_remediation_plan, :rejected, account: account, sbom: sbom) }
    let!(:executing_plan) { create(:supply_chain_remediation_plan, :executing, account: account, sbom: sbom) }
    let!(:completed_plan) { create(:supply_chain_remediation_plan, :completed, account: account, sbom: sbom) }
    let!(:failed_plan) { create(:supply_chain_remediation_plan, :failed, account: account, sbom: sbom) }
    let!(:ai_plan) { create(:supply_chain_remediation_plan, :ai_generated, account: account, sbom: sbom) }
    let!(:auto_exec_plan) { create(:supply_chain_remediation_plan, :auto_executable_plan, account: account, sbom: sbom) }
    let!(:high_conf_plan) { create(:supply_chain_remediation_plan, :high_confidence, account: account, sbom: sbom) }
    let!(:old_plan) { create(:supply_chain_remediation_plan, account: account, sbom: sbom, created_at: 1.week.ago) }

    describe ".by_status" do
      it "filters by status" do
        expect(described_class.by_status("draft")).to include(draft_plan)
        expect(described_class.by_status("draft")).not_to include(approved_plan)
      end
    end

    describe ".draft" do
      it "returns only draft plans" do
        expect(described_class.draft).to include(draft_plan)
        expect(described_class.draft).not_to include(approved_plan)
      end
    end

    describe ".pending_review" do
      it "returns only pending_review plans" do
        expect(described_class.pending_review).to include(pending_plan)
        expect(described_class.pending_review).not_to include(draft_plan)
      end
    end

    describe ".approved" do
      it "returns only approved plans" do
        expect(described_class.approved).to include(approved_plan)
        expect(described_class.approved).not_to include(draft_plan)
      end
    end

    describe ".rejected" do
      it "returns only rejected plans" do
        expect(described_class.rejected).to include(rejected_plan)
        expect(described_class.rejected).not_to include(approved_plan)
      end
    end

    describe ".executing" do
      it "returns only executing plans" do
        expect(described_class.executing).to include(executing_plan)
        expect(described_class.executing).not_to include(completed_plan)
      end
    end

    describe ".completed" do
      it "returns only completed plans" do
        expect(described_class.completed).to include(completed_plan)
        expect(described_class.completed).not_to include(executing_plan)
      end
    end

    describe ".failed" do
      it "returns only failed plans" do
        expect(described_class.failed).to include(failed_plan)
        expect(described_class.failed).not_to include(completed_plan)
      end
    end

    describe ".actionable" do
      it "returns draft, pending_review, and approved plans" do
        actionable = described_class.actionable
        expect(actionable).to include(draft_plan, pending_plan, approved_plan)
        expect(actionable).not_to include(rejected_plan, executing_plan, completed_plan, failed_plan)
      end
    end

    describe ".ai_generated" do
      it "returns only ai_generated plans" do
        expect(described_class.ai_generated).to include(ai_plan)
        expect(described_class.ai_generated).not_to include(draft_plan)
      end
    end

    describe ".auto_executable" do
      it "returns only auto_executable plans" do
        expect(described_class.auto_executable).to include(auto_exec_plan)
        expect(described_class.auto_executable).not_to include(draft_plan)
      end
    end

    describe ".high_confidence" do
      it "returns plans with confidence >= 0.8" do
        expect(described_class.high_confidence).to include(high_conf_plan)
        expect(described_class.high_confidence).not_to include(draft_plan)
      end
    end

    describe ".recent" do
      it "orders by created_at desc" do
        recent = described_class.recent
        expect(recent.first.created_at).to be > recent.last.created_at
      end
    end
  end

  describe "status predicates" do
    describe "#draft?" do
      it "returns true for draft status" do
        plan = build(:supply_chain_remediation_plan, status: "draft")
        expect(plan.draft?).to be true
      end

      it "returns false for non-draft status" do
        plan = build(:supply_chain_remediation_plan, status: "approved")
        expect(plan.draft?).to be false
      end
    end

    describe "#pending_review?" do
      it "returns true for pending_review status" do
        plan = build(:supply_chain_remediation_plan, status: "pending_review")
        expect(plan.pending_review?).to be true
      end

      it "returns false for non-pending_review status" do
        plan = build(:supply_chain_remediation_plan, status: "draft")
        expect(plan.pending_review?).to be false
      end
    end

    describe "#approved?" do
      it "returns true for approved status" do
        plan = build(:supply_chain_remediation_plan, status: "approved")
        expect(plan.approved?).to be true
      end

      it "returns false for non-approved status" do
        plan = build(:supply_chain_remediation_plan, status: "draft")
        expect(plan.approved?).to be false
      end
    end

    describe "#rejected?" do
      it "returns true for rejected status" do
        plan = build(:supply_chain_remediation_plan, status: "rejected")
        expect(plan.rejected?).to be true
      end

      it "returns false for non-rejected status" do
        plan = build(:supply_chain_remediation_plan, status: "approved")
        expect(plan.rejected?).to be false
      end
    end

    describe "#executing?" do
      it "returns true for executing status" do
        plan = build(:supply_chain_remediation_plan, status: "executing")
        expect(plan.executing?).to be true
      end

      it "returns false for non-executing status" do
        plan = build(:supply_chain_remediation_plan, status: "completed")
        expect(plan.executing?).to be false
      end
    end

    describe "#completed?" do
      it "returns true for completed status" do
        plan = build(:supply_chain_remediation_plan, status: "completed")
        expect(plan.completed?).to be true
      end

      it "returns false for non-completed status" do
        plan = build(:supply_chain_remediation_plan, status: "executing")
        expect(plan.completed?).to be false
      end
    end

    describe "#failed?" do
      it "returns true for failed status" do
        plan = build(:supply_chain_remediation_plan, status: "failed")
        expect(plan.failed?).to be true
      end

      it "returns false for non-failed status" do
        plan = build(:supply_chain_remediation_plan, status: "completed")
        expect(plan.failed?).to be false
      end
    end
  end

  describe "plan type predicates" do
    describe "#manual?" do
      it "returns true for manual plan_type" do
        plan = build(:supply_chain_remediation_plan, plan_type: "manual")
        expect(plan.manual?).to be true
      end

      it "returns false for non-manual plan_type" do
        plan = build(:supply_chain_remediation_plan, plan_type: "ai_generated")
        expect(plan.manual?).to be false
      end
    end

    describe "#ai_generated?" do
      it "returns true for ai_generated plan_type" do
        plan = build(:supply_chain_remediation_plan, plan_type: "ai_generated")
        expect(plan.ai_generated?).to be true
      end

      it "returns false for non-ai_generated plan_type" do
        plan = build(:supply_chain_remediation_plan, plan_type: "manual")
        expect(plan.ai_generated?).to be false
      end
    end

    describe "#auto_fix?" do
      it "returns true for auto_fix plan_type" do
        plan = build(:supply_chain_remediation_plan, plan_type: "auto_fix")
        expect(plan.auto_fix?).to be true
      end

      it "returns false for non-auto_fix plan_type" do
        plan = build(:supply_chain_remediation_plan, plan_type: "manual")
        expect(plan.auto_fix?).to be false
      end
    end
  end

  describe "#can_execute?" do
    it "returns true for approved and auto_executable plan" do
      plan = build(:supply_chain_remediation_plan, status: "approved", auto_executable: true)
      expect(plan.can_execute?).to be true
    end

    it "returns true for approved and manual plan" do
      plan = build(:supply_chain_remediation_plan, status: "approved", plan_type: "manual", auto_executable: false)
      expect(plan.can_execute?).to be true
    end

    it "returns false for non-approved plan" do
      plan = build(:supply_chain_remediation_plan, status: "draft", auto_executable: true)
      expect(plan.can_execute?).to be false
    end

    it "returns false for approved but not auto_executable and not manual" do
      plan = build(:supply_chain_remediation_plan, status: "approved", plan_type: "ai_generated", auto_executable: false)
      expect(plan.can_execute?).to be false
    end
  end

  describe "#high_confidence?" do
    it "returns true when confidence_score >= 0.8" do
      plan = build(:supply_chain_remediation_plan, confidence_score: 0.8)
      expect(plan.high_confidence?).to be true
    end

    it "returns true when confidence_score is 0.95" do
      plan = build(:supply_chain_remediation_plan, confidence_score: 0.95)
      expect(plan.high_confidence?).to be true
    end

    it "returns false when confidence_score < 0.8" do
      plan = build(:supply_chain_remediation_plan, confidence_score: 0.79)
      expect(plan.high_confidence?).to be false
    end

    it "returns false when confidence_score is nil" do
      plan = build(:supply_chain_remediation_plan, confidence_score: nil)
      expect(plan.high_confidence?).to be false
    end
  end

  describe "#has_breaking_changes?" do
    it "returns true when breaking_changes is present and not empty" do
      plan = build(:supply_chain_remediation_plan, breaking_changes: [ { "package" => "axios" } ])
      expect(plan.has_breaking_changes?).to be true
    end

    it "returns false when breaking_changes is empty array" do
      plan = build(:supply_chain_remediation_plan, breaking_changes: [])
      expect(plan.has_breaking_changes?).to be false
    end

    it "returns false when breaking_changes is nil" do
      plan = build(:supply_chain_remediation_plan)
      plan.breaking_changes = nil
      expect(plan.has_breaking_changes?).to be false
    end
  end

  describe "#target_vulnerability_count" do
    it "returns the count of target_vulnerabilities" do
      plan = build(:supply_chain_remediation_plan, target_vulnerabilities: [ { "id" => "1" }, { "id" => "2" } ])
      expect(plan.target_vulnerability_count).to eq(2)
    end

    it "returns 0 when target_vulnerabilities is empty" do
      plan = build(:supply_chain_remediation_plan, target_vulnerabilities: [])
      expect(plan.target_vulnerability_count).to eq(0)
    end

    it "returns 0 when target_vulnerabilities is nil" do
      plan = build(:supply_chain_remediation_plan)
      plan.target_vulnerabilities = nil
      expect(plan.target_vulnerability_count).to eq(0)
    end
  end

  describe "#upgrade_count" do
    it "returns the count of upgrade_recommendations" do
      plan = build(:supply_chain_remediation_plan, upgrade_recommendations: [ { "package" => "a" }, { "package" => "b" } ])
      expect(plan.upgrade_count).to eq(2)
    end

    it "returns 0 when upgrade_recommendations is empty" do
      plan = build(:supply_chain_remediation_plan, upgrade_recommendations: [])
      expect(plan.upgrade_count).to eq(0)
    end

    it "returns 0 when upgrade_recommendations is nil" do
      plan = build(:supply_chain_remediation_plan)
      plan.upgrade_recommendations = nil
      expect(plan.upgrade_count).to eq(0)
    end
  end

  describe "review workflow" do
    describe "#submit_for_review!" do
      it "updates status to pending_review" do
        plan = create(:supply_chain_remediation_plan, :draft, account: account, sbom: sbom)
        plan.submit_for_review!
        expect(plan.status).to eq("pending_review")
      end

      it "persists the change" do
        plan = create(:supply_chain_remediation_plan, :draft, account: account, sbom: sbom)
        plan.submit_for_review!
        plan.reload
        expect(plan.status).to eq("pending_review")
      end
    end

    describe "#approve!" do
      let(:plan) { create(:supply_chain_remediation_plan, :pending_review, account: account, sbom: sbom) }
      let(:approver) { create(:user, account: account) }

      it "updates status to approved" do
        plan.approve!(approver)
        expect(plan.status).to eq("approved")
      end

      it "sets approval_status to approved" do
        plan.approve!(approver)
        expect(plan.approval_status).to eq("approved")
      end

      it "sets approved_by" do
        plan.approve!(approver)
        expect(plan.approved_by).to eq(approver)
      end

      it "sets approved_at" do
        freeze_time do
          plan.approve!(approver)
          expect(plan.approved_at).to be_within(1.second).of(Time.current)
        end
      end

      it "persists all changes" do
        plan.approve!(approver)
        plan.reload
        expect(plan.status).to eq("approved")
        expect(plan.approval_status).to eq("approved")
        expect(plan.approved_by).to eq(approver)
        expect(plan.approved_at).to be_present
      end
    end

    describe "#reject!" do
      let(:plan) { create(:supply_chain_remediation_plan, :pending_review, account: account, sbom: sbom) }
      let(:rejector) { create(:user, account: account) }

      it "updates status to rejected" do
        plan.reject!(rejector, "Not suitable")
        expect(plan.status).to eq("rejected")
      end

      it "sets approval_status to rejected" do
        plan.reject!(rejector, "Not suitable")
        expect(plan.approval_status).to eq("rejected")
      end

      it "sets approved_by" do
        plan.reject!(rejector, "Not suitable")
        expect(plan.approved_by).to eq(rejector)
      end

      it "sets approved_at" do
        freeze_time do
          plan.reject!(rejector, "Not suitable")
          expect(plan.approved_at).to be_within(1.second).of(Time.current)
        end
      end

      it "stores rejection reason in metadata" do
        plan.reject!(rejector, "Not suitable")
        expect(plan.metadata["rejection_reason"]).to eq("Not suitable")
      end

      it "works without rejection reason" do
        plan.reject!(rejector)
        expect(plan.status).to eq("rejected")
        expect(plan.metadata["rejection_reason"]).to be_nil
      end

      it "persists all changes" do
        plan.reject!(rejector, "Too risky")
        plan.reload
        expect(plan.status).to eq("rejected")
        expect(plan.approval_status).to eq("rejected")
        expect(plan.approved_by).to eq(rejector)
        expect(plan.approved_at).to be_present
        expect(plan.metadata["rejection_reason"]).to eq("Too risky")
      end
    end
  end

  describe "execution workflow" do
    describe "#start_execution!" do
      it "updates status to executing" do
        plan = create(:supply_chain_remediation_plan, :approved, account: account, sbom: sbom)
        plan.start_execution!
        expect(plan.status).to eq("executing")
      end

      it "persists the change" do
        plan = create(:supply_chain_remediation_plan, :approved, account: account, sbom: sbom)
        plan.start_execution!
        plan.reload
        expect(plan.status).to eq("executing")
      end
    end

    describe "#complete_execution!" do
      let(:plan) { create(:supply_chain_remediation_plan, :executing, account: account, sbom: sbom) }

      it "updates status to completed" do
        plan.complete_execution!
        expect(plan.status).to eq("completed")
      end

      it "sets generated_pr_url when provided" do
        pr_url = "https://github.com/org/repo/pull/123"
        plan.complete_execution!(pr_url)
        expect(plan.generated_pr_url).to eq(pr_url)
      end

      it "does not set generated_pr_url when not provided" do
        plan.complete_execution!
        expect(plan.generated_pr_url).to be_nil
      end

      it "persists all changes" do
        pr_url = "https://github.com/org/repo/pull/456"
        plan.complete_execution!(pr_url)
        plan.reload
        expect(plan.status).to eq("completed")
        expect(plan.generated_pr_url).to eq(pr_url)
      end
    end

    describe "#fail_execution!" do
      let(:plan) { create(:supply_chain_remediation_plan, :executing, account: account, sbom: sbom) }

      it "updates status to failed" do
        plan.fail_execution!("Network error")
        expect(plan.status).to eq("failed")
      end

      it "stores error message in metadata" do
        plan.fail_execution!("Network error")
        expect(plan.metadata["execution_error"]).to eq("Network error")
      end

      it "persists all changes" do
        plan.fail_execution!("API timeout")
        plan.reload
        expect(plan.status).to eq("failed")
        expect(plan.metadata["execution_error"]).to eq("API timeout")
      end
    end
  end

  describe "#add_upgrade_recommendation" do
    let(:plan) { create(:supply_chain_remediation_plan, account: account, sbom: sbom) }

    context "with non-breaking change" do
      it "adds upgrade recommendation" do
        plan.add_upgrade_recommendation(
          package_name: "lodash",
          current_version: "4.17.15",
          target_version: "4.17.21",
          reason: "Security fix",
          breaking: false
        )

        expect(plan.upgrade_recommendations.length).to eq(1)
        recommendation = plan.upgrade_recommendations.first
        expect(recommendation["package_name"]).to eq("lodash")
        expect(recommendation["current_version"]).to eq("4.17.15")
        expect(recommendation["target_version"]).to eq("4.17.21")
        expect(recommendation["reason"]).to eq("Security fix")
        expect(recommendation["is_breaking"]).to be false
        expect(recommendation["added_at"]).to be_present
      end

      it "does not add to breaking_changes" do
        plan.add_upgrade_recommendation(
          package_name: "lodash",
          current_version: "4.17.15",
          target_version: "4.17.21",
          breaking: false
        )

        expect(plan.breaking_changes).to be_empty
      end

      it "persists the changes" do
        plan.add_upgrade_recommendation(
          package_name: "lodash",
          current_version: "4.17.15",
          target_version: "4.17.21",
          breaking: false
        )

        plan.reload
        expect(plan.upgrade_recommendations.length).to eq(1)
      end
    end

    context "with breaking change" do
      it "adds upgrade recommendation with is_breaking flag" do
        plan.add_upgrade_recommendation(
          package_name: "axios",
          current_version: "0.21.1",
          target_version: "1.6.0",
          reason: "Major version upgrade",
          breaking: true
        )

        recommendation = plan.upgrade_recommendations.first
        expect(recommendation["is_breaking"]).to be true
      end

      it "adds to breaking_changes array" do
        plan.add_upgrade_recommendation(
          package_name: "axios",
          current_version: "0.21.1",
          target_version: "1.6.0",
          reason: "Major version upgrade",
          breaking: true
        )

        expect(plan.breaking_changes.length).to eq(1)
        breaking_change = plan.breaking_changes.first
        expect(breaking_change["package_name"]).to eq("axios")
        expect(breaking_change["from_version"]).to eq("0.21.1")
        expect(breaking_change["to_version"]).to eq("1.6.0")
        expect(breaking_change["description"]).to eq("Major version upgrade")
      end

      it "persists both upgrade_recommendations and breaking_changes" do
        plan.add_upgrade_recommendation(
          package_name: "axios",
          current_version: "0.21.1",
          target_version: "1.6.0",
          reason: "Major upgrade",
          breaking: true
        )

        plan.reload
        expect(plan.upgrade_recommendations.length).to eq(1)
        expect(plan.breaking_changes.length).to eq(1)
      end
    end

    context "with multiple upgrades" do
      it "accumulates upgrade recommendations" do
        plan.add_upgrade_recommendation(
          package_name: "lodash",
          current_version: "4.17.15",
          target_version: "4.17.21",
          breaking: false
        )

        plan.add_upgrade_recommendation(
          package_name: "axios",
          current_version: "0.21.1",
          target_version: "1.6.0",
          breaking: true
        )

        expect(plan.upgrade_recommendations.length).to eq(2)
        expect(plan.breaking_changes.length).to eq(1)
      end
    end
  end

  describe "#summary" do
    let(:plan) { create(:supply_chain_remediation_plan, :with_vulnerabilities, :with_upgrades, :with_breaking_changes, account: account, sbom: sbom) }

    it "returns expected keys" do
      summary = plan.summary

      expect(summary).to include(
        :id,
        :plan_type,
        :status,
        :target_vulnerability_count,
        :upgrade_count,
        :has_breaking_changes,
        :confidence_score,
        :auto_executable,
        :approval_status,
        :generated_pr_url,
        :created_at
      )
    end

    it "returns correct values" do
      summary = plan.summary

      expect(summary[:id]).to eq(plan.id)
      expect(summary[:plan_type]).to eq(plan.plan_type)
      expect(summary[:status]).to eq(plan.status)
      expect(summary[:target_vulnerability_count]).to eq(2)
      expect(summary[:upgrade_count]).to eq(2)
      expect(summary[:has_breaking_changes]).to be true
      expect(summary[:confidence_score]).to eq(plan.confidence_score)
      expect(summary[:auto_executable]).to eq(plan.auto_executable)
    end
  end

  describe "#detailed_plan" do
    let(:plan) { create(:supply_chain_remediation_plan, :with_vulnerabilities, :with_upgrades, account: account, sbom: sbom) }

    it "returns expected keys" do
      detailed = plan.detailed_plan

      expect(detailed).to include(
        :summary,
        :sbom,
        :target_vulnerabilities,
        :upgrade_recommendations,
        :breaking_changes,
        :execution_summary
      )
    end

    it "includes summary data" do
      detailed = plan.detailed_plan
      expect(detailed[:summary]).to eq(plan.summary)
    end

    it "includes sbom summary" do
      detailed = plan.detailed_plan
      expect(detailed[:sbom]).to eq(sbom.summary)
    end

    it "includes target_vulnerabilities" do
      detailed = plan.detailed_plan
      expect(detailed[:target_vulnerabilities]).to eq(plan.target_vulnerabilities)
    end

    it "includes upgrade_recommendations" do
      detailed = plan.detailed_plan
      expect(detailed[:upgrade_recommendations]).to eq(plan.upgrade_recommendations)
    end

    it "includes breaking_changes" do
      detailed = plan.detailed_plan
      expect(detailed[:breaking_changes]).to eq(plan.breaking_changes)
    end

    it "includes execution_summary" do
      detailed = plan.detailed_plan
      expect(detailed[:execution_summary]).to eq(plan.summary)
    end
  end

  describe "JSONB sanitization" do
    describe "before_save callback" do
      it "initializes target_vulnerabilities as empty array when nil" do
        plan = create(:supply_chain_remediation_plan, account: account, sbom: sbom, target_vulnerabilities: nil)
        plan.reload
        expect(plan.target_vulnerabilities).to eq([])
      end

      it "initializes upgrade_recommendations as empty array when nil" do
        plan = create(:supply_chain_remediation_plan, account: account, sbom: sbom, upgrade_recommendations: nil)
        plan.reload
        expect(plan.upgrade_recommendations).to eq([])
      end

      it "initializes breaking_changes as empty array when nil" do
        plan = create(:supply_chain_remediation_plan, account: account, sbom: sbom, breaking_changes: nil)
        plan.reload
        expect(plan.breaking_changes).to eq([])
      end

      it "initializes metadata as empty hash when nil" do
        plan = create(:supply_chain_remediation_plan, account: account, sbom: sbom, metadata: nil)
        plan.reload
        expect(plan.metadata).to eq({})
      end

      it "preserves existing target_vulnerabilities" do
        vulns = [ { "id" => "CVE-2024-1234" } ]
        plan = create(:supply_chain_remediation_plan, account: account, sbom: sbom, target_vulnerabilities: vulns)
        plan.reload
        expect(plan.target_vulnerabilities).to eq(vulns)
      end

      it "preserves existing upgrade_recommendations" do
        upgrades = [ { "package" => "lodash" } ]
        plan = create(:supply_chain_remediation_plan, account: account, sbom: sbom, upgrade_recommendations: upgrades)
        plan.reload
        expect(plan.upgrade_recommendations).to eq(upgrades)
      end

      it "preserves existing breaking_changes" do
        breaking = [ { "package" => "axios" } ]
        plan = create(:supply_chain_remediation_plan, account: account, sbom: sbom, breaking_changes: breaking)
        plan.reload
        expect(plan.breaking_changes).to eq(breaking)
      end

      it "preserves existing metadata" do
        meta = { "key" => "value" }
        plan = create(:supply_chain_remediation_plan, account: account, sbom: sbom, metadata: meta)
        plan.reload
        expect(plan.metadata).to eq(meta)
      end
    end
  end
end
