# frozen_string_literal: true

require "rails_helper"

# A6 H1 through the real doors, keyed on the TRANSPORT. Every call through the
# MCP door is agent-opened. The streamable controller hands the tool an
# `mcp_client_agent` when the call carries an OAuth token and the account has a
# provider to back that identity, and no agent otherwise; either way no person
# is recorded, and ranking refuses to spend until A6b. The token's owner is the
# AUTHORITY the permission checks ask, never the CONSENT the security gate
# reads. Only the REST button, a person's UI session, records its person and
# spends: the other arm, with the same user and the same component.
RSpec.describe "MCP platform_investigate opener (A6 H1)", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("platform.status.read", "ai.autonomy.manage", account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    { "Authorization" => "Bearer #{oauth_token.plaintext_token}", "Content-Type" => "application/json" }
  end
  let!(:component) do
    create(:platform_component_status, account: account, component_kind: "docker_host",
                                       component_ref: "host-1", display_name: "web-1",
                                       verdict: Platform::ComponentStatus::DOWN,
                                       conditions: [ { "type" => "Connected", "status" => false,
                                                       "reason" => "ConnectionError", "severity" => "down" } ])
  end

  before { allow(WorkerJobService).to receive(:enqueue_job) }

  def investigate_over_mcp!
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { "name" => "platform.platform_investigate",
                             "arguments" => { "component_kind" => "docker_host",
                                              "component_ref" => "host-1" } } }.to_json,
         headers: headers
  end

  def investigate_over_rest!
    post "/api/v1/platform/component_statuses/#{component.id}/investigations",
         headers: auth_headers_for(user), as: :json
  end

  describe "who is recorded as the opener" do
    it "records the MCP client agent, and no person" do
      create(:ai_provider, account: account)

      investigate_over_mcp!

      expect(response).to have_http_status(:ok)
      client_agent = Ai::Agent.find_by!(account: account, agent_type: "mcp_client")
      investigation = Platform::Investigation.sole
      expect(investigation.opened_by_agent_id).to eq(client_agent.id)
      expect(investigation.opened_by_user_id).to be_nil
      expect(investigation.opened_via_mcp?).to be(true)
      expect(client_agent.creator_id).to eq(user.id)
    end

    # Keyed on the transport, not on whether an agent could be resolved. With
    # no provider there is no client agent, and the call is still not a
    # person's consent: it is refused the same way, and says who opened it.
    it "records no person when no client agent can stand for the call, and refuses its spend" do
      investigate_over_mcp!

      expect(response).to have_http_status(:ok)
      expect(Ai::Agent.where(account: account, agent_type: "mcp_client")).to be_empty
      investigation = Platform::Investigation.sole
      expect(investigation.opened_by_user_id).to be_nil
      expect(investigation.opened_by_agent_id).to be_nil
      expect(investigation.opened_via_mcp?).to be(true)

      outcome = Platform::Investigation::Ranking.run!(investigation, account: account)

      expect(outcome[:ranking]).to include("state" => "not_run", "reason" => "AutomaticSpendNeedsGrant",
                                           "retryable" => false)
      expect(outcome[:ranking]["message"]).to include("An MCP client opened this investigation")
    end

    it "records the person who pressed the REST button — the other arm" do
      investigate_over_rest!

      expect(response).to have_http_status(:success)
      investigation = Platform::Investigation.sole
      expect(investigation.opened_by_user_id).to eq(user.id)
      expect(investigation.opened_by_agent_id).to be_nil
      expect(investigation.opened_via_mcp?).to be(false)
    end
  end

  # Through the REAL pre-execution security gate and the real principal
  # resolution, as in ranking_spec's G1 block: only the provider boundary and
  # the non-gate rails are stubbed. Same user, same component, same account with
  # a provider; only the door differs.
  describe "who may spend, through the real security gate" do
    let!(:canonical) do
      create(:ai_agent, :global, slug: "infrastructure-generalist", name: "Infrastructure Generalist")
    end
    let!(:account_provider) { create(:ai_provider, account: account) }
    let(:valid_json) do
      '{"hypotheses":[{"cause":"docker daemon died","evidence_classes":["conditions"],"score":6.0}]}'
    end

    before do
      @provider_calls = 0
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:execute_with_provider) do |*_args|
        @provider_calls += 1
        { "output" => valid_json, "metadata" => { "tokens_used" => 10 } }
      end
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_input_guardrails).and_return(blocked: false)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_post_execution_security_gate).and_return(nil)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:run_output_guardrails).and_return(blocked: false)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:validate_output!).and_return(true)
      allow_any_instance_of(Ai::McpAgentExecutor).to receive(:write_back_to_memory).and_return(nil)
    end

    def rank_sole_investigation
      Platform::Investigation::Ranking.run!(Platform::Investigation.sole, account: account)
    end

    it "spends as the person when the REST button opened it" do
      investigate_over_rest!
      expect(response).to have_http_status(:success)

      outcome = nil
      expect { outcome = rank_sole_investigation }.to change(Ai::AgentExecution, :count).by(1)

      expect(outcome[:ranking]).to be_nil
      expect(outcome[:ranked].map { |c| c[:cause] }).to eq([ "docker daemon died" ])
      expect(@provider_calls).to eq(1)
      expect(Ai::AgentExecution.order(:created_at).last.user_id).to eq(user.id)
    end

    it "refuses when the same person's MCP client opened it, and books nothing — the other arm" do
      investigate_over_mcp!
      expect(response).to have_http_status(:ok)
      expect(Platform::Investigation.sole.opened_by_agent_id).to be_present

      outcome = nil
      expect { outcome = rank_sole_investigation }.not_to change(Ai::AgentExecution, :count)

      expect(outcome[:ranking]).to include("state" => "not_run", "reason" => "AutomaticSpendNeedsGrant",
                                           "retryable" => false)
      expect(outcome[:ranking]["message"]).to include("An agent opened this investigation")
      expect(@provider_calls).to eq(0)
      expect(Ai::Agent.where(cloned_from_id: canonical.id)).to be_empty
    end
  end
end
