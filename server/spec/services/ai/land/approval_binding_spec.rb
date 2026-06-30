# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Land::ApprovalBinding do
  let(:account) { create(:account) }

  def campaign(authority)
    create(:ai_campaign, account: account, decision_authority: authority)
  end

  describe ".request_land_approval" do
    it "creates a pending_approval land for a trusted campaign (requires approval)" do
      c = campaign("trusted")
      allow(Ai::Land::ApprovalBinding).to receive(:new).and_call_original
      allow_any_instance_of(described_class).to receive(:governance_available?).and_return(false)

      land = described_class.request_land_approval(campaign: c, target_branch: "develop")

      expect(land).to have_attributes(status: "pending_approval", target_branch: "develop")
      expect(land.source_branch).to eq("campaign/#{c.id}")
    end

    it "auto-enqueues for an autonomous campaign" do
      c = campaign("autonomous")
      land = described_class.request_land_approval(campaign: c)
      expect(land.status).to eq("queued")
      expect(land.queued_at).to be_present
    end

    it "defaults to requiring approval when governance is unavailable (supervised)" do
      c = campaign("supervised")
      allow_any_instance_of(described_class).to receive(:governance_available?).and_return(false)
      land = described_class.request_land_approval(campaign: c)
      expect(land.status).to eq("pending_approval")
    end

    it "still populates campaign_id (and the polymorphic source) for a campaign land" do
      c = campaign("autonomous")
      land = described_class.request_land_approval(campaign: c)
      expect(land.campaign_id).to eq(c.id)
      expect(land.source_type).to eq("Ai::Campaign")
      expect(land.source).to eq(c)
    end
  end

  describe "blocking security gate (G4)" do
    before { Ai::Land::SecurityScannerRegistry.reset! }
    after { Ai::Land::SecurityScannerRegistry.reset! }

    it "parks an autonomous land (does NOT auto-merge) when a scanner blocks" do
      Ai::Land::SecurityScannerRegistry.register(:sast) do |_ctx|
        [ { scanner: "sast", severity: "high", detail: "leaked credential" } ]
      end
      c = campaign("autonomous")

      land = described_class.request_land_approval(campaign: c)

      expect(land.status).to eq("parked")            # NOT "queued"
      expect(land.queued_at).to be_nil
      expect(land.parked_reason).to match(/security gate blocked/)
      expect(land.metadata.dig("security_gate", "blocked")).to be(true)
      expect(land.metadata.dig("security_gate", "findings")).to be_present
    end

    it "parks even under autonomous authority on a core secret finding" do
      c = campaign("autonomous")
      allow(Ai::Land::SecurityGateService).to receive(:evaluate).and_return(
        blocked: true, scanned_content: true,
        findings: [ { scanner: "core_secret_scan", severity: "critical", detail: "potential secret detected (token)" } ]
      )

      land = described_class.request_land_approval(campaign: c)
      expect(land.status).to eq("parked")
      expect(land.metadata.dig("security_gate", "findings").first["scanner"]).to eq("core_secret_scan")
    end

    it "lets a clean autonomous land auto-queue (gate passes)" do
      c = campaign("autonomous")
      land = described_class.request_land_approval(campaign: c)
      expect(land.status).to eq("queued")
      expect(land.metadata["security_gate"]).to be_nil
    end

    it "fails closed (parks) when the gate itself errors" do
      c = campaign("autonomous")
      allow(Ai::Land::SecurityGateService).to receive(:evaluate).and_raise(StandardError, "boom")
      land = described_class.request_land_approval(campaign: c)
      expect(land.status).to eq("parked")
    end
  end

  describe ".request_land_approval (mission source)" do
    let(:mission) do
      create(:ai_mission, account: account, branch_name: "mission/feature-x", base_branch: "develop")
    end

    it "auto-approves a mission land (queued), with a nil campaign and the mission branch" do
      land = described_class.request_land_approval(source: mission, target_branch: "develop")

      expect(land.status).to eq("queued")
      expect(land.queued_at).to be_present
      expect(land.campaign_id).to be_nil
      expect(land.source).to eq(mission)
      expect(land.source_type).to eq("Ai::Mission")
      expect(land.source_branch).to eq("mission/feature-x")
    end

    it "honors an explicit source_branch / target_branch" do
      land = described_class.request_land_approval(
        source: mission, source_branch: "mission/explicit", target_branch: "main"
      )
      expect(land.source_branch).to eq("mission/explicit")
      expect(land.target_branch).to eq("main")
    end
  end
end
