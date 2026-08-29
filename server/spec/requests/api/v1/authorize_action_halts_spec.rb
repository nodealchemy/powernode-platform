# frozen_string_literal: true

require "rails_helper"

# S1 regression cover: a permission guard must HALT, not merely render.
#
# Twelve controllers defined a private `authorize_action!` that called
# render_forbidden / render_error from the action body with no `raise` and no
# `return` on the caller. Rails does not halt an action on a render, so the
# guard produced a clean 403 AND the mutation still ran; the resulting
# DoubleRenderError was swallowed by ApiResponse's
# `rescue_from StandardError ... unless performed?`.
#
# These examples assert THE ACTUATOR IS NEVER INVOKED. Asserting only
# `response.status == 403` passes against the defect and is not valid evidence —
# every pre-existing spec for these endpoints did exactly that and stayed green
# while the writes landed.
RSpec.describe "authorize_action! halts before the actuator", type: :request do
  let(:account) { create(:account) }
  let(:unauthorized_user) { create(:user, account: account, permissions: [ "integrations.read" ]) }
  let(:headers) { auth_headers_for(unauthorized_user) }
  let(:instance) { create(:devops_integration_instance, account: account) }

  describe "DELETE /api/v1/integrations/instances/:id without integrations.delete" do
    it "returns 403 AND never calls the uninstall service" do
      expect(::Devops::RegistryService).not_to receive(:uninstall_instance)

      delete "/api/v1/integrations/instances/#{instance.id}", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/integrations/instances/:id/activate without integrations.update" do
    it "returns 403 AND never calls the activate service" do
      expect(::Devops::RegistryService).not_to receive(:activate_instance)

      post "/api/v1/integrations/instances/#{instance.id}/activate", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/integrations/instances without integrations.create" do
    it "returns 403 AND never calls the install service" do
      expect(::Devops::RegistryService).not_to receive(:install_template)

      post "/api/v1/integrations/instances",
           params: { instance: { name: "zz-fixture" } }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  # Same defect, different METHOD NAME. The sweep above was keyed on the name
  # `authorize_action!`, so these two guards — identical in shape, called bare at
  # the top of an action body and never registered as a before_action — were not
  # touched by it. The assertion here is THE ROW, not the status: both endpoints
  # answered 403 before the fix and answer 403 after it.
  describe "review-comment guards that render without halting" do
    let(:reviewer) { create(:user, account: account, permissions: [ "ai.teams.manage" ]) }
    let(:reviewer_headers) { auth_headers_for(reviewer) }
    let(:team) { create(:ai_agent_team, account: account) }
    let(:team_execution) { create(:ai_team_execution, account: account, agent_team: team) }
    let(:team_task) { create(:ai_team_task, team_execution: team_execution) }
    let(:review) { create(:ai_task_review, account: account, team_task: team_task) }
    let(:comment_payload) do
      { comment: { file_path: "app/zz.rb", content: "zz-unauthorized", comment_type: "suggestion", severity: "warning" } }
    end

    it "POST comments without ai.code_reviews.manage creates NO comment row" do
      expect {
        post "/api/v1/ai/teams/reviews/#{review.id}/comments",
             params: comment_payload, headers: reviewer_headers, as: :json
      }.not_to change { ::Ai::CodeReviewComment.count }

      expect(response).to have_http_status(:forbidden)
      # Pins the controller's `authorize_action!` override, whose ONLY job is to
      # keep the body bare render_forbidden used to produce. Without this, the
      # override could be deleted and every spec would stay green.
      expect(json_response["error"]).to eq("Access denied")
    end

    it "PATCH a comment without ai.code_reviews.manage leaves the row untouched" do
      comment = create(:ai_code_review_comment, task_review: review, account: account, content: "original")

      expect {
        patch "/api/v1/ai/teams/reviews/#{review.id}/comments/#{comment.id}",
              params: { comment: { content: "zz-unauthorized-edit" } },
              headers: reviewer_headers, as: :json
      }.not_to change { comment.reload.content }

      expect(response).to have_http_status(:forbidden)
      expect(json_response["error"]).to eq("Access denied")
    end
  end
end
