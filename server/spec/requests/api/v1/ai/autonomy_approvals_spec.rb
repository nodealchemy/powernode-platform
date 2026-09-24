# frozen_string_literal: true

require "rails_helper"

# fc-12 review: the autonomy approvals REST door (Ai::AutonomyApprovalActions)
# is now the sole approval-request read/decide surface — the governance
# door's equivalent endpoints (which carried this coverage) were deleted.
# This file restores the baseline security coverage that deletion took with
# it: unauthenticated, unknown id, cross-account isolation, the
# ai.autonomy.approve gate, and the approver on a recorded decision.
RSpec.describe "Api::V1::Ai::Autonomy approvals — baseline request-door coverage", type: :request do
  let(:account) { create(:account) }
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:approver) { create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.approve]) }
  let!(:approval_request) { create(:ai_approval_request, account: account, status: "pending") }

  describe "authentication" do
    it "is required on the list, show, approve and reject actions" do
      get "/api/v1/ai/autonomy/approvals", as: :json
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", as: :json
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/approve", as: :json
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/reject", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "an unknown id" do
    let(:unknown_id) { SecureRandom.uuid }

    it "returns 404 on show, approve and reject" do
      get "/api/v1/ai/autonomy/approvals/#{unknown_id}", headers: auth_headers_for(approver), as: :json
      expect_error_response("Approval request not found", 404)

      post "/api/v1/ai/autonomy/approvals/#{unknown_id}/approve", headers: auth_headers_for(approver), as: :json
      expect_error_response("Approval request not found", 404)

      post "/api/v1/ai/autonomy/approvals/#{unknown_id}/reject", headers: auth_headers_for(approver), as: :json
      expect_error_response("Approval request not found", 404)
    end
  end

  describe "cross-account isolation" do
    let(:other_account) { create(:account) }
    let!(:other_request) { create(:ai_approval_request, account: other_account, status: "pending") }

    it "returns 404 on show, approve and reject, and records no decision" do
      get "/api/v1/ai/autonomy/approvals/#{other_request.id}", headers: auth_headers_for(approver), as: :json
      expect_error_response("Approval request not found", 404)

      post "/api/v1/ai/autonomy/approvals/#{other_request.id}/approve", headers: auth_headers_for(approver),
                                                                        as: :json
      expect_error_response("Approval request not found", 404)

      post "/api/v1/ai/autonomy/approvals/#{other_request.id}/reject", headers: auth_headers_for(approver),
                                                                       as: :json
      expect_error_response("Approval request not found", 404)

      expect(other_request.reload.status).to eq("pending")
      expect(other_request.decisions.count).to eq(0)
    end
  end

  describe "the ai.autonomy.approve gate" do
    it "forbids approve and reject for a user who only holds ai.agents.read" do
      post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/approve", headers: auth_headers_for(reader),
                                                                           as: :json
      expect(response).to have_http_status(:forbidden)
      expect(approval_request.reload.status).to eq("pending")

      post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/reject", headers: auth_headers_for(reader),
                                                                          as: :json
      expect(response).to have_http_status(:forbidden)
      expect(approval_request.reload.status).to eq("pending")
      expect(approval_request.decisions.count).to eq(0)
    end
  end

  describe "GET /api/v1/ai/autonomy/approvals/:id — decisions" do
    it "includes the approver on each recorded decision" do
      post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/approve", headers: auth_headers_for(approver),
                                                                           as: :json
      expect(response).to have_http_status(:ok)

      get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", headers: auth_headers_for(approver), as: :json

      decisions = json_response_data["decisions"]
      expect(decisions.size).to eq(1)
      expect(decisions.first["decision"]).to eq("approved")
      expect(decisions.first["approver_id"]).to eq(approver.id)
    end
  end
end
