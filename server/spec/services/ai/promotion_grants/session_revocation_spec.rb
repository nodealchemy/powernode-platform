# frozen_string_literal: true

require "rails_helper"

# Review MEDIUM-1: a person deliberately revoking an MCP session ends the
# grants bound to it AT ONCE and for good, while a transport drop (the same
# revoke! with no flag) only pauses them for the reconnect grace.
RSpec.describe "Session-bound promotion grants and session revocation" do
  let(:account) { create(:account) }
  let(:operator) { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:agent) { create(:ai_agent, account: account, agent_type: "mcp_client") }
  let(:session) { McpSession.create!(user: operator, account: account, ai_agent: agent) }
  let!(:grant) do
    create(:ai_promotion_grant, account: account, agent: agent, binding_kind: "mcp_session", binding_id: session.id)
  end

  def revoked_rows = AuditLog.where(account_id: account.id, action: "ai.promotion_grant.revoked")

  describe "a transport drop (revoke! with no flag)" do
    it "pauses the grant, which comes back when the owner reconnects" do
      session.revoke!

      expect(grant.reload).not_to be_revoked
      expect(session.reload).to be_reactivatable
      expect(Ai::PromotionGrants::Binding.target_live?(kind: "mcp_session", id: session.id,
                                                      account_id: account.id, agent_id: agent.id)).to be(false)
      expect(session.reactivate!).to be(true)
      expect(Ai::PromotionGrants::Binding.target_live?(kind: "mcp_session", id: session.id,
                                                      account_id: account.id, agent_id: agent.id)).to be(true)
    end

    it "is revoked by the sweep once the grace has passed" do
      session.revoke!
      session.update_columns(revoked_at: (McpSession::RECONNECT_GRACE_PERIOD + 1.minute).ago)

      Ai::PromotionGrants::BindingSweep.sweep!

      expect(grant.reload).to be_revoked
      expect(revoked_rows.sole.metadata["revocation_reason"]).to eq("session_ended")
    end
  end

  describe "a person's deliberate revoke (revoke!(final: true))" do
    it "revokes the grant at once with session_revoked_by_operator, and the session cannot come back" do
      expect(session.revoke!(final: true)).to be(true)

      expect(grant.reload).to be_revoked
      expect(revoked_rows.sole.metadata["revocation_reason"]).to eq("session_revoked_by_operator")
      expect(session.reload).not_to be_reactivatable
      expect(session.reactivate!).to be(false)
    end

    it "also finalises a session a transport drop already revoked inside the grace" do
      session.revoke!
      expect(session.revoke!(final: true)).to be(true)

      expect(grant.reload).to be_revoked
      expect(session.reload).not_to be_reactivatable
    end
  end

  describe "DELETE /api/v1/mcp/sessions/:id", type: :request do
    it "is a deliberate revoke: the bound grant ends now and the session cannot reconnect" do
      delete "/api/v1/mcp/sessions/#{session.id}", headers: auth_headers_for(operator)

      expect(response).to have_http_status(:ok)
      expect(grant.reload).to be_revoked
      expect(revoked_rows.sole.metadata["revocation_reason"]).to eq("session_revoked_by_operator")
      expect(session.reload).not_to be_reactivatable
    end
  end
end
