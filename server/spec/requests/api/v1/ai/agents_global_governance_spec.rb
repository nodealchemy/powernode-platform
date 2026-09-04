# frozen_string_literal: true

require "rails_helper"

# Governance for GLOBAL (platform-managed, canonical) agents:
#   - read-only to consumers (must clone to customize) — D6
#   - clone-to-customize + rebase reuse the existing GloballyScopedContent infra — D7
#   - changes to a global agent are audited over time — D5
RSpec.describe "Api::V1::Ai::Agents global governance", type: :request do
  let(:account)  { create(:account, name: "Powernode Admin") }
  let(:provider) { create(:ai_provider, :openai, account: account) }
  let(:user) do
    create(:user, account: account,
                  permissions: %w[ai.agents.read ai.agents.create ai.agents.update ai.agents.delete ai.agents.execute])
  end
  let(:headers) { auth_headers_for(user) }

  let!(:global_agent) do
    create(:ai_agent, account: nil, name: "Fleet Autonomy", slug: "fleet-autonomy",
                      agent_type: "monitor", source_key: "fleet-autonomy", is_system: true,
                      creator: user, provider: provider)
  end

  describe "read-only guard (D6)" do
    it "rejects PATCH on a global agent with a clone-to-customize message" do
      patch "/api/v1/ai/agents/#{global_agent.id}",
            params: { agent: { description: "hacked" } }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.to_s).to match(/read-only|clone it to customize/i)
      expect(global_agent.reload.description).not_to eq("hacked")
    end

    it "rejects DELETE on a global agent" do
      delete "/api/v1/ai/agents/#{global_agent.id}", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Ai::Agent.exists?(global_agent.id)).to be true
    end
  end

  describe "clone-to-customize (D6/D7)" do
    it "clones a global agent into the account as a provenance-tracked editable copy" do
      expect {
        post "/api/v1/ai/agents/#{global_agent.id}/clone", headers: headers, as: :json
      }.to change { Ai::Agent.owned_by_account(account.id).count }.by(1)

      expect(response).to have_http_status(:created)
      copy = Ai::Agent.owned_by_account(account.id).order(:created_at).last
      expect(copy.cloned_from_id).to eq(global_agent.id)
      expect(copy.global?).to be false
    end

    # IMP-6cda93db7f31: a canonical seeded before any provider existed carries
    # none (ai_provider_id is nullable on a GLOBAL row), while an ACCOUNT row
    # must have one. The clone therefore cannot simply inherit the canonical's
    # — this door resolves the account's own provider exactly as
    # Ai::Agents::AccountPrincipalResolver and AgentManagementTool#clone_canonical_agent do.
    context "when the canonical carries no provider" do
      before { global_agent.update_columns(ai_provider_id: nil, creator_id: nil) }

      it "clones onto the account's own active provider" do
        provider # the account has one

        post "/api/v1/ai/agents/#{global_agent.id}/clone", headers: headers, as: :json

        expect(response).to have_http_status(:created)
        copy = Ai::Agent.owned_by_account(account.id).order(:created_at).last
        expect(copy.ai_provider_id).to eq(provider.id)
        expect(copy.creator_id).to eq(user.id)
      end

      it "explains the cause instead of a bare validation failure when the account has none either" do
        Ai::Provider.where(account_id: account.id).update_all(is_active: false)

        expect {
          post "/api/v1/ai/agents/#{global_agent.id}/clone", headers: headers, as: :json
        }.not_to change { Ai::Agent.owned_by_account(account.id).count }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.to_s).to match(/provider/i)
      end
    end

    it "lets the account edit its own clone (not read-only)" do
      copy = global_agent.clone_to_account(account, creator: user)
      patch "/api/v1/ai/agents/#{copy.id}",
            params: { agent: { description: "my customization" } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(copy.reload.description).to eq("my customization")
    end
  end

  describe "visibility (D6)" do
    it "lists global agents alongside the account's own, and ?scope=custom excludes them" do
      get "/api/v1/ai/agents", headers: headers
      ids = json_response_data["items"].map { |a| a["id"] }
      expect(ids).to include(global_agent.id)

      get "/api/v1/ai/agents", params: { scope: "custom" }, headers: headers
      ids = json_response_data["items"].map { |a| a["id"] }
      expect(ids).not_to include(global_agent.id)
    end
  end

  describe "audit of global-agent changes over time (D5)" do
    it "records an AuditLog entry when a global agent actually changes" do
      expect {
        global_agent.update!(description: "maintainer update via seed")
      }.to change {
        AuditLog.where(resource_type: "Ai::Agent", resource_id: global_agent.id, action: "ai.agents.update").count
      }.by(1)

      entry = AuditLog.where(resource_type: "Ai::Agent", resource_id: global_agent.id).order(:created_at).last
      expect(entry.source).to eq("system")
      expect(entry.metadata["global_agent"]).to be true
      expect(entry.metadata["changed_fields"]).to include("description")
    end

    it "does not log an idempotent no-op save" do
      expect {
        global_agent.update!(description: global_agent.description)
      }.not_to change { AuditLog.where(resource_type: "Ai::Agent", resource_id: global_agent.id).count }
    end
  end
end
