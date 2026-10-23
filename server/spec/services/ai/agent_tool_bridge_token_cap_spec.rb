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
        # the real canonical marker: a seeded GLOBAL system row
        a.update_columns(slug: roster_slug, account_id: nil, is_system: true)
        # the seeded floor: tool_families, never allowed_tools
        a.update!(mcp_metadata: { "tool_access" => { "tool_families" => %w[list get search create] } })
      end
    end

    before do
      everything = (role_verbs + bootstrap + %w[list_agents get_user search_x create_y] +
                    (1..300).map { |i| "list_thing_#{i}" }).uniq
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(registry_defs(everything))
    end

    it "is not mistaken for an agent a user merely names like a roster row" do
      lookalike = create(:ai_agent, account: account, provider: provider, creator: user, agent_type: "assistant",
                                    name: "Platform Reviewer")
      lookalike.update!(mcp_metadata: { "tool_access" => { "allowed_tools" => %w[list_agents] } })
      expect(lookalike.slug).to eq("platform-reviewer")

      bridge = described_class.new(agent: lookalike, account: account)

      expect(bridge.roster_shadow?).to be(false)
      names = names_of(bridge.tool_definitions_for_llm)
      expect(names).to include("list_agents", "discover_tools")
      expect(names).not_to include("list_thing_1")
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

RSpec.describe Ai::AgentToolBridgeService, "discovery, ceiling carry-over and failure isolation", type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider, creator: user, agent_type: "assistant") }
  let(:bridge) { described_class.new(agent: agent, account: account) }
  let(:llm) { instance_double(WorkerLlmClient) }

  def registry_defs(names)
    names.map { |n| { name: n, description: "d #{n}", parameters: { q: { type: "string", description: "q" } } } }
  end

  def call_turn(name, args = {}, cost_usage: { prompt_tokens: 100, completion_tokens: 1, total_tokens: 101 })
    Ai::Llm::Response.new(content: nil, finish_reason: "tool_calls", usage: cost_usage,
                          tool_calls: [{ id: "c#{SecureRandom.hex(3)}", name: name, arguments: args }])
  end

  def text_turn
    Ai::Llm::Response.new(content: "done", tool_calls: [], finish_reason: "stop",
                          usage: { prompt_tokens: 10, completion_tokens: 1, total_tokens: 11 })
  end

  describe "a tool found beyond the cap" do
    before do
      names = (1..120).map { |i| "list_thing_#{i}" } + %w[discover_tools describe_tool]
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(registry_defs(names))
      allow(bridge).to receive(:dispatch_tool_call_capturing).and_return(["{}", { success: true }])
    end

    it "is callable on the next turn once describe_tool has loaded it" do
      seen = []
      turns = [call_turn("describe_tool", { name: "platform.list_thing_119" }), text_turn]
      allow(llm).to receive(:complete_with_tools) do |tools:, **|
        seen << tools.map { |t| t[:name] }
        turns.shift
      end

      bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "go" }], model: "m")

      expect(seen.first).not_to include("list_thing_119")
      expect(seen.last).to include("list_thing_119")
    end

    it "never adds a tool outside the agent's scope, even one the registry holds" do
      agent.update!(mcp_metadata: { "tool_access" => { "allowed_tools" => %w[list_thing_1] } })
      scoped = described_class.new(agent: agent, account: account)

      expect(scoped.definitions_for_names(%w[list_thing_119])).to eq([])
      expect(scoped.definitions_for_names(%w[list_thing_1]).map { |t| t[:name] }).to eq(%w[list_thing_1])
    end

    it "serves the worker the definitions it names, and picks the first set by the user's intent" do
      expect(bridge.definitions_for_names(%w[platform.list_thing_119]).map { |t| t[:name] }).to eq(%w[list_thing_119])
      expect(bridge.definitions_for_names(%w[nope])).to eq([])
    end
  end

  describe "describe_tool arguments that arrive as a JSON string" do
    it "still loads the tool" do
      names = (1..120).map { |i| "list_thing_#{i}" } + %w[discover_tools describe_tool]
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(registry_defs(names))
      allow(bridge).to receive(:dispatch_tool_call_capturing).and_return(["{}", { success: true }])
      seen = []
      turns = [Ai::Llm::Response.new(content: nil, finish_reason: "tool_calls", usage: { prompt_tokens: 1 },
                                     tool_calls: [{ id: "c1", name: "describe_tool",
                                                    arguments: { name: "list_thing_119" }.to_json }]),
               text_turn]
      allow(llm).to receive(:complete_with_tools) { |tools:, **| seen << tools.map { |t| t[:name] }; turns.shift }

      bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "go" }], model: "m")

      expect(seen.last).to include("list_thing_119")
    end
  end

  describe "reasoning phases after a park" do
    it "runs no reflection or evaluation once the ceiling was reached, and keeps the parked reason" do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(registry_defs(%w[search_knowledge]))
      allow(bridge).to receive(:dispatch_tool_call_capturing).and_return(["{}", {}])
      allow(NotificationService).to receive(:send_system_alert)
      allow(Ai::CostCalculationService).to receive(:calculate_cents).and_return(150)
      allow(llm).to receive(:complete_with_tools) { call_turn("search_knowledge") }
      reflection = instance_double(Ai::Reasoning::ReflectionService)
      allow(Ai::Reasoning::ReflectionService).to receive(:new).and_return(reflection)
      allow(reflection).to receive(:reflect)
      evaluator = instance_double(Ai::Reasoning::OutputEvaluatorService)
      allow(Ai::Reasoning::OutputEvaluatorService).to receive(:new).and_return(evaluator)
      allow(evaluator).to receive(:evaluate)

      result = bridge.execute_with_reasoning(
        llm_client: llm, messages: [{ role: "user", content: "go" }], model: "m",
        reflection_enabled: true, evaluation_config: { "enabled" => true }
      )

      expect(reflection).not_to have_received(:reflect)
      expect(evaluator).not_to have_received(:evaluate)
      expect(result[:finish_reason]).to eq("cost_ceiling_parked")
    end
  end

  describe "a worker catalog" do
    it "follows the user's intent rather than registry order" do
      names = (1..80).map { |i| "list_thing_#{i}" } + (1..40).map { |i| "integration_health_#{i}" }
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(registry_defs(names))

      tools = bridge.tool_definitions_for_llm(user_message: "show the integration health status")

      expect(tools.size).to eq(30)
      expect(tools.count { |t| t[:name].start_with?("integration_health_") }).to be >= 20
    end
  end

  describe "the cost ceiling across one execution" do
    before do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(registry_defs(%w[search_knowledge]))
      allow(bridge).to receive(:dispatch_tool_call_capturing).and_return(["{}", {}])
      allow(NotificationService).to receive(:send_system_alert)
    end

    it "uses the SiteSetting override" do
      expect(Ai::AgentBudget.execution_ceiling_cents).to eq(100)
      SiteSetting.set("ai_execution_cost_ceiling_cents", 500, setting_type: "integer")
      expect(Ai::AgentBudget.execution_ceiling_cents).to eq(500)
    end

    it "lets a turn under the ceiling run and parks on the turn that crosses it" do
      allow(Ai::CostCalculationService).to receive(:calculate_cents).and_return(60)
      allow(llm).to receive(:complete_with_tools) { call_turn("search_knowledge") }

      result = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "go" }], model: "m")

      expect(llm).to have_received(:complete_with_tools).twice
      expect(result[:finish_reason]).to eq("cost_ceiling_parked")
      expect(result[:content]).to include("cost ceiling")
    end

    it "keeps the stop notice when the model also spoke" do
      allow(Ai::CostCalculationService).to receive(:calculate_cents).and_return(150)
      allow(llm).to receive(:complete_with_tools) do
        Ai::Llm::Response.new(content: "partial answer", finish_reason: "tool_calls", usage: { prompt_tokens: 1 },
                              tool_calls: [{ id: "c1", name: "search_knowledge", arguments: {} }])
      end

      result = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "go" }], model: "m")

      expect(result[:content]).to start_with("partial answer")
      expect(result[:content]).to include("cost ceiling")
    end

    it "does not reset when the loop is re-entered for a reflection or evaluation retry" do
      allow(Ai::CostCalculationService).to receive(:calculate_cents).and_return(60)
      allow(llm).to receive(:complete_with_tools).and_return(text_turn)

      first = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "a" }], model: "m")
      second = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "b" }], model: "m")

      expect(first[:finish_reason]).to eq("stop")
      expect(NotificationService).to have_received(:send_system_alert).once
      expect(second[:finish_reason]).to eq("stop")
    end

    it "parks a re-entered loop that starts past the ceiling" do
      allow(Ai::CostCalculationService).to receive(:calculate_cents).and_return(60)
      allow(llm).to receive(:complete_with_tools) { call_turn("search_knowledge") }

      bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "a" }], model: "m")
      again = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "b" }], model: "m")

      expect(again[:finish_reason]).to eq("cost_ceiling_parked")
      expect(llm).to have_received(:complete_with_tools).exactly(3).times
    end

    it "carries the turns on an emergency halt" do
      allow(llm).to receive(:complete_with_tools) { call_turn("search_knowledge") }
      allow(bridge).to receive(:kill_switch_halted?).and_return(true)

      result = bridge.execute_tool_loop(llm_client: llm, messages: [{ role: "user", content: "a" }], model: "m")

      expect(result[:finish_reason]).to eq("emergency_halt")
      expect(result[:turns].size).to eq(1)
    end
  end

  describe Ai::AgentBudget, ".record_execution_ceiling_breach!" do
    it "still alerts when the audit write fails, and still audits when the alert fails" do
      allow(NotificationService).to receive(:send_system_alert)
      allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      described_class.record_execution_ceiling_breach!(account: account, agent: agent, cost_cents: 150, ceiling_cents: 100)
      expect(NotificationService).to have_received(:send_system_alert)

      allow(AuditLog).to receive(:create!).and_call_original
      allow(NotificationService).to receive(:send_system_alert).and_raise(StandardError)
      expect do
        described_class.record_execution_ceiling_breach!(account: account, agent: agent, cost_cents: 150, ceiling_cents: 100)
      end.to change { AuditLog.where(action: "ai.execution.cost_ceiling_exceeded").count }.by(1)
    end
  end

  describe "a parked run downstream" do
    let(:result) do
      { content: "partial", usage: { total_tokens: 5, prompt_tokens: 3, completion_tokens: 2 }, tool_calls_log: [],
        finish_reason: "cost_ceiling_parked", turns: [] }
    end

    it "carries finish_reason into the executor's result metadata" do
      executor = Ai::McpAgentExecutor.new(agent: agent, account: account)
      executor.instance_variable_set(:@start_time, Time.current)

      metadata = executor.send(:format_tool_loop_result, result, "m")["metadata"]

      expect(metadata["finish_reason"]).to eq("cost_ceiling_parked")
    end

    it "records a parked execution's routing outcome as failed" do
      execution = create(:ai_agent_execution, :running, account: account, agent: agent, provider: provider)
      decision = create(:ai_routing_decision, account: account, agent_execution: execution,
                                              model_tier: "reasoning", outcome: nil)

      execution.update!(status: "parked", completed_at: Time.current, duration_ms: 5)

      expect(decision.reload.outcome).to eq("failed")
    end

    it "is recorded as a parked execution, not a completed one" do
      mcp_result = { "result" => { "output" => "partial", "metadata" => { "finish_reason" => "cost_ceiling_parked" } } }

      expect(Ai::AgentExecution.final_status_for(mcp_result)).to eq("parked")
      expect(Ai::AgentExecution.final_status_for({ "result" => { "metadata" => {} } })).to eq("completed")
      expect(Ai::AgentExecution.final_status_for({ "error" => { "message" => "x" } })).to eq("failed")
      expect(Ai::AgentExecution.final_status_for({ "result" => "plain text" })).to eq("completed")
      expect(build(:ai_agent_execution, status: "parked")).to be_valid
      expect(build(:ai_agent_execution, status: "parked").finished?).to be(true)
    end
  end
end

RSpec.describe WorkerLlmClient, "credential use", type: :service do
  it "stamps the credential for clients with no agent_id and for skipped budget tracking" do
    account = create(:account)
    credential = create(:ai_provider_credential, account: account, last_used_at: 1.month.ago)
    response = Ai::Llm::Response.new(content: "x", tool_calls: [], finish_reason: "stop",
                                     usage: { prompt_tokens: 5, completion_tokens: 1, total_tokens: 6 })

    described_class.for_provider(provider: credential.provider, credential: credential)
                   .send(:track_llm_usage!, response, "m")

    expect(credential.reload.last_used_at).to be_within(1.minute).of(Time.current)
  end

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
