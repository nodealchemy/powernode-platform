# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::Security::AgentIdentity", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ["ai.security.manage"]) }
  let(:headers) { auth_headers_for(user) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  describe "GET /api/v1/ai/security/identities" do
    before do
      create_list(:ai_agent_identity, 3, account: account)
    end

    it "returns list of identities" do
      get "/api/v1/ai/security/identities", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["items"]).to be_an(Array)
      expect(data["items"].length).to eq(3)
    end

    it "filters by agent_id" do
      identity = create(:ai_agent_identity, account: account, agent_id: agent.id)

      get "/api/v1/ai/security/identities",
          headers: headers,
          params: { agent_id: agent.id }

      expect_success_response
      data = json_response_data
      ids = data["items"].map { |i| i["id"] }
      expect(ids).to include(identity.id)
    end

    it "filters by status" do
      create(:ai_agent_identity, :revoked, account: account)

      get "/api/v1/ai/security/identities",
          headers: headers,
          params: { status: "revoked" }

      expect_success_response
      data = json_response_data
      statuses = data["items"].map { |i| i["status"] }
      expect(statuses.uniq).to eq(["revoked"])
    end

    it "returns 403 without permission" do
      no_perm_user = create(:user, account: account, permissions: [])
      get "/api/v1/ai/security/identities",
          headers: auth_headers_for(no_perm_user),
          as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "includes pagination" do
      get "/api/v1/ai/security/identities", headers: headers, as: :json

      data = json_response_data
      expect(data["pagination"]).to include("current_page", "total_count", "total_pages")
    end
  end

  describe "GET /api/v1/ai/security/identities/:id" do
    let!(:identity) { create(:ai_agent_identity, account: account) }

    it "returns the identity" do
      get "/api/v1/ai/security/identities/#{identity.id}",
          headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["id"]).to eq(identity.id)
      expect(data["key_fingerprint"]).to eq(identity.key_fingerprint)
    end

    it "returns 404 for non-existent identity" do
      get "/api/v1/ai/security/identities/#{SecureRandom.uuid}",
          headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/ai/security/identities" do
    it "provisions a new identity for an agent" do
      post "/api/v1/ai/security/identities",
           headers: headers,
           params: { agent_id: agent.id },
           as: :json

      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data["agent_id"]).to eq(agent.id)
      expect(data["status"]).to eq("active")
      expect(data["algorithm"]).to eq("ed25519")
      expect(data["key_fingerprint"]).to be_present
    end

    it "returns 404 for non-existent agent" do
      post "/api/v1/ai/security/identities",
           headers: headers,
           params: { agent_id: SecureRandom.uuid },
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/ai/security/identities/:id/rotate" do
    let(:identity_service) { Ai::Security::AgentIdentityService.new(account: account) }
    let!(:identity) { identity_service.provision!(agent: agent) }

    it "rotates the identity" do
      post "/api/v1/ai/security/identities/#{identity.id}/rotate",
           headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["status"]).to eq("active")
      expect(data["id"]).not_to eq(identity.id)

      identity.reload
      expect(identity.status).to eq("rotated")
    end
  end

  describe "POST /api/v1/ai/security/identities/:id/revoke" do
    let(:identity_service) { Ai::Security::AgentIdentityService.new(account: account) }
    let!(:identity) { identity_service.provision!(agent: agent) }

    it "revokes the identity" do
      post "/api/v1/ai/security/identities/#{identity.id}/revoke",
           params: { reason: "Security breach" }.to_json,
           headers: headers

      expect_success_response
      data = json_response_data
      expect(data["revoked_count"]).to be >= 1
    end
  end

  describe "POST /api/v1/ai/security/identities/verify" do
    let(:identity_service) { Ai::Security::AgentIdentityService.new(account: account) }
    let!(:identity) { identity_service.provision!(agent: agent) }

    it "verifies a valid signature" do
      payload = "test_payload"
      signature = identity_service.sign(agent: agent, payload: payload)

      post "/api/v1/ai/security/identities/verify",
           headers: headers,
           params: { agent_id: agent.id, payload: payload, signature: signature },
           as: :json

      expect_success_response
      data = json_response_data
      expect(data["valid"]).to be true
    end

    it "rejects an invalid signature" do
      post "/api/v1/ai/security/identities/verify",
           headers: headers,
           params: {
             agent_id: agent.id,
             payload: "test",
             signature: Base64.strict_encode64("invalid")
           },
           as: :json

      expect_success_response
      data = json_response_data
      expect(data["valid"]).to be false
    end
  end
end
