# frozen_string_literal: true

require "rails_helper"

# Canonical/shadow rule: a GLOBAL canonical agent (account_id nil) is a
# read-only template, and only account rows run. A promotion grant, and an
# agent's request for one, names an account-scoped agent, never a canonical.
RSpec.describe "Promotion grants name account agents only" do
  let(:account) { create(:account) }
  let(:ops) { account.environments.find_by!(slug: "ops") }
  let(:granter) { create(:user, account: account) }
  let(:canonical) { create(:ai_agent, :global, name: "Platform Engineer") }
  let(:shadow) { create(:ai_agent, account: account, name: "Platform Engineer") }

  describe Ai::PromotionGrant do
    it "refuses a global canonical agent by name" do
      grant = build(:ai_promotion_grant, account: account, granted_by: granter, agent: canonical, environment: ops)
      expect(grant).not_to be_valid
      expect(grant.errors[:agent].join).to include("global canonical")
    end

    it "accepts the account's own row" do
      expect(build(:ai_promotion_grant, account: account, granted_by: granter, agent: shadow, environment: ops)).to be_valid
    end
  end

  describe Ai::PromotionGrantRequest do
    def build_request(agent)
      Ai::PromotionGrantRequest.new(account: account, agent: agent, environment: ops, action_category: "release.promote",
                                    lifetime_seconds: 3600, reason: "ship")
    end

    it "refuses a global canonical agent by name" do
      grant_request = build_request(canonical)
      expect(grant_request).not_to be_valid
      expect(grant_request.errors[:agent].join).to include("global canonical")
    end

    it "accepts the account's own row" do
      expect(build_request(shadow)).to be_valid
    end
  end

  it "the request service refuses a canonical caller, naming the account row to use" do
    expect do
      Ai::PromotionGrants::Requests.request!(account: account, agent: canonical,
                                             terms: { environment: "ops", expires_in_hours: 1, reason: "x", bind: "none" })
    end.to raise_error(Ai::PromotionGrants::Requests::Refused, /global canonical/)
    expect(Ai::PromotionGrantRequest.count).to eq(0)
  end

  it "the request verb refuses a canonical caller before anything parks" do
    tool = Ai::Tools::AgentAutonomyTool.new(account: account, agent: canonical, call_origin: Ai::Tools::CallOrigin::MCP_OAUTH)
    result = tool.execute(params: { action: "request_promotion_grant", environment: "ops", expires_in_hours: 1,
                                    reason: "x", bind: "none" }.with_indifferent_access)
    expect(result[:success]).to be(false)
    expect(Ai::PromotionGrantRequest.count).to eq(0)
  end
end
