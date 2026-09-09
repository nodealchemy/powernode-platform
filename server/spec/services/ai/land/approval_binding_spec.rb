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

  # IMP-01a081f2 — #create_governance_request called
  # `Ai::ApprovalChain.find_or_create_default_for`, a method that is defined
  # NOWHERE in the tree. The resulting NoMethodError was caught by the method's
  # own `rescue StandardError`, logged at warn, and swallowed into nil, so with
  # a governance extension present NO ApprovalRequest was ever minted: the land
  # fell through to the proposal card and the formal chain — the thing that
  # makes land.on_approval_decision fire — silently did not exist.
  #
  # SELF-SEALING, which is why it survived: the rescue that hid the error is in
  # the same method as the error, the fallback path looks like a working
  # feature, and the only signal was one warn line on a code path core-mode
  # installs never take.
  #
  # THE ORACLE IS THE PERSISTED REQUEST ROW, never "did not raise" — the old
  # code did not raise either. Nor is it the log line: asserting the warn would
  # have passed against the broken code.
  describe "the formal approval chain (governance present)" do
    before { allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(true) }

    it "mints an ApprovalRequest bound to the land" do
      c = campaign("supervised")

      land = described_class.request_land_approval(campaign: c, description: "land it")

      request = Ai::ApprovalRequest.find_by(source_type: "Ai::CampaignLand", source_id: land.id)
      expect(request).to be_present
      expect(request.status).to eq("pending")
      expect(request.description).to eq("land it")
    end

    it "leaves the land pending_approval, waiting on that request" do
      land = described_class.request_land_approval(campaign: campaign("supervised"))

      expect(land.reload.status).to eq("pending_approval")
    end

    # The source-keyed chain distinction the class documents ("missions and
    # campaigns route through distinct default chains") was unreachable — the
    # kind was computed and handed to a method that did not exist. Missions
    # auto-approve, so the campaign side is where the kind is observable.
    it "routes the campaign land through a campaign_land chain" do
      land = described_class.request_land_approval(campaign: campaign("supervised"))

      chain = Ai::ApprovalRequest.find_by(source_type: "Ai::CampaignLand", source_id: land.id).approval_chain
      expect(chain.name).to include("campaign_land")
    end

    it "mints nothing for an autonomous campaign, which auto-enqueues instead" do
      land = described_class.request_land_approval(campaign: campaign("autonomous"))

      expect(land.status).to eq("queued")
      expect(Ai::ApprovalRequest.where(source_type: "Ai::CampaignLand", source_id: land.id)).to be_empty
    end
  end

  # Core mode (no governance extension) must keep its existing behaviour: no
  # chain, no request, land parked for the proposal card. Pinned because the
  # repair routes through Ai::Approvals::Gateway, whose #request! answers
  # :proceed rather than :pending in core mode — read as "go ahead" that would
  # have auto-enqueued a land that needs a human.
  describe "core mode (no governance extension)" do
    before { allow(Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(false) }

    it "parks the land for the proposal card without minting a request" do
      land = described_class.request_land_approval(campaign: campaign("supervised"))

      expect(land.reload.status).to eq("pending_approval")
      expect(Ai::ApprovalRequest.where(source_type: "Ai::CampaignLand", source_id: land.id)).to be_empty
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

  describe "scope guardrail on the land path (G10)" do
    before { Ai::Land::SecurityScannerRegistry.reset! }
    after { Ai::Land::SecurityScannerRegistry.reset! }

    # Record a changed-files set on the source's loop iteration (the dev-loop pull
    # path stores paths in check_results["files_changed"]).
    def record_changed_files(campaign, files)
      loop_rec = create(:ai_ralph_loop, account: account, campaign: campaign)
      create(:ai_ralph_iteration, ralph_loop: loop_rec, iteration_number: 1,
             check_results: { "files_changed" => files })
    end

    it "parks an autonomous land touching a protected path even with NO secret finding" do
      c = campaign("autonomous")
      record_changed_files(c, ["app/services/payments/charge_service.rb"])

      land = described_class.request_land_approval(campaign: c)

      expect(land.status).to eq("parked")              # NOT "queued"
      expect(land.queued_at).to be_nil
      expect(land.parked_reason).to match(/scope guardrail blocked/)
      expect(land.metadata.dig("scope_guardrail", "blocked")).to be(true)
      expect(land.metadata.dig("scope_guardrail", "violations").first["file"])
        .to eq("app/services/payments/charge_service.rb")
      # The block came from scope, not a secret finding.
      expect(land.metadata["security_gate"]).to be_nil
    end

    it "lets a clean autonomous land auto-queue (no protected paths touched)" do
      c = campaign("autonomous")
      record_changed_files(c, ["app/models/widget.rb"])

      land = described_class.request_land_approval(campaign: c)

      expect(land.status).to eq("queued")
      expect(land.metadata["scope_guardrail"]).to be_nil
    end

    it "queues an autonomous land when the source recorded no changed paths" do
      c = campaign("autonomous")
      land = described_class.request_land_approval(campaign: c)

      expect(land.status).to eq("queued")
      expect(land.metadata["scope_guardrail"]).to be_nil
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
