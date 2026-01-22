# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::LicenseViolation, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:sbom) { create(:supply_chain_sbom, account: account) }
  let(:sbom_component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
  let(:license_policy) { create(:supply_chain_license_policy, account: account) }
  let(:license) { create(:supply_chain_license) }
  let(:user) { create(:user, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:sbom).class_name("SupplyChain::Sbom") }
    it { is_expected.to belong_to(:sbom_component).class_name("SupplyChain::SbomComponent") }
    it { is_expected.to belong_to(:license_policy).class_name("SupplyChain::LicensePolicy") }
    it { is_expected.to belong_to(:license).class_name("SupplyChain::License").optional }
    it { is_expected.to belong_to(:exception_approved_by).class_name("User").optional }
  end

  describe "validations" do
    subject do
      build(:supply_chain_license_violation,
            account: account,
            sbom: sbom,
            sbom_component: sbom_component,
            license_policy: license_policy)
    end

    it { is_expected.to validate_presence_of(:violation_type) }
    it { is_expected.to validate_inclusion_of(:violation_type).in_array(SupplyChain::LicenseViolation::VIOLATION_TYPES) }
    # Note: presence validation is effectively handled by before_validation callback + inclusion validation
    it { is_expected.to validate_inclusion_of(:severity).in_array(SupplyChain::LicenseViolation::SEVERITIES) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(SupplyChain::LicenseViolation::STATUSES) }

    it "allows nil exception_status" do
      violation = build(:supply_chain_license_violation,
                        account: account,
                        sbom: sbom,
                        sbom_component: sbom_component,
                        license_policy: license_policy,
                        exception_status: nil)
      expect(violation).to be_valid
    end

    it "validates exception_status inclusion when present" do
      expect(subject).to validate_inclusion_of(:exception_status)
        .in_array(SupplyChain::LicenseViolation::EXCEPTION_STATUSES)
        .allow_nil
    end
  end

  describe "scopes" do
    let!(:denied_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, violation_type: "denied", severity: "critical")
    end
    let!(:copyleft_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, violation_type: "copyleft", severity: "high")
    end
    let!(:incompatible_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, violation_type: "incompatible", severity: "medium")
    end
    let!(:unknown_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, violation_type: "unknown", severity: "low")
    end
    let!(:open_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, status: "open")
    end
    let!(:reviewing_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, status: "reviewing")
    end
    let!(:resolved_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, status: "resolved")
    end
    let!(:exception_granted_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, status: "exception_granted")
    end
    let!(:wont_fix_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, status: "wont_fix")
    end
    let!(:critical_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, severity: "critical")
    end
    let!(:high_violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, severity: "high")
    end
    let!(:with_exception) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, exception_requested: true, exception_status: "pending")
    end

    describe ".by_type" do
      it "filters violations by type" do
        expect(described_class.by_type("denied")).to include(denied_violation)
        expect(described_class.by_type("denied")).not_to include(copyleft_violation)
      end
    end

    describe ".by_severity" do
      it "filters violations by severity" do
        expect(described_class.by_severity("critical")).to include(denied_violation, critical_violation)
        expect(described_class.by_severity("critical")).not_to include(copyleft_violation)
      end
    end

    describe ".by_status" do
      it "filters violations by status" do
        expect(described_class.by_status("open")).to include(open_violation)
        expect(described_class.by_status("open")).not_to include(resolved_violation)
      end
    end

    describe ".open" do
      it "returns only open violations" do
        expect(described_class.open).to include(open_violation)
        expect(described_class.open).not_to include(reviewing_violation, resolved_violation)
      end
    end

    describe ".reviewing" do
      it "returns only reviewing violations" do
        expect(described_class.reviewing).to include(reviewing_violation)
        expect(described_class.reviewing).not_to include(open_violation, resolved_violation)
      end
    end

    describe ".resolved" do
      it "returns only resolved violations" do
        expect(described_class.resolved).to include(resolved_violation)
        expect(described_class.resolved).not_to include(open_violation, reviewing_violation)
      end
    end

    describe ".exception_granted" do
      it "returns only exception_granted violations" do
        expect(described_class.exception_granted).to include(exception_granted_violation)
        expect(described_class.exception_granted).not_to include(open_violation)
      end
    end

    describe ".actionable" do
      it "returns open and reviewing violations" do
        expect(described_class.actionable).to include(open_violation, reviewing_violation)
        expect(described_class.actionable).not_to include(resolved_violation, exception_granted_violation, wont_fix_violation)
      end
    end

    describe ".critical" do
      it "returns only critical severity violations" do
        expect(described_class.critical).to include(denied_violation, critical_violation)
        expect(described_class.critical).not_to include(copyleft_violation)
      end
    end

    describe ".high" do
      it "returns only high severity violations" do
        expect(described_class.high).to include(copyleft_violation, high_violation)
        expect(described_class.high).not_to include(denied_violation)
      end
    end

    describe ".with_exception_requested" do
      it "returns violations with exception requested" do
        expect(described_class.with_exception_requested).to include(with_exception)
        expect(described_class.with_exception_requested).not_to include(open_violation)
      end
    end

    describe ".pending_exception" do
      it "returns violations with pending exception status" do
        expect(described_class.pending_exception).to include(with_exception)
        expect(described_class.pending_exception).not_to include(open_violation)
      end
    end

    describe ".recent" do
      it "orders by created_at desc" do
        ordered = described_class.recent
        expect(ordered.first.created_at).to be >= ordered.last.created_at
      end
    end

    describe ".ordered_by_severity" do
      it "orders by severity with critical first" do
        ordered = described_class.ordered_by_severity.pluck(:severity)
        critical_index = ordered.index("critical") || Float::INFINITY
        high_index = ordered.index("high") || Float::INFINITY
        medium_index = ordered.index("medium") || Float::INFINITY
        low_index = ordered.index("low") || Float::INFINITY

        expect(critical_index).to be <= high_index
        expect(high_index).to be <= medium_index
        expect(medium_index).to be <= low_index
      end
    end
  end

  describe "status predicates" do
    describe "#open?" do
      it "returns true when status is open" do
        violation = build(:supply_chain_license_violation, status: "open")
        expect(violation.open?).to be true
      end

      it "returns false when status is not open" do
        violation = build(:supply_chain_license_violation, status: "resolved")
        expect(violation.open?).to be false
      end
    end

    describe "#reviewing?" do
      it "returns true when status is reviewing" do
        violation = build(:supply_chain_license_violation, status: "reviewing")
        expect(violation.reviewing?).to be true
      end

      it "returns false when status is not reviewing" do
        violation = build(:supply_chain_license_violation, status: "open")
        expect(violation.reviewing?).to be false
      end
    end

    describe "#resolved?" do
      it "returns true when status is resolved" do
        violation = build(:supply_chain_license_violation, status: "resolved")
        expect(violation.resolved?).to be true
      end

      it "returns false when status is not resolved" do
        violation = build(:supply_chain_license_violation, status: "open")
        expect(violation.resolved?).to be false
      end
    end

    describe "#exception_granted?" do
      it "returns true when status is exception_granted" do
        violation = build(:supply_chain_license_violation, status: "exception_granted")
        expect(violation.exception_granted?).to be true
      end

      it "returns false when status is not exception_granted" do
        violation = build(:supply_chain_license_violation, status: "open")
        expect(violation.exception_granted?).to be false
      end
    end

    describe "#wont_fix?" do
      it "returns true when status is wont_fix" do
        violation = build(:supply_chain_license_violation, status: "wont_fix")
        expect(violation.wont_fix?).to be true
      end

      it "returns false when status is not wont_fix" do
        violation = build(:supply_chain_license_violation, status: "open")
        expect(violation.wont_fix?).to be false
      end
    end

    describe "#actionable?" do
      it "returns true when status is open" do
        violation = build(:supply_chain_license_violation, status: "open")
        expect(violation.actionable?).to be true
      end

      it "returns true when status is reviewing" do
        violation = build(:supply_chain_license_violation, status: "reviewing")
        expect(violation.actionable?).to be true
      end

      it "returns false when status is resolved" do
        violation = build(:supply_chain_license_violation, status: "resolved")
        expect(violation.actionable?).to be false
      end

      it "returns false when status is exception_granted" do
        violation = build(:supply_chain_license_violation, status: "exception_granted")
        expect(violation.actionable?).to be false
      end
    end
  end

  describe "violation type predicates" do
    describe "#denied?" do
      it "returns true when violation_type is denied" do
        violation = build(:supply_chain_license_violation, violation_type: "denied")
        expect(violation.denied?).to be true
      end

      it "returns false when violation_type is not denied" do
        violation = build(:supply_chain_license_violation, violation_type: "copyleft")
        expect(violation.denied?).to be false
      end
    end

    describe "#copyleft?" do
      it "returns true when violation_type is copyleft" do
        violation = build(:supply_chain_license_violation, violation_type: "copyleft")
        expect(violation.copyleft?).to be true
      end

      it "returns false when violation_type is not copyleft" do
        violation = build(:supply_chain_license_violation, violation_type: "denied")
        expect(violation.copyleft?).to be false
      end
    end

    describe "#incompatible?" do
      it "returns true when violation_type is incompatible" do
        violation = build(:supply_chain_license_violation, violation_type: "incompatible")
        expect(violation.incompatible?).to be true
      end

      it "returns false when violation_type is not incompatible" do
        violation = build(:supply_chain_license_violation, violation_type: "denied")
        expect(violation.incompatible?).to be false
      end
    end

    describe "#unknown?" do
      it "returns true when violation_type is unknown" do
        violation = build(:supply_chain_license_violation, violation_type: "unknown")
        expect(violation.unknown?).to be true
      end

      it "returns false when violation_type is not unknown" do
        violation = build(:supply_chain_license_violation, violation_type: "denied")
        expect(violation.unknown?).to be false
      end
    end
  end

  describe "#has_ai_remediation?" do
    it "returns true when ai_remediation has content" do
      violation = build(:supply_chain_license_violation, ai_remediation: { suggestions: [ "Replace with MIT license" ] })
      expect(violation.has_ai_remediation?).to be true
    end

    it "returns false when ai_remediation is empty hash" do
      violation = build(:supply_chain_license_violation, ai_remediation: {})
      expect(violation.has_ai_remediation?).to be false
    end

    it "returns false when ai_remediation is nil" do
      violation = build(:supply_chain_license_violation, ai_remediation: nil)
      expect(violation.has_ai_remediation?).to be false
    end
  end

  describe "exception predicates" do
    describe "#exception_pending?" do
      it "returns true when exception is requested and status is pending" do
        violation = build(:supply_chain_license_violation, exception_requested: true, exception_status: "pending")
        expect(violation.exception_pending?).to be true
      end

      it "returns false when exception is not requested" do
        violation = build(:supply_chain_license_violation, exception_requested: false, exception_status: "pending")
        expect(violation.exception_pending?).to be false
      end

      it "returns false when status is not pending" do
        violation = build(:supply_chain_license_violation, exception_requested: true, exception_status: "approved")
        expect(violation.exception_pending?).to be false
      end
    end

    describe "#exception_approved?" do
      it "returns true when exception_status is approved" do
        violation = build(:supply_chain_license_violation, exception_status: "approved")
        expect(violation.exception_approved?).to be true
      end

      it "returns false when exception_status is not approved" do
        violation = build(:supply_chain_license_violation, exception_status: "pending")
        expect(violation.exception_approved?).to be false
      end
    end

    describe "#exception_expired?" do
      it "returns true when exception_expires_at is in the past" do
        violation = build(:supply_chain_license_violation, exception_expires_at: 1.day.ago)
        expect(violation.exception_expired?).to be true
      end

      it "returns false when exception_expires_at is in the future" do
        violation = build(:supply_chain_license_violation, exception_expires_at: 1.day.from_now)
        expect(violation.exception_expired?).to be false
      end

      it "returns false when exception_expires_at is nil" do
        violation = build(:supply_chain_license_violation, exception_expires_at: nil)
        expect(violation.exception_expired?).to be false
      end
    end
  end

  describe "status transition methods" do
    describe "#start_review!" do
      it "changes status to reviewing" do
        violation = create(:supply_chain_license_violation,
                           account: account, sbom: sbom, sbom_component: sbom_component,
                           license_policy: license_policy, status: "open")
        violation.start_review!

        expect(violation.status).to eq("reviewing")
      end
    end

    describe "#resolve!" do
      let(:violation) do
        create(:supply_chain_license_violation,
               account: account, sbom: sbom, sbom_component: sbom_component,
               license_policy: license_policy, status: "reviewing")
      end

      it "changes status to resolved" do
        violation.resolve!("Fixed by upgrading component")
        expect(violation.status).to eq("resolved")
      end

      it "stores resolution reason in metadata" do
        violation.resolve!("Fixed by upgrading component")
        expect(violation.metadata["resolution_reason"]).to eq("Fixed by upgrading component")
      end

      it "works without a reason" do
        violation.resolve!
        expect(violation.status).to eq("resolved")
        expect(violation.metadata["resolution_reason"]).to be_nil
      end
    end

    describe "#wont_fix!" do
      let(:violation) do
        create(:supply_chain_license_violation,
               account: account, sbom: sbom, sbom_component: sbom_component,
               license_policy: license_policy, status: "reviewing")
      end

      it "changes status to wont_fix" do
        violation.wont_fix!("Not applicable to our use case")
        expect(violation.status).to eq("wont_fix")
      end

      it "stores wont_fix reason in metadata" do
        violation.wont_fix!("Not applicable to our use case")
        expect(violation.metadata["wont_fix_reason"]).to eq("Not applicable to our use case")
      end

      it "works without a reason" do
        violation.wont_fix!
        expect(violation.status).to eq("wont_fix")
        expect(violation.metadata["wont_fix_reason"]).to be_nil
      end
    end
  end

  describe "exception workflow" do
    describe "#request_exception!" do
      let(:violation) do
        create(:supply_chain_license_violation,
               account: account, sbom: sbom, sbom_component: sbom_component,
               license_policy: license_policy, status: "open")
      end

      it "sets exception_requested to true" do
        violation.request_exception!("Required for legacy system compatibility")
        expect(violation.exception_requested).to be true
      end

      it "sets exception_status to pending" do
        violation.request_exception!("Required for legacy system compatibility")
        expect(violation.exception_status).to eq("pending")
      end

      it "stores exception reason" do
        violation.request_exception!("Required for legacy system compatibility")
        expect(violation.exception_reason).to eq("Required for legacy system compatibility")
      end
    end

    describe "#approve_exception!" do
      let(:violation) do
        create(:supply_chain_license_violation,
               account: account, sbom: sbom, sbom_component: sbom_component,
               license_policy: license_policy, status: "open",
               exception_requested: true, exception_status: "pending")
      end

      it "changes status to exception_granted" do
        violation.approve_exception!(user)
        expect(violation.status).to eq("exception_granted")
      end

      it "sets exception_status to approved" do
        violation.approve_exception!(user)
        expect(violation.exception_status).to eq("approved")
      end

      it "records who approved the exception" do
        violation.approve_exception!(user)
        expect(violation.exception_approved_by).to eq(user)
      end

      it "records when the exception was approved" do
        freeze_time do
          violation.approve_exception!(user)
          expect(violation.exception_approved_at).to eq(Time.current)
        end
      end

      it "sets expiration date when provided" do
        expiration_date = 90.days.from_now
        violation.approve_exception!(user, expires_at: expiration_date)
        expect(violation.exception_expires_at).to be_within(1.second).of(expiration_date)
      end

      it "does not set expiration date when not provided" do
        violation.approve_exception!(user)
        expect(violation.exception_expires_at).to be_nil
      end
    end

    describe "#reject_exception!" do
      let(:violation) do
        create(:supply_chain_license_violation,
               account: account, sbom: sbom, sbom_component: sbom_component,
               license_policy: license_policy, status: "open",
               exception_requested: true, exception_status: "pending")
      end

      it "sets exception_status to rejected" do
        violation.reject_exception!(user, "Policy violation too severe")
        expect(violation.exception_status).to eq("rejected")
      end

      it "records who rejected the exception" do
        violation.reject_exception!(user, "Policy violation too severe")
        expect(violation.exception_approved_by).to eq(user)
      end

      it "records when the exception was rejected" do
        freeze_time do
          violation.reject_exception!(user, "Policy violation too severe")
          expect(violation.exception_approved_at).to eq(Time.current)
        end
      end

      it "stores rejection reason in metadata" do
        violation.reject_exception!(user, "Policy violation too severe")
        expect(violation.metadata["rejection_reason"]).to eq("Policy violation too severe")
      end

      it "works without a reason" do
        violation.reject_exception!(user)
        expect(violation.exception_status).to eq("rejected")
        expect(violation.metadata["rejection_reason"]).to be_nil
      end
    end
  end

  describe "helper methods" do
    let(:violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, license: license)
    end

    describe "#component_name" do
      it "returns the component full name" do
        allow(sbom_component).to receive(:full_name).and_return("@example/package")
        expect(violation.component_name).to eq("@example/package")
      end
    end

    describe "#component_version" do
      it "returns the component version" do
        expect(violation.component_version).to eq(sbom_component.version)
      end
    end

    describe "#license_name" do
      it "returns license name when license is present" do
        expect(violation.license_name).to eq(license.name)
      end

      it "returns component license name when license is nil" do
        violation.license = nil
        allow(sbom_component).to receive(:license_name).and_return("Apache-2.0")
        expect(violation.license_name).to eq("Apache-2.0")
      end

      it "returns 'Unknown' when both license and component license are nil" do
        violation.license = nil
        allow(sbom_component).to receive(:license_name).and_return(nil)
        expect(violation.license_name).to eq("Unknown")
      end
    end

    describe "#license_spdx_id" do
      it "returns license spdx_id when license is present" do
        expect(violation.license_spdx_id).to eq(license.spdx_id)
      end

      it "returns component license_spdx_id when license is nil" do
        violation.license = nil
        allow(sbom_component).to receive(:license_spdx_id).and_return("MIT")
        expect(violation.license_spdx_id).to eq("MIT")
      end
    end

    describe "#policy_name" do
      it "returns the license policy name" do
        expect(violation.policy_name).to eq(license_policy.name)
      end
    end
  end

  describe "#summary" do
    let(:violation) do
      create(:supply_chain_license_violation,
             account: account, sbom: sbom, sbom_component: sbom_component,
             license_policy: license_policy, license: license,
             exception_requested: true, exception_status: "pending")
    end

    it "returns expected structure" do
      summary = violation.summary

      expect(summary).to include(
        :id,
        :violation_type,
        :severity,
        :status,
        :component,
        :license,
        :policy,
        :exception_requested,
        :exception_status,
        :has_ai_remediation,
        :created_at
      )
    end

    it "includes component details" do
      summary = violation.summary

      expect(summary[:component]).to include(
        :id,
        :name,
        :version
      )
      expect(summary[:component][:id]).to eq(sbom_component.id)
    end

    it "includes license details" do
      summary = violation.summary

      expect(summary[:license]).to include(
        :spdx_id,
        :name
      )
    end

    it "includes policy details" do
      summary = violation.summary

      expect(summary[:policy]).to include(
        :id,
        :name
      )
      expect(summary[:policy][:id]).to eq(license_policy.id)
    end

    it "includes exception information" do
      summary = violation.summary

      expect(summary[:exception_requested]).to be true
      expect(summary[:exception_status]).to eq("pending")
    end

    it "includes ai_remediation flag" do
      summary = violation.summary

      expect(summary[:has_ai_remediation]).to be false
    end
  end

  describe "callbacks" do
    describe "#sanitize_jsonb_fields" do
      it "initializes ai_remediation as empty hash when nil" do
        violation = create(:supply_chain_license_violation,
                           account: account, sbom: sbom, sbom_component: sbom_component,
                           license_policy: license_policy, ai_remediation: nil)
        expect(violation.ai_remediation).to eq({})
      end

      it "initializes metadata as empty hash when nil" do
        violation = create(:supply_chain_license_violation,
                           account: account, sbom: sbom, sbom_component: sbom_component,
                           license_policy: license_policy, metadata: nil)
        expect(violation.metadata).to eq({})
      end

      it "preserves existing ai_remediation content" do
        remediation = { "suggestions" => [ "Use alternative license" ] }
        violation = create(:supply_chain_license_violation,
                           account: account, sbom: sbom, sbom_component: sbom_component,
                           license_policy: license_policy, ai_remediation: remediation)
        expect(violation.ai_remediation).to eq(remediation)
      end

      it "preserves existing metadata content" do
        metadata = { "custom_field" => "value" }
        violation = create(:supply_chain_license_violation,
                           account: account, sbom: sbom, sbom_component: sbom_component,
                           license_policy: license_policy, metadata: metadata)
        expect(violation.metadata).to eq(metadata)
      end
    end

    describe "#set_severity_from_type" do
      it "sets severity to high for denied violation" do
        violation = build(:supply_chain_license_violation, violation_type: "denied", severity: nil)
        violation.save!
        expect(violation.severity).to eq("high")
      end

      it "sets severity to high for copyleft violation" do
        violation = build(:supply_chain_license_violation, violation_type: "copyleft", severity: nil)
        violation.save!
        expect(violation.severity).to eq("high")
      end

      it "sets severity to medium for incompatible violation" do
        violation = build(:supply_chain_license_violation, violation_type: "incompatible", severity: nil)
        violation.save!
        expect(violation.severity).to eq("medium")
      end

      it "sets severity to medium for unknown violation" do
        violation = build(:supply_chain_license_violation, violation_type: "unknown", severity: nil)
        violation.save!
        expect(violation.severity).to eq("medium")
      end

      it "sets severity to low for expired violation" do
        violation = build(:supply_chain_license_violation, violation_type: "expired", severity: nil)
        violation.save!
        expect(violation.severity).to eq("low")
      end

      it "does not override manually set severity when violation_type does not change" do
        violation = create(:supply_chain_license_violation,
                           account: account, sbom: sbom, sbom_component: sbom_component,
                           license_policy: license_policy, violation_type: "denied", severity: "critical")
        violation.update!(description: "Updated description")
        expect(violation.severity).to eq("critical")
      end

      it "updates severity when violation_type changes" do
        violation = create(:supply_chain_license_violation,
                           account: account, sbom: sbom, sbom_component: sbom_component,
                           license_policy: license_policy, violation_type: "denied", severity: "critical")
        violation.update!(violation_type: "expired")
        expect(violation.severity).to eq("low")
      end
    end
  end
end
