# frozen_string_literal: true

require "rails_helper"

# Separation of duty at the door: the same approver's second decision on a step
# is a 422, and so is the race that slipped past the check, which the unique
# index stops. Never a 500.
RSpec.describe "POST /api/v1/ai/autonomy/approvals/:id/approve — one decision per approver per step", type: :request do
  let(:account) { create(:account) }
  let(:perm) { "system.infra_tasks.control" }
  let!(:approver) { create(:user, account: account, permissions: [ "ai.agents.read", "ai.autonomy.approve", perm ]) }
  let!(:request_row) do
    Ai::ApprovalChain.create!(
      account: account, name: "chain-#{SecureRandom.hex(4)}",
      trigger_type: "autonomy_action", status: "active",
      is_sequential: true, timeout_hours: 4, timeout_action: "reject",
      steps: [ { "name" => "Two keys", "approvers" => [ { "type" => "permission", "value" => perm } ],
                 "required_approvals" => 2 } ]
    ).create_request!(source_type: "X", source_id: SecureRandom.uuid, description: "d")
  end
  let(:path) { "/api/v1/ai/autonomy/approvals/#{request_row.id}/approve" }

  def approve!
    post path, headers: auth_headers_for(approver), as: :json
  end

  it "answers the same approver's second approval with 422" do
    approve!
    expect(response).to have_http_status(:ok)

    approve!
    expect(response).to have_http_status(:unprocessable_content)
    expect(request_row.decisions.count).to eq(1)
  end

  it "answers a same-approver race that got past the check with the same 422, not a 500" do
    approve!
    expect(response).to have_http_status(:ok)
    allow_any_instance_of(Ai::ApprovalRequest).to receive(:decided_current_step?).and_return(false)

    approve!
    expect(response).to have_http_status(:unprocessable_content)
    expect(request_row.decisions.count).to eq(1)
    expect(request_row.reload.step_statuses[0]["current_approvals"]).to eq(1)
  end

  context "through the governance decide door" do
    let!(:approver) do
      create(:user, account: account, permissions: [ "ai.governance.read", "ai.governance.manage", perm ])
    end
    let(:decide_path) { "/api/v1/ai/governance/approval_requests/#{request_row.id}/decide" }

    def decide!
      post decide_path, params: { decision: "approved" }, headers: auth_headers_for(approver), as: :json
    end

    it "answers the same approver's second decision with 422" do
      decide!
      expect(response).to have_http_status(:ok)

      decide!
      expect(response).to have_http_status(:unprocessable_content)
      expect(request_row.decisions.count).to eq(1)
      expect(request_row.reload.status).to eq("pending")
    end

    it "answers a same-approver race that got past the check with 422, not a 500" do
      decide!
      expect(response).to have_http_status(:ok)
      allow_any_instance_of(Ai::ApprovalRequest).to receive(:decided_current_step?).and_return(false)

      decide!
      expect(response).to have_http_status(:unprocessable_content)
      expect(request_row.decisions.count).to eq(1)
    end
  end
end
