# frozen_string_literal: true

require "rails_helper"

# IMP-03134d9452d2 — the REST half of secreview §21 G4 (option 1).
#
# Which parked requests only a person may decide in their own session is read
# from intervention-policy rows (Ai::Approvals::HumanSessionPolicy#account_mark).
# The tool doors that write those rows are human-only; this REST door stayed
# direct "for a person", but it never asked whether the session IS that person.
# An impersonation or account-switch session could therefore lift the mark.
#
# The rule: a write that could lift the mark (touching a row that carries
# requires_human_session, or writing it false) needs a person's own session.
# Adding the mark to a row that has none only tightens, so any session may.
RSpec.describe "Intervention-policy REST writes of the person-session mark", type: :request do
  let(:account) { create(:account) }
  let!(:operator) { user_with_permissions("ai.intervention_policies.manage", account: account) }
  let(:mark) { Ai::Approvals::HumanSessionPolicy::CONDITION_KEY }

  def own_headers
    auth_headers_for(operator).merge("Content-Type" => "application/json")
  end

  def impersonation_headers
    admin = create(:user, :admin, account: account)
    session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: operator)
    payload = { type: "impersonation", session_id: session.id, sub: operator.id, account_id: operator.account_id,
                version: Security::JwtService::CURRENT_TOKEN_VERSION }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  def marked_row!
    Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: "*",
                                   policy: "require_approval", priority: 1, conditions: { mark => true })
  end

  def unmark_body
    { scope: "global", action_category: "*", policy: "require_approval", priority: 100,
      conditions: { mark => false } }
  end

  describe "from an impersonation session" do
    it "refuses creating a row that unmarks, and writes nothing" do
      post "/api/v1/ai/intervention_policies", params: unmark_body.to_json, headers: impersonation_headers

      expect(response).to have_http_status(:forbidden)
      expect(json_response["error"]).to include("own session")
      expect(account.ai_intervention_policies.count).to eq(0)
    end

    it "refuses changing or deleting a marked row, leaving it marked and active" do
      row = marked_row!

      patch "/api/v1/ai/intervention_policies/#{row.id}", params: { is_active: false }.to_json,
                                                          headers: impersonation_headers
      expect(response).to have_http_status(:forbidden)

      delete "/api/v1/ai/intervention_policies/#{row.id}", headers: impersonation_headers
      expect(response).to have_http_status(:forbidden)

      row.reload
      expect(row.is_active).to be(true)
      expect(row.conditions).to eq(mark => true)
    end

    it "still writes a row that carries no mark, and one that adds the mark" do
      post "/api/v1/ai/intervention_policies",
           params: { scope: "global", action_category: "spec.plain", policy: "notify_and_proceed", priority: 1 }.to_json,
           headers: impersonation_headers
      expect(response).to have_http_status(:created)

      post "/api/v1/ai/intervention_policies",
           params: { scope: "global", action_category: "spec.tighten", policy: "require_approval", priority: 1,
                     conditions: { mark => true } }.to_json,
           headers: impersonation_headers
      expect(response).to have_http_status(:created)
      expect(account.ai_intervention_policies.count).to eq(2)
    end
  end

  describe "from the person's own session" do
    it "creates an unmarking row, and changes and deletes a marked one" do
      post "/api/v1/ai/intervention_policies", params: unmark_body.to_json, headers: own_headers
      expect(response).to have_http_status(:created)

      row = marked_row!
      patch "/api/v1/ai/intervention_policies/#{row.id}", params: { is_active: false }.to_json, headers: own_headers
      expect(response).to have_http_status(:ok)
      expect(row.reload.is_active).to be(false)

      delete "/api/v1/ai/intervention_policies/#{row.id}", headers: own_headers
      expect(response).to have_http_status(:ok)
      expect(Ai::InterventionPolicy.exists?(row.id)).to be(false)
    end
  end
end
