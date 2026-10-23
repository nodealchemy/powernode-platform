# frozen_string_literal: true

require "rails_helper"

# The streamable controller hands the registrar the caller's owner-resolved MCP
# session twice, side by side: `mcp_session_id` (a proposal's origin session)
# and `mcp_session` (a promotion grant request's binding). Both come from the
# ONE current_mcp_session, so a proposal and a grant request filed on the same
# session record the same session id, and every call hands the two the same id.
RSpec.describe "A proposal and a grant request filed on one MCP session", type: :request do
  let(:account) { create(:account) }
  let!(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:user) { user_with_permissions("ai.agents.read", account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:token) { create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write") }
  let(:mcp_endpoint) { "/api/v1/mcp/message" }
  let(:catalog) do
    Class.new do
      def required_permission(category) = category == "release.promote" ? "ai.agents.update" : nil
      def subjects(**) = []
      def unknown_subject_ids(ids:, **) = []
    end.new
  end

  before do
    allow(Ai::PromotionGrants::Catalog).to receive(:provider).and_return(catalog)
    allow_any_instance_of(Ai::AgentOutreachService).to receive(:notify_proposal).and_return(true)
  end

  def headers_for(session_id: nil)
    { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/json" }
      .merge(session_id ? { "Mcp-Session-Id" => session_id } : {})
  end

  def rpc(method, params = {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  def initialize_session
    post mcp_endpoint,
         params: rpc("initialize", { "protocolVersion" => "2025-11-25",
                                     "clientInfo" => { "name" => "sharedSession", "version" => "1" } }),
         headers: headers_for
    McpSession.find_by!(session_token: response.headers["Mcp-Session-Id"])
  end

  def call_tool(name, arguments, session)
    post mcp_endpoint, params: rpc("tools/call", { "name" => name, "arguments" => arguments }),
                       headers: headers_for(session_id: session.session_token)
    expect(response).to have_http_status(:ok)
  end

  it "records the same owner-resolved session id on both rows, from one source" do
    session = initialize_session
    expect(session.reload.ai_agent).to be_present

    handed = []
    allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_wrap_original do |original, *args, **kwargs|
      handed << [ kwargs[:mcp_session_id], kwargs[:mcp_session]&.id ]
      original.call(*args, **kwargs)
    end

    call_tool("platform.create_proposal",
              { proposal_type: "feature", title: "Ship it", description: "From the same session" }, session)
    call_tool("platform.request_promotion_grant",
              { environment: "ops", expires_in_hours: 1, reason: "ship it", bind: "session" }, session)

    expect(handed).to eq([ [ session.id, session.id ], [ session.id, session.id ] ])

    proposal = Ai::AgentProposal.where(account_id: account.id).sole
    grant_request = Ai::PromotionGrantRequest.where(account_id: account.id).sole
    expect(proposal.origin_mcp_session_id).to eq(session.id)
    expect(grant_request.binding_kind).to eq("mcp_session")
    expect(grant_request.binding_id).to eq(proposal.origin_mcp_session_id)
  end
end
