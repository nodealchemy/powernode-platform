# frozen_string_literal: true

require 'rails_helper'

# IMP-fea579e125d1 (the 0.3.0 interim token cap), IMP-feffafe51c3c (per-execution
# ceiling alert) and the kept parts of IMP-df846f2166d5.
RSpec.describe Ai::AgentToolBridgeService, "token cap", type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:user) { create(:user, account: account) }
  let(:roster_slug) { Ai::Agents::CanonicalRoster.slugs.first }
  let(:role_verbs) { Ai::Agents::CanonicalRoster.fetch(roster_slug).dig(:role, :verbs) }
  let(:bootstrap) { %w[discover_tools describe_tool get_agent assemble_task record_agent_execution] }

  def registry_defs(names)
    names.map do |n|
      { name: n, description: "d #{n}", parameters: { q: { type: "string", description: "q" } } }
    end
  end

  def names_of(tools) = tools.map { |t| t[:name] }

  describe "a roster shadow" do
    let(:agent) do
      create(:ai_agent, account: account, provider: provider, creator: user, agent_type: "assistant",
                        name: "Shadow").tap do |a|
        a.update_column(:slug, roster_slug)
        # the seeded floor: tool_families, never allowed_tools
        a.update!(mcp_metadata: { "tool_access" => { "tool_families" => %w[list get search create] } })
      end
    end

    before do
      everything = (role_verbs + bootstrap + %w[list_agents get_user search_x create_y] +
                    (1..300).map { |i| "list_thing_#{i}" }).uniq
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(registry_defs(everything))
    end

    it "is advertised exactly its role verbs plus the five bootstrap verbs, never the family expansion" do
      tools = described_class.new(agent: agent, account: account).tool_definitions_for_llm

      expect(names_of(tools)).to match_array((role_verbs + bootstrap).uniq)
    end
  end

  describe "any other agent" do
    let(:agent) do
      create(:ai_agent, account: account, provider: provider, creator: user, agent_type: "assistant")
    end
    let(:bridge) { described_class.new(agent: agent, account: account) }

    before do
      names = (1..120).map { |i| "list_thing_#{i}" } + %w[discover_tools describe_tool search_knowledge]
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(registry_defs(names))
    end

    it "caps the catalog at 30 and keeps discover_tools and describe_tool for the overflow" do
      tools = bridge.tool_definitions_for_llm

      expect(tools.size).to eq(30)
      expect(names_of(tools)).to include("discover_tools", "describe_tool")
    end

    it "sends at most 30 definitions to the model on every turn and records per-turn metrics" do
      llm = instance_double(WorkerLlmClient)
      sent = []
      allow(llm).to receive(:complete_with_tools) do |tools:, **|
        sent << tools.size
        Ai::Llm::Response.new(content: "ok", tool_calls: [], finish_reason: "stop",
                              usage: { prompt_tokens: 1200, completion_tokens: 10, total_tokens: 1210,
                                       cached_tokens: 900 })
      end

      result = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "hi" }], model: "m")

      expect(sent).to eq([30])
      expect(result[:turns]).to eq([{ "prompt_tokens" => 1200, "cached_tokens" => 900, "tool_definition_count" => 30 }])
    end
  end

  describe "the per-execution cost ceiling" do
    let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user, agent_type: "assistant") }
    let(:bridge) { described_class.new(agent: agent, account: account) }
    let(:llm) { instance_double(WorkerLlmClient) }
    let(:tool_turn) do
      Ai::Llm::Response.new(content: nil, finish_reason: "tool_calls",
                            tool_calls: [{ id: "c1", name: "search_knowledge", arguments: {} }],
                            usage: { prompt_tokens: 1000, completion_tokens: 10, total_tokens: 1010 })
    end

    before do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions)
        .and_return(registry_defs(%w[search_knowledge]))
      allow(Ai::CostCalculationService).to receive(:calculate_cents).and_return(150)
      allow(llm).to receive(:complete_with_tools).and_return(tool_turn)
      allow(bridge).to receive(:dispatch_tool_call_capturing).and_return(["{}", {}])
      allow(NotificationService).to receive(:send_system_alert)
    end

    it "parks the run, alerts the account and writes an audit row when one execution passes the ceiling" do
      expect do
        @result = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "go" }], model: "m")
      end.to change { AuditLog.where(account_id: account.id, action: "ai.execution.cost_ceiling_exceeded").count }.by(1)

      expect(@result[:finish_reason]).to eq("cost_ceiling_parked")
      expect(llm).to have_received(:complete_with_tools).once
      expect(NotificationService).to have_received(:send_system_alert)
        .with(hash_including(account: account, type: "execution_cost_ceiling")).once
    end

    it "does nothing below the ceiling" do
      allow(Ai::CostCalculationService).to receive(:calculate_cents).and_return(3)
      allow(llm).to receive(:complete_with_tools).and_return(
        Ai::Llm::Response.new(content: "done", tool_calls: [], finish_reason: "stop",
                              usage: { prompt_tokens: 10, completion_tokens: 1, total_tokens: 11 })
      )

      result = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "go" }], model: "m")

      expect(result[:finish_reason]).to eq("stop")
      expect(NotificationService).not_to have_received(:send_system_alert)
    end
  end
end

RSpec.describe WorkerLlmClient, "credential use", type: :service do
  it "stamps the credential's last_used_at when a call is tracked" do
    account = create(:account)
    credential = create(:ai_provider_credential, account: account, last_used_at: 1.month.ago)
    agent = create(:ai_agent, account: account, provider: credential.provider)
    client = described_class.new(provider: credential.provider, credential: credential, agent_id: agent.id)
    response = Ai::Llm::Response.new(content: "x", tool_calls: [], finish_reason: "stop",
                                     usage: { prompt_tokens: 5, completion_tokens: 1, total_tokens: 6 })

    expect { client.send(:track_llm_usage!, response, "m") }
      .to(change { credential.reload.last_used_at }.to(be_within(1.minute).of(Time.current)))
  end
end
