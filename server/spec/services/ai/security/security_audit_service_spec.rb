# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Security::SecurityAuditService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  describe "#log!" do
    it "creates a security audit trail entry" do
      expect {
        service.log!(action: "test_action", outcome: "allowed", severity: "info")
      }.to change(Ai::SecurityAuditTrail, :count).by(1)
    end

    it "creates entry with all provided attributes" do
      trail = service.log!(
        action: "identity_check",
        outcome: "denied",
        asi_reference: "ASI03",
        agent: agent,
        severity: "warning",
        context: { reason: "expired_key" }
      )

      expect(trail.action).to eq("identity_check")
      expect(trail.outcome).to eq("denied")
      expect(trail.asi_reference).to eq("ASI03")
      expect(trail.agent_id).to eq(agent.id)
      expect(trail.severity).to eq("warning")
    end
  end

  describe "#compliance_matrix" do
    before do
      # Create some audit trails across different ASI references
      create(:ai_security_audit_trail, account: account, asi_reference: "ASI01", outcome: "allowed")
      create(:ai_security_audit_trail, account: account, asi_reference: "ASI01", outcome: "denied")
      create(:ai_security_audit_trail, account: account, asi_reference: "ASI03", outcome: "allowed")
      create(:ai_security_audit_trail, account: account, asi_reference: "ASI05", outcome: "blocked")
    end

    it "returns 10 items (one per ASI reference)" do
      matrix = service.compliance_matrix
      expect(matrix.length).to eq(10)
    end

    it "includes coverage score and status for each reference" do
      matrix = service.compliance_matrix
      matrix.each do |item|
        expect(item).to have_key(:asi_reference)
        expect(item).to have_key(:name)
        expect(item).to have_key(:coverage_score)
        expect(item).to have_key(:status)
        expect(item).to have_key(:total_events)
      end
    end

    it "shows positive coverage for references with events" do
      matrix = service.compliance_matrix
      asi01 = matrix.find { |m| m[:asi_reference] == "ASI01" }
      expect(asi01[:total_events]).to eq(2)
      expect(asi01[:coverage_score]).to be > 0
    end

    it "shows zero coverage for references with no events" do
      matrix = service.compliance_matrix
      asi09 = matrix.find { |m| m[:asi_reference] == "ASI09" }
      expect(asi09[:total_events]).to eq(0)
      expect(asi09[:coverage_score]).to eq(0.0)
      expect(asi09[:status]).to eq("no_coverage")
    end
  end

  describe "#risk_score" do
    context "with no security history" do
      it "returns a low risk score" do
        result = service.risk_score(agent: agent)

        expect(result[:composite_score]).to eq(0.0)
        expect(result[:risk_level]).to eq("low")
        expect(result[:factors]).to include(:anomaly, :violations, :quarantine, :communication)
      end
    end

    context "with significant security history" do
      before do
        # Create denial history
        5.times do
          create(:ai_security_audit_trail, :denied,
            account: account, agent_id: agent.id)
        end

        # Create quarantine records
        2.times do
          create(:ai_quarantine_record,
            account: account, agent_id: agent.id)
        end
      end

      it "returns an elevated risk score" do
        result = service.risk_score(agent: agent)
        expect(result[:composite_score]).to be > 0
        expect(result[:factors][:violations]).to be > 0
        expect(result[:factors][:quarantine]).to be > 0
      end
    end
  end

  describe "#recent_events" do
    before do
      create(:ai_security_audit_trail, account: account, agent_id: agent.id, outcome: "allowed", action: "test1")
      create(:ai_security_audit_trail, :denied, account: account, agent_id: agent.id, action: "test2")
      create(:ai_security_audit_trail, account: account, outcome: "allowed", action: "other")
    end

    it "returns all events for the account" do
      events = service.recent_events
      expect(events.count).to eq(3)
    end

    it "filters by agent_id" do
      events = service.recent_events(filters: { agent_id: agent.id })
      expect(events.count).to eq(2)
    end

    it "filters by outcome" do
      events = service.recent_events(filters: { outcome: "denied" })
      expect(events.count).to eq(1)
    end

    it "filters by severity" do
      events = service.recent_events(filters: { severity: "warning" })
      expect(events.count).to eq(1)
    end
  end

  describe "#security_report" do
    before do
      create_list(:ai_security_audit_trail, 5, account: account, outcome: "allowed")
      create_list(:ai_security_audit_trail, 2, :denied, account: account)
      create(:ai_quarantine_record, account: account, agent_id: agent.id)
    end

    it "returns a comprehensive report" do
      report = service.security_report

      expect(report[:account_id]).to eq(account.id)
      expect(report[:total_events]).to eq(7)
      expect(report[:by_outcome]).to include("allowed" => 5, "denied" => 2)
      expect(report[:active_quarantines]).to eq(1)
      expect(report[:recommendations]).to be_an(Array)
      expect(report[:average_compliance_coverage]).to be_a(Float)
    end

    it "accepts custom period" do
      report = service.security_report(period: 7.days)
      expect(report[:period_days]).to eq(7)
    end

    it "includes top risk agents" do
      agent2 = create(:ai_agent, account: account, provider: provider)
      3.times { create(:ai_security_audit_trail, :denied, account: account, agent_id: agent2.id) }

      report = service.security_report
      expect(report[:top_risk_agents]).to be_an(Array)
    end
  end
end
