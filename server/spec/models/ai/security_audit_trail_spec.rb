# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SecurityAuditTrail, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { should belong_to(:account) }
  end

  describe "validations" do
    subject { build(:ai_security_audit_trail, account: account) }

    it { should validate_presence_of(:action) }
    it { should validate_presence_of(:outcome) }
    it { should validate_inclusion_of(:outcome).in_array(%w[allowed denied blocked quarantined escalated]) }
    it { should validate_inclusion_of(:severity).in_array(%w[info warning critical]).allow_nil }

    it "validates risk_score range" do
      trail = build(:ai_security_audit_trail, account: account, risk_score: 1.5)
      expect(trail).not_to be_valid
    end

    it "allows nil risk_score" do
      trail = build(:ai_security_audit_trail, account: account, risk_score: nil)
      expect(trail).to be_valid
    end
  end

  describe "scopes" do
    let(:agent_id) { SecureRandom.uuid }
    let!(:allowed_trail) { create(:ai_security_audit_trail, account: account, agent_id: agent_id, outcome: "allowed") }
    let!(:denied_trail) { create(:ai_security_audit_trail, :denied, account: account, agent_id: agent_id) }
    let!(:blocked_trail) { create(:ai_security_audit_trail, :blocked, account: account) }

    it ".for_agent scopes by agent_id" do
      results = described_class.for_agent(agent_id)
      expect(results).to include(allowed_trail, denied_trail)
      expect(results).not_to include(blocked_trail)
    end

    it ".by_outcome filters by outcome" do
      expect(described_class.by_outcome("allowed")).to include(allowed_trail)
      expect(described_class.by_outcome("allowed")).not_to include(denied_trail)
    end

    it ".by_severity filters by severity" do
      expect(described_class.by_severity("warning")).to include(denied_trail)
      expect(described_class.by_severity("critical")).to include(blocked_trail)
    end

    it ".by_asi filters by ASI reference" do
      identity_trail = create(:ai_security_audit_trail, :identity, account: account)
      expect(described_class.by_asi("ASI03")).to include(identity_trail)
      expect(described_class.by_asi("ASI03")).not_to include(allowed_trail)
    end

    it ".denied_or_blocked returns both denied and blocked" do
      expect(described_class.denied_or_blocked).to include(denied_trail, blocked_trail)
      expect(described_class.denied_or_blocked).not_to include(allowed_trail)
    end

    it ".recent returns records within the given duration" do
      old_trail = create(:ai_security_audit_trail, account: account, created_at: 60.days.ago)
      expect(described_class.recent(30.days)).to include(allowed_trail)
      expect(described_class.recent(30.days)).not_to include(old_trail)
    end

    it ".high_risk returns records with risk_score >= 0.7" do
      high_risk = create(:ai_security_audit_trail, :high_risk, account: account)
      low_risk = create(:ai_security_audit_trail, account: account, risk_score: 0.3)
      expect(described_class.high_risk).to include(high_risk)
      expect(described_class.high_risk).not_to include(low_risk)
    end
  end

  describe ".log!" do
    it "creates a new audit trail entry" do
      expect {
        described_class.log!(
          action: "test_action",
          outcome: "allowed",
          account: account,
          asi_reference: "ASI05",
          severity: "info"
        )
      }.to change(described_class, :count).by(1)
    end

    it "returns nil on failure without raising" do
      result = described_class.log!(action: nil, outcome: "allowed", account: account)
      expect(result).to be_nil
    end
  end

  describe "instance methods" do
    it "#allowed? returns true for allowed outcome" do
      trail = build(:ai_security_audit_trail, outcome: "allowed")
      expect(trail.allowed?).to be true
    end

    it "#denied? returns true for denied outcome" do
      trail = build(:ai_security_audit_trail, outcome: "denied")
      expect(trail.denied?).to be true
    end

    it "#high_risk? returns true for high risk scores" do
      trail = build(:ai_security_audit_trail, risk_score: 0.85)
      expect(trail.high_risk?).to be true
    end

    it "#high_risk? returns false for low risk scores" do
      trail = build(:ai_security_audit_trail, risk_score: 0.2)
      expect(trail.high_risk?).to be false
    end
  end
end
