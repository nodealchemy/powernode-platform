# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentToolBridgeService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:user) { create(:user, account: account) }

  let(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, agent_type: "assistant")
  end

  subject(:bridge) { described_class.new(agent: agent, account: account) }

  describe '#tools_enabled?' do
    it 'returns true by default for standard agents' do
      expect(bridge.tools_enabled?).to be true
    end

    it 'returns false for mcp_client agents' do
      agent.update!(agent_type: "mcp_client")
      bridge = described_class.new(agent: agent)

      expect(bridge.tools_enabled?).to be false
    end

    it 'returns false when explicitly disabled in mcp_metadata' do
      agent.mcp_metadata = { "tool_access" => { "enabled" => false } }
      bridge = described_class.new(agent: agent)

      expect(bridge.tools_enabled?).to be false
    end

    it 'returns true when explicitly enabled in mcp_metadata' do
      agent.mcp_metadata = { "tool_access" => { "enabled" => true } }
      bridge = described_class.new(agent: agent)

      expect(bridge.tools_enabled?).to be true
    end

    context 'with various agent types' do
      %w[assistant code_assistant data_analyst content_generator monitor workflow_operations].each do |type|
        it "returns true for #{type} agents" do
          agent.update!(agent_type: type)
          bridge = described_class.new(agent: agent)

          expect(bridge.tools_enabled?).to be true
        end
      end
    end
  end

  describe '#max_iterations' do
    it 'defaults to 10' do
      expect(bridge.max_iterations).to eq(10)
    end

    it 'uses configured value from mcp_metadata' do
      agent.mcp_metadata = { "tool_access" => { "max_iterations" => 5 } }
      bridge = described_class.new(agent: agent)

      expect(bridge.max_iterations).to eq(5)
    end

    it 'caps at 25 regardless of configuration' do
      agent.mcp_metadata = { "tool_access" => { "max_iterations" => 100 } }
      bridge = described_class.new(agent: agent)

      expect(bridge.max_iterations).to eq(25)
    end

    it 'falls back to default for zero or negative values' do
      agent.mcp_metadata = { "tool_access" => { "max_iterations" => 0 } }
      bridge = described_class.new(agent: agent)

      expect(bridge.max_iterations).to eq(10)
    end
  end

  describe '#tool_definitions_for_llm' do
    before do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return([
        {
          name: "search_knowledge",
          description: "Search shared knowledge",
          parameters: {
            action: { type: "string", description: "Action", required: true },
            query: { type: "string", description: "Search query", required: true },
            limit: { type: "integer", description: "Max results" }
          }
        },
        {
          name: "query_learnings",
          description: "Query compound learnings",
          parameters: {
            action: { type: "string", description: "Action", required: true },
            category: { type: "string", description: "Category", enum: %w[pattern best_practice discovery failure_mode] }
          }
        }
      ])
    end

    it 'returns an array of tool definitions' do
      tools = bridge.tool_definitions_for_llm

      expect(tools).to be_an(Array)
      expect(tools.length).to eq(2)
    end

    it 'strips the :action parameter from definitions' do
      tools = bridge.tool_definitions_for_llm

      tools.each do |tool|
        expect(tool[:parameters][:properties]).not_to have_key("action")
      end
    end

    it 'includes proper JSON Schema structure' do
      tools = bridge.tool_definitions_for_llm
      search_tool = tools.find { |t| t[:name] == "search_knowledge" }

      expect(search_tool[:parameters][:type]).to eq("object")
      expect(search_tool[:parameters][:properties]).to have_key("query")
      expect(search_tool[:parameters][:required]).to include("query")
      expect(search_tool[:parameters][:required]).not_to include("action")
    end

    it 'preserves enum values in parameters' do
      tools = bridge.tool_definitions_for_llm
      learnings_tool = tools.find { |t| t[:name] == "query_learnings" }

      category_prop = learnings_tool[:parameters][:properties]["category"]
      expect(category_prop[:enum]).to eq(%w[pattern best_practice discovery failure_mode])
    end

    context 'with allowed_tools filter' do
      before do
        agent.mcp_metadata = { "tool_access" => { "allowed_tools" => ["search_knowledge"] } }
      end

      it 'only includes allowed tools' do
        bridge = described_class.new(agent: agent)
        tools = bridge.tool_definitions_for_llm

        expect(tools.length).to eq(1)
        expect(tools.first[:name]).to eq("search_knowledge")
      end
    end

    context 'with wildcard allowed_tools' do
      before do
        agent.mcp_metadata = { "tool_access" => { "allowed_tools" => ["*"] } }
      end

      it 'includes all tools' do
        bridge = described_class.new(agent: agent)
        tools = bridge.tool_definitions_for_llm

        expect(tools.length).to eq(2)
      end
    end
  end

  describe '#dispatch_tool_call' do
    let(:tool_call) do
      { name: "search_knowledge", arguments: { "query" => "permissions" } }
    end

    it 'routes through McpPlatformToolRegistrar' do
      expect(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).with(
        "platform.search_knowledge",
        params: { "query" => "permissions" },
        account: account,
        user: user,
        agent_id: agent.id,
        mcp_agent: agent
      ).and_return({ success: true, data: [] })

      result = bridge.dispatch_tool_call(tool_call)
      parsed = JSON.parse(result)

      expect(parsed["success"]).to eq(true)
    end

    it 'handles string arguments' do
      string_tool_call = { name: "search_knowledge", arguments: '{"query": "permissions"}' }

      expect(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).with(
        "platform.search_knowledge",
        params: { "query" => "permissions" },
        account: account,
        user: user,
        agent_id: agent.id,
        mcp_agent: agent
      ).and_return({ success: true })

      bridge.dispatch_tool_call(string_tool_call)
    end

    it 'wraps unknown tool errors as JSON' do
      allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
        .and_raise(ArgumentError, "Unknown platform tool: nonexistent_tool")

      result = bridge.dispatch_tool_call({ name: "nonexistent_tool", arguments: {} })
      parsed = JSON.parse(result)

      expect(parsed["error"]).to eq("Unknown tool: nonexistent_tool")
    end

    it 'wraps permission errors as JSON' do
      allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
        .and_raise(Mcp::ProtocolService::PermissionDeniedError, "Permission denied")

      result = bridge.dispatch_tool_call(tool_call)
      parsed = JSON.parse(result)

      expect(parsed["error"]).to eq("Permission denied")
    end

    it 'wraps rate limit errors as JSON' do
      allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
        .and_raise(Ai::Introspection::RateLimiter::RateLimitExceeded.new(retry_after: 30))

      result = bridge.dispatch_tool_call(tool_call)
      parsed = JSON.parse(result)

      expect(parsed["error"]).to eq("Rate limit exceeded")
      expect(parsed["message"]).to include("Retry after")
    end

    it 'truncates oversized results' do
      large_result = { data: "x" * 100_000 }
      allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_return(large_result)

      result = bridge.dispatch_tool_call(tool_call)

      expect(result.bytesize).to be <= described_class::MAX_RESULT_SIZE + 100
      expect(result).to include("truncated")
    end
  end

  describe '#execute_tool_loop' do
    let(:llm_client) { instance_double(WorkerLlmClient) }
    let(:messages) { [{ role: "user", content: "Search for permission docs" }] }

    before do
      allow(Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return([
        {
          name: "search_knowledge",
          description: "Search shared knowledge",
          parameters: { query: { type: "string", description: "Search query", required: true } }
        }
      ])
    end

    context 'when LLM returns text directly' do
      let(:response) do
        Ai::Llm::Response.new(
          content: "Here is the answer",
          tool_calls: [],
          finish_reason: "stop",
          usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 }
        )
      end

      it 'returns the text response without tool calls' do
        allow(llm_client).to receive(:complete_with_tools).and_return(response)

        result = bridge.execute_tool_loop(
          llm_client: llm_client, messages: messages, model: "test-model"
        )

        expect(result[:content]).to eq("Here is the answer")
        expect(result[:usage][:total_tokens]).to eq(30)
        expect(result[:tool_calls_log]).to be_empty
      end
    end

    context 'when LLM calls a tool then returns text' do
      let(:tool_response) do
        Ai::Llm::Response.new(
          content: nil,
          tool_calls: [{ id: "call_1", name: "search_knowledge", arguments: { query: "permissions" } }],
          finish_reason: "tool_calls",
          usage: { prompt_tokens: 15, completion_tokens: 10, total_tokens: 25 }
        )
      end

      let(:final_response) do
        Ai::Llm::Response.new(
          content: "Based on the search results, permissions are...",
          tool_calls: [],
          finish_reason: "stop",
          usage: { prompt_tokens: 40, completion_tokens: 30, total_tokens: 70 }
        )
      end

      before do
        allow(llm_client).to receive(:complete_with_tools)
          .and_return(tool_response, final_response)
        allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
          .and_return({ success: true, data: [{ title: "Permission Guide" }] })
      end

      it 'dispatches the tool call and returns the final response' do
        result = bridge.execute_tool_loop(
          llm_client: llm_client, messages: messages, model: "test-model"
        )

        expect(result[:content]).to eq("Based on the search results, permissions are...")
        expect(result[:tool_calls_log].size).to eq(1)
        expect(result[:tool_calls_log].first[:tool]).to eq("search_knowledge")
      end

      it 'accumulates tokens across iterations' do
        result = bridge.execute_tool_loop(
          llm_client: llm_client, messages: messages, model: "test-model"
        )

        expect(result[:usage][:total_tokens]).to eq(95) # 25 + 70
        expect(result[:usage][:prompt_tokens]).to eq(55) # 15 + 40
        expect(result[:usage][:completion_tokens]).to eq(40) # 10 + 30
      end

      it 'appends tool call and result messages to conversation' do
        bridge.execute_tool_loop(
          llm_client: llm_client, messages: messages, model: "test-model"
        )

        expect(messages.length).to eq(3)
        expect(messages[1][:role]).to eq("assistant")
        expect(messages[1][:tool_calls]).to be_present
        expect(messages[2][:role]).to eq("tool")
        expect(messages[2][:tool_call_id]).to eq("call_1")
      end
    end

    context 'when max iterations reached with pending tool calls' do
      let(:tool_response) do
        Ai::Llm::Response.new(
          content: "Partial answer",
          tool_calls: [{ id: "call_n", name: "search_knowledge", arguments: {} }],
          finish_reason: "tool_calls",
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        )
      end

      before do
        agent.mcp_metadata = { "tool_access" => { "max_iterations" => 1 } }
        allow(llm_client).to receive(:complete_with_tools).and_return(tool_response)
      end

      it 'returns the response at max iteration' do
        bridge = described_class.new(agent: agent, account: account)
        result = bridge.execute_tool_loop(
          llm_client: llm_client, messages: messages, model: "test-model"
        )

        expect(result[:content]).to eq("Partial answer")
        expect(result[:tool_calls_log]).to be_empty
      end
    end

    context 'with multiple tool calls in one response' do
      let(:multi_tool_response) do
        Ai::Llm::Response.new(
          content: nil,
          tool_calls: [
            { id: "call_a", name: "search_knowledge", arguments: { query: "auth" } },
            { id: "call_b", name: "search_knowledge", arguments: { query: "roles" } }
          ],
          finish_reason: "tool_calls",
          usage: { prompt_tokens: 20, completion_tokens: 15, total_tokens: 35 }
        )
      end

      let(:final_response) do
        Ai::Llm::Response.new(
          content: "Combined results...",
          tool_calls: [],
          finish_reason: "stop",
          usage: { prompt_tokens: 60, completion_tokens: 40, total_tokens: 100 }
        )
      end

      before do
        allow(llm_client).to receive(:complete_with_tools)
          .and_return(multi_tool_response, final_response)
        allow(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
          .and_return({ success: true })
      end

      it 'dispatches all tool calls' do
        result = bridge.execute_tool_loop(
          llm_client: llm_client, messages: messages, model: "test-model"
        )

        expect(Ai::Tools::McpPlatformToolRegistrar).to have_received(:execute_tool).twice
        expect(result[:tool_calls_log].size).to eq(2)
      end
    end
  end
end
