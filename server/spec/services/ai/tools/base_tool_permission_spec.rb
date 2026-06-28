# frozen_string_literal: true

require "rails_helper"

# BaseTool.permitted? must use the canonical permission resolution so an agent can see a
# tool whose required permission its account holds via a CODE-DEFINED role (e.g.
# ai.campaigns.*), not only via a DB RolePermission row. (gap-audit follow-up: campaign_*
# tools were invisible to the concierge because the old raw-RolePermission query missed
# code-defined grants.)
RSpec.describe Ai::Tools::BaseTool, ".permitted?" do
  it "grants the tool when an account user holds the required permission" do
    account = create(:account)
    create(:user, account: account, permissions: ["ai.campaigns.manage"])
    agent = create(:ai_agent, account: account)
    expect(Ai::Tools::CampaignTool.permitted?(agent: agent)).to be true
  end

  it "denies the tool when no account user holds the required permission" do
    account = create(:account)
    create(:user, account: account, permissions: ["ai.goals.read"])
    agent = create(:ai_agent, account: account)
    expect(Ai::Tools::CampaignTool.permitted?(agent: agent)).to be false
  end

  it "is permissive with no agent" do
    expect(Ai::Tools::CampaignTool.permitted?(agent: nil)).to be true
  end
end
