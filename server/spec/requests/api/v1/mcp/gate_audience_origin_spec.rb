# frozen_string_literal: true

require "rails_helper"

# MCP identity plan #5 and #6, through the real door. An OAuth MCP call is a
# machine call whether or not the account could give it a client agent, so the
# gate resolves it in the agent audience (its own rows plus scope "global"),
# never on the operator path (scope "action_type"). Before this, an account with
# no active AI provider got no client agent, and an operator's action_type
# auto_approve row ran the call unparked. The parked call also records the door
# it came through (the descriptor's origin).
RSpec.describe "Gate audience over OAuth MCP (MCP identity plan #5, #6)", type: :request do
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account) } # first user: OWNER, holds every permission
  let!(:skill) { create(:ai_skill, account: account, slug: "refine-me", name: "Refine Me") }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    { "Authorization" => "Bearer #{oauth_token.plaintext_token}", "Content-Type" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25" }
  end
  let(:service) { instance_double(Ai::SelfImprovement::SkillMutationService) }

  before do
    allow(Ai::SelfImprovement::SkillMutationService).to receive(:new).and_return(service)
    allow(service).to receive(:mutate!).and_return(double("version", id: SecureRandom.uuid))
    # The operator path: an action_type auto_approve row for a core gate-wired
    # category, and no scope-"global" row.
    Ai::InterventionPolicy.create!(account: account, scope: "action_type", action_category: "dev.prompt_refine",
                                   policy: "auto_approve", priority: 5, is_active: true)
  end

  def mcp_mutate
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { "name" => "platform.mutate_skill",
                             "arguments" => { "skill_id" => skill.id, "strategy" => "rephrase" } } }.to_json,
         headers: headers
    json_response.dig("result", "structuredContent")
  end

  def expect_parked(result)
    expect(result).to include("success" => true)
    expect(result["data"]).to include("pending" => true)
    expect(service).not_to have_received(:mutate!)
    Ai::DeferredOperation.find(result["data"]["deferred_operation_id"])
  end

  context "when the account has no active AI provider (no client agent can be created)" do
    before { account.ai_providers.update_all(is_active: false) }

    it "parks the call instead of letting the operator's row run it, and records the MCP door" do
      operation = expect_parked(mcp_mutate)

      expect(account.ai_agents.where(agent_type: "mcp_client")).to be_empty
      expect(operation.params["principal"]).to include("kind" => "user", "user_id" => user.id, "origin" => "mcp_oauth")
    end
  end

  context "when the account has an active AI provider (the call carries a client agent)" do
    before do
      create(:ai_provider, account: account, is_active: true) unless account.ai_providers.where(is_active: true).exists?
    end

    it "parks the same way (the control), and records the MCP door" do
      operation = expect_parked(mcp_mutate)

      expect(account.ai_agents.where(agent_type: "mcp_client").count).to eq(1)
      expect(operation.params["principal"]).to include("origin" => "mcp_oauth")
    end
  end

  it "still lets the operator's row run the same call built by a person's own REST door (the other arm)" do
    tool = Ai::Tools::SelfImprovementTool.new(account: account, user: user)

    result = tool.execute(params: { action: "mutate_skill", skill_id: skill.id, strategy: "rephrase" }.with_indifferent_access)

    expect(result[:success]).to be(true), result[:error].to_s
    expect(service).to have_received(:mutate!)
  end
end
