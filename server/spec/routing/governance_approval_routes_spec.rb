# frozen_string_literal: true

require "rails_helper"

# fc-12 — the governance approval-request and approval-chain endpoints were
# deleted: their frontend callers were removed by fc-11, and the canonical
# decision surface is the autonomy door (Ai::AutonomyApprovalActions,
# /api/v1/ai/autonomy/approvals). The canonical approval-chain CRUD is
# /api/v1/ai/approval_chains, unaffected by this deletion.
RSpec.describe "Deleted governance approval routes", type: :routing do
  it "does not route the governance approval_requests endpoints" do
    expect(get: "/api/v1/ai/governance/approval_requests").not_to be_routable
    expect(get: "/api/v1/ai/governance/approval_requests/pending").not_to be_routable
    expect(get: "/api/v1/ai/governance/approval_requests/abc").not_to be_routable
    expect(post: "/api/v1/ai/governance/approval_requests/abc/decide").not_to be_routable
  end

  it "does not route the governance approval_chains endpoints" do
    expect(get: "/api/v1/ai/governance/approval_chains").not_to be_routable
    expect(post: "/api/v1/ai/governance/approval_chains").not_to be_routable
  end

  it "still routes the canonical approval_chains resource and the autonomy decide door" do
    expect(get: "/api/v1/ai/approval_chains").to route_to("api/v1/ai/approval_chains#index")
    expect(post: "/api/v1/ai/autonomy/approvals/abc/approve")
      .to route_to("api/v1/ai/autonomy#approve_action", id: "abc")
    expect(post: "/api/v1/ai/autonomy/approvals/abc/reject")
      .to route_to("api/v1/ai/autonomy#reject_action", id: "abc")
  end

  it "still routes the surviving governance endpoints (only approvals were removed)" do
    expect(get: "/api/v1/ai/governance/policies").to route_to("api/v1/ai/governance#policies")
    expect(get: "/api/v1/ai/governance/violations").to route_to("api/v1/ai/governance#violations")
  end
end
