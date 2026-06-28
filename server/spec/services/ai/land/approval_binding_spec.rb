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
  end
end
