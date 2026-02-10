# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Security::QuarantineService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe "#quarantine!" do
    it "creates a quarantine record with correct severity" do
      record = service.quarantine!(agent: agent, severity: "medium", reason: "Suspicious activity")

      expect(record).to be_persisted
      expect(record.severity).to eq("medium")
      expect(record.status).to eq("active")
      expect(record.trigger_reason).to eq("Suspicious activity")
      expect(record.agent_id).to eq(agent.id)
    end

    it "captures forensic snapshot" do
      record = service.quarantine!(agent: agent, severity: "low", reason: "Test")

      expect(record.forensic_snapshot).to be_present
      expect(record.forensic_snapshot["agent_id"]).to eq(agent.id)
      expect(record.forensic_snapshot["captured_at"]).to be_present
    end

    it "captures previous capabilities" do
      record = service.quarantine!(agent: agent, severity: "low", reason: "Test")

      expect(record.previous_capabilities).to be_present
      expect(record.previous_capabilities).to have_key("status")
    end

    it "sets cooldown based on severity" do
      low = service.quarantine!(agent: agent, severity: "low", reason: "Low")
      expect(low.cooldown_minutes).to eq(30)

      agent2 = create(:ai_agent, account: account, provider: provider)
      high = service.quarantine!(agent: agent2, severity: "high", reason: "High")
      expect(high.cooldown_minutes).to eq(240)
    end

    it "does not set scheduled_restore_at for critical severity" do
      record = service.quarantine!(agent: agent, severity: "critical", reason: "Critical issue")
      expect(record.scheduled_restore_at).to be_nil
    end

    it "sets scheduled_restore_at for non-critical severity" do
      record = service.quarantine!(agent: agent, severity: "medium", reason: "Medium issue")
      expect(record.scheduled_restore_at).to be_present
      expect(record.scheduled_restore_at).to be > Time.current
    end

    it "creates an audit trail entry" do
      expect {
        service.quarantine!(agent: agent, severity: "medium", reason: "Test")
      }.to change(Ai::SecurityAuditTrail, :count).by_at_least(1)
    end

    it "raises on invalid severity" do
      expect {
        service.quarantine!(agent: agent, severity: "invalid", reason: "Test")
      }.to raise_error(Ai::Security::QuarantineService::QuarantineError)
    end

    it "creates restriction policies for medium+ severities" do
      service.quarantine!(agent: agent, severity: "medium", reason: "Test")

      policy = Ai::AgentPrivilegePolicy.where(account: account, agent_id: agent.id).first
      expect(policy).to be_present
      expect(policy.denied_tools).to be_present
    end

    it "pauses agent for critical severity" do
      service.quarantine!(agent: agent, severity: "critical", reason: "Critical")
      agent.reload
      expect(agent.status).to eq("paused")
    end
  end

  describe "#escalate!" do
    let!(:quarantine_record) do
      service.quarantine!(agent: agent, severity: "low", reason: "Initial issue")
    end

    it "creates a new record with higher severity" do
      new_record = service.escalate!(quarantine_record: quarantine_record, new_severity: "high")

      expect(new_record).to be_persisted
      expect(new_record.severity).to eq("high")
      expect(new_record.escalated_from_id).to eq(quarantine_record.id)

      quarantine_record.reload
      expect(quarantine_record.status).to eq("escalated")
    end

    it "raises when escalating to same or lower severity" do
      expect {
        service.escalate!(quarantine_record: quarantine_record, new_severity: "low")
      }.to raise_error(Ai::Security::QuarantineService::QuarantineError, /Cannot escalate/)
    end
  end

  describe "#restore!" do
    let!(:quarantine_record) do
      service.quarantine!(agent: agent, severity: "medium", reason: "Test quarantine")
    end

    it "restores agent from quarantine" do
      restored = service.restore!(quarantine_record: quarantine_record, approved_by: user)

      expect(restored.status).to eq("restored")
      expect(restored.restored_at).to be_present
      expect(restored.approved_by_id).to eq(user.id)
    end

    it "raises when record is not active" do
      quarantine_record.update!(status: "restored", restored_at: Time.current)

      expect {
        service.restore!(quarantine_record: quarantine_record, approved_by: user)
      }.to raise_error(Ai::Security::QuarantineService::QuarantineError, /non-active/)
    end

    it "deactivates restriction policies" do
      service.restore!(quarantine_record: quarantine_record, approved_by: user)

      policies = Ai::AgentPrivilegePolicy.where(account: account, agent_id: agent.id)
      expect(policies.active.count).to eq(0)
    end
  end

  describe "#emergency_kill!" do
    it "creates a critical quarantine record" do
      record = service.emergency_kill!(agent: agent, reason: "Compromised agent")

      expect(record).to be_persisted
      expect(record.severity).to eq("critical")
      expect(record.trigger_reason).to include("EMERGENCY KILL")
    end

    it "pauses the agent" do
      service.emergency_kill!(agent: agent, reason: "Compromised")
      agent.reload
      expect(agent.status).to eq("paused")
    end
  end

  describe "#auto_restore_expired!" do
    it "restores records past scheduled_restore_at" do
      record = create(:ai_quarantine_record, :restorable,
        account: account,
        agent_id: agent.id)

      restored_ids = service.auto_restore_expired!

      expect(restored_ids).to include(record.id)
      record.reload
      expect(record.status).to eq("restored")
    end

    it "does not restore records that are not yet due" do
      record = create(:ai_quarantine_record,
        account: account,
        agent_id: agent.id,
        status: "active",
        scheduled_restore_at: 1.hour.from_now)

      restored_ids = service.auto_restore_expired!
      expect(restored_ids).not_to include(record.id)
    end
  end

  describe "#restorable_records" do
    it "returns records past their scheduled restore time" do
      restorable = create(:ai_quarantine_record, :restorable,
        account: account, agent_id: agent.id)
      not_yet = create(:ai_quarantine_record,
        account: account, agent_id: agent.id,
        status: "active",
        scheduled_restore_at: 1.hour.from_now)

      records = service.restorable_records
      expect(records).to include(restorable)
      expect(records).not_to include(not_yet)
    end
  end
end
