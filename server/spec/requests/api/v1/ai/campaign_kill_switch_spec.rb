# frozen_string_literal: true

require "rails_helper"

# Kill-switch (gap-audit #7): REST campaign write paths that arm autonomous loops must
# refuse while the account's AI is suspended.
RSpec.describe "Campaign control-plane kill-switch (REST)", type: :request do
  let(:user) { user_with_permissions("ai.campaigns.read", "ai.campaigns.manage") }
  let(:account) { user.account }
  let(:headers) { auth_headers_for(user) }

  before { account.update!(ai_suspended: true) }

  it "409s on POST /campaigns (create) while AI is suspended" do
    post "/api/v1/ai/campaigns", headers: headers, params: { name: "Nope" }, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it "409s on POST /campaigns/:id/delegate while AI is suspended" do
    account.update!(ai_suspended: false)
    campaign = ::Ai::DevLoop::CampaignDriver.new(account: account, user: user).start(name: "C")[:campaign]
    account.update!(ai_suspended: true)
    post "/api/v1/ai/campaigns/#{campaign.id}/delegate", headers: headers,
         params: { driver_kind: "claude_code" }, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it "409s on POST /campaign_proposals/:id/spawn while AI is suspended" do
    account.update!(ai_suspended: false)
    proposal = create(:ai_campaign_proposal, :approved, account: account)
    account.update!(ai_suspended: true)
    post "/api/v1/ai/campaign_proposals/#{proposal.id}/spawn", headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end
end
