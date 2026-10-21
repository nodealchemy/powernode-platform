# frozen_string_literal: true

require "rails_helper"

# The REST door for promotion grants: the ONLY door that issues one. Issuing
# needs ai.promotion_grants.manage, the permission the gated verb itself
# requires (the extension's catalog answers which), and a person's own session.
RSpec.describe "Api::V1::Ai::PromotionGrants", type: :request do
  let(:account) { create(:account) }
  # Stands in for the promote verb's own permission; the system extension's
  # catalog answers system.modules.update in a full install.
  let(:verb_permission) { "ai.agents.update" }
  let(:granter) { user_with_permissions("ai.promotion_grants.manage", verb_permission, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:ops) { account.environments.find_by!(slug: "ops") }
  let(:module_id) { SecureRandom.uuid }

  before do
    allow(Ai::PromotionGrants::Catalog).to receive(:required_permission).and_call_original
    allow(Ai::PromotionGrants::Catalog).to receive(:required_permission).with("release.promote")
                                                                        .and_return(verb_permission)
    allow(Ai::PromotionGrants::Catalog).to receive(:unknown_subject_ids).and_return([])
  end

  def headers_for(user)
    auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  def impersonation_headers_for(user)
    admin = create(:user, :admin, account: account)
    session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: user)
    payload = { type: "impersonation", session_id: session.id, sub: user.id, account_id: user.account_id,
                version: Security::JwtService::CURRENT_TOKEN_VERSION }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  def body(**over)
    { ai_agent_id: agent.id, environment_id: ops.id, action_category: "release.promote",
      module_ids: [ module_id ], max_uses: 3, expires_in_hours: 4, reason: "release train" }.merge(over)
  end

  describe "POST /api/v1/ai/promotion_grants" do
    it "issues a grant from a person's own session and audits it" do
      post "/api/v1/ai/promotion_grants", params: body.to_json, headers: headers_for(granter)

      expect(response).to have_http_status(:created)
      data = json_response["data"]["promotion_grant"]
      grant = Ai::PromotionGrant.find(data["id"])
      expect(grant.granted_by).to eq(granter)
      expect(grant.agent).to eq(agent)
      expect(grant.environment).to eq(ops)
      expect(grant.module_ids).to eq([ module_id ])
      expect(grant.max_uses).to eq(3)
      expect(grant.expires_at).to be_within(1.minute).of(4.hours.from_now)
      expect(data).to include("status" => "active", "uses_count" => 0, "environment" => include("slug" => "ops"))

      audit = AuditLog.where(account_id: account.id, action: "ai.promotion_grant.created").sole
      expect(audit.resource_id).to eq(grant.id)
      expect(audit.user_id).to eq(granter.id)
    end

    it "refuses an impersonation session and writes nothing" do
      post "/api/v1/ai/promotion_grants", params: body.to_json, headers: impersonation_headers_for(granter)

      expect(response).to have_http_status(:forbidden)
      expect(json_response["error"]).to include("own session")
      expect(Ai::PromotionGrant.count).to eq(0)
    end

    it "refuses a granter without ai.promotion_grants.manage" do
      user = user_with_permissions(verb_permission, account: account)
      post "/api/v1/ai/promotion_grants", params: body.to_json, headers: headers_for(user)

      expect(response).to have_http_status(:forbidden)
      expect(Ai::PromotionGrant.count).to eq(0)
    end

    it "refuses a granter who does not hold the verb's own permission" do
      user = user_with_permissions("ai.promotion_grants.manage", account: account)
      post "/api/v1/ai/promotion_grants", params: body.to_json, headers: headers_for(user)

      expect(response).to have_http_status(:forbidden)
      expect(json_response["error"]).to include(verb_permission)
      expect(Ai::PromotionGrant.count).to eq(0)
    end

    it "refuses when no extension declares the category (core mode)" do
      allow(Ai::PromotionGrants::Catalog).to receive(:required_permission).with("release.promote").and_return(nil)
      post "/api/v1/ai/promotion_grants", params: body.to_json, headers: headers_for(granter)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Ai::PromotionGrant.count).to eq(0)
    end

    it "refuses a lifetime over 24 hours" do
      post "/api/v1/ai/promotion_grants", params: body(expires_in_hours: 25).to_json, headers: headers_for(granter)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("24 hours")
      expect(Ai::PromotionGrant.count).to eq(0)
    end

    it "refuses another account's agent" do
      foreign = create(:ai_agent, account: create(:account))
      post "/api/v1/ai/promotion_grants", params: body(ai_agent_id: foreign.id).to_json, headers: headers_for(granter)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Ai::PromotionGrant.count).to eq(0)
    end

    it "refuses a module the catalog does not know in this account" do
      allow(Ai::PromotionGrants::Catalog).to receive(:unknown_subject_ids).and_return([ module_id ])
      post "/api/v1/ai/promotion_grants", params: body.to_json, headers: headers_for(granter)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include(module_id)
    end
  end

  describe "POST /api/v1/ai/promotion_grants/:id/revoke" do
    let!(:grant) { create(:ai_promotion_grant, account: account, granted_by: granter, agent: agent, environment: ops) }

    it "revokes and audits" do
      post "/api/v1/ai/promotion_grants/#{grant.id}/revoke", headers: headers_for(granter)

      expect(response).to have_http_status(:ok)
      expect(grant.reload).to be_revoked
      expect(grant.revoked_by).to eq(granter)
      expect(json_response["data"]["promotion_grant"]["status"]).to eq("revoked")
      expect(AuditLog.where(account_id: account.id, action: "ai.promotion_grant.revoked").count).to eq(1)
    end

    it "is allowed from any REST session (revoking only tightens)" do
      post "/api/v1/ai/promotion_grants/#{grant.id}/revoke", headers: impersonation_headers_for(granter)
      expect(response).to have_http_status(:ok)
      expect(grant.reload).to be_revoked
    end

    it "refuses a second revoke" do
      grant.revoke!(by: granter)
      post "/api/v1/ai/promotion_grants/#{grant.id}/revoke", headers: headers_for(granter)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "cannot reach another account's grant" do
      other = create(:ai_promotion_grant)
      post "/api/v1/ai/promotion_grants/#{other.id}/revoke", headers: headers_for(granter)
      expect(response).to have_http_status(:not_found)
      expect(other.reload).not_to be_revoked
    end
  end

  describe "GET /api/v1/ai/promotion_grants" do
    let!(:grant) { create(:ai_promotion_grant, account: account, granted_by: granter, agent: agent, environment: ops) }

    it "lists the account's grants with who granted, uses and time left" do
      create(:ai_promotion_grant) # another account's

      get "/api/v1/ai/promotion_grants", headers: headers_for(granter)

      expect(response).to have_http_status(:ok)
      rows = json_response["data"]["promotion_grants"]
      expect(rows.map { |r| r["id"] }).to eq([ grant.id ])
      expect(rows.first).to include(
        "granted_by" => include("id" => granter.id), "agent" => include("id" => agent.id),
        "uses_count" => 0, "status" => "active"
      )
      expect(rows.first["seconds_remaining"]).to be > 0
    end

    it "shows a grant's uses: the operations that ran under it" do
      op = Ai::DeferredOperation.create!(account: account, action_category: "release.promote",
                                         executor_class: "X", params: {}, promotion_grant: grant, status: "completed")
      get "/api/v1/ai/promotion_grants/#{grant.id}", headers: headers_for(granter)

      expect(response).to have_http_status(:ok)
      expect(json_response["data"]["promotion_grant"]["uses"].map { |u| u["deferred_operation_id"] }).to eq([ op.id ])
    end

    it "needs a promotion-grant permission" do
      get "/api/v1/ai/promotion_grants", headers: headers_for(user_with_permissions("ai.agents.read", account: account))
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/ai/promotion_grants/options" do
    it "offers the environments with their protection, and the catalog's modules" do
      allow(Ai::PromotionGrants::Catalog).to receive(:subjects).and_return([ { id: module_id, name: "hub-backend" } ])

      get "/api/v1/ai/promotion_grants/options", headers: headers_for(granter)

      expect(response).to have_http_status(:ok)
      data = json_response["data"]
      expect(data["environments"].map { |e| e["slug"] }).to include("ops", "prod")
      expect(data["environments"].find { |e| e["slug"] == "prod" }).to include("is_protected" => true)
      expect(data["modules"]).to eq([ { "id" => module_id, "name" => "hub-backend" } ])
      expect(data["max_lifetime_hours"]).to eq(24)
      expect(data["categories"]).to eq([ "release.promote" ])
    end
  end
end
