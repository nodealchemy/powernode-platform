# frozen_string_literal: true

require "rails_helper"

# Wiring + regression: report_issue / escalate forward to the OUTBOUND tracker
# bridge (opt-in) without changing their internal behavior. Heavy internal
# collaborators are stubbed so this exercises the bridge wiring specifically.
RSpec.describe Ai::Tools::AgentAutonomyTool, "external tracker bridge wiring" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:tool) { described_class.new(account: account, agent: agent, user: user) }

  before do
    allow(Ai::AgentObservation).to receive(:create).and_return(double("observation", id: "obs-1"))

    outreach = instance_double(Ai::AgentOutreachService, notify: true, notify_escalation: true)
    allow(Ai::AgentOutreachService).to receive(:new).and_return(outreach)

    escalation = double("escalation", id: "esc-1", title: "Esc", severity: "high", escalated_to_user: nil)
    esc_service = instance_double(Ai::EscalationService, escalate: escalation)
    allow(Ai::EscalationService).to receive(:new).and_return(esc_service)
  end

  describe "#report_issue" do
    it "forwards the issue to the tracker bridge" do
      expect(Ai::Connectors::TrackerBridge).to receive(:forward)
        .with(hash_including(kind: "issue", title: "Disk full", severity: "critical"))
        .and_return(nil)

      result = tool.send(:report_issue, { "title" => "Disk full", "description" => "d", "severity" => "critical" })

      expect(result[:success]).to be(true)
    end

    it "is unchanged (no external_tracker key) when no tracker is configured" do
      allow(Ai::Connectors::TrackerConfig).to receive(:enabled?).and_return(false)

      result = tool.send(:report_issue, { "title" => "x", "description" => "y" })

      expect(result[:success]).to be(true)
      expect(result[:data]).not_to have_key(:external_tracker)
    end

    it "still succeeds even when the bridge raises" do
      allow(Ai::Connectors::TrackerBridge).to receive(:forward).and_raise(StandardError, "boom")

      result = tool.send(:report_issue, { "title" => "x", "description" => "y" })

      expect(result[:success]).to be(true)
    end

    it "includes the external_tracker result when forwarding succeeds" do
      allow(Ai::Connectors::TrackerBridge).to receive(:forward)
        .and_return({ ok: true, external_id: "ISS-7" })

      result = tool.send(:report_issue, { "title" => "x", "description" => "y" })

      expect(result[:data][:external_tracker]).to eq({ ok: true, external_id: "ISS-7" })
    end
  end

  describe "#escalate" do
    it "forwards the escalation to the tracker bridge" do
      expect(Ai::Connectors::TrackerBridge).to receive(:forward)
        .with(hash_including(kind: "escalation", title: "Boom"))
        .and_return(nil)

      result = tool.send(:escalate, { "title" => "Boom", "escalation_type" => "incident", "severity" => "high" })

      expect(result[:success]).to be(true)
    end
  end
end
