# frozen_string_literal: true

require "rails_helper"

# D2: the tool-bridge path carries loop-local tools (the Ralph git tools) beside
# the platform registry. A local tool is advertised, survives the provider tool
# cap, and is dispatched to its own executor — never to the platform registrar.
RSpec.describe Ai::AgentToolBridgeService, "#execute_tool_loop with local tools", type: :service do
  include PermissionTestHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) do
    create(:ai_agent, account: account, provider: provider, creator: user, agent_type: "assistant",
                      mcp_metadata: { "tool_access" => { "enabled" => true, "allowed_tools" => [ "discover_skills" ] } })
  end

  subject(:bridge) { described_class.new(agent: agent, account: account) }

  let(:local_definitions) do
    [ { name: "write_file", description: "Write a file and commit it",
        parameters: { type: "object", properties: { path: { type: "string" } }, required: [ "path" ] } } ]
  end

  let(:local_executor) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def execute(name, arguments)
        @calls << [ name, arguments ]
        { success: true, commit_sha: "0123456789abcdef0123456789abcdef01234567" }
      end
    end.new
  end

  let(:llm_client_class) do
    Class.new do
      attr_reader :requests

      def initialize(provider_type, responses)
        @provider_type = provider_type
        @responses = responses
        @requests = []
      end

      attr_reader :provider_type

      def complete_with_tools(messages:, tools:, model:, **_opts)
        @requests << { messages: messages.map(&:dup), tools: tools, model: model }
        @responses.shift || Ai::Llm::Response.new(content: "done", finish_reason: "stop")
      end
    end
  end

  def tool_call_response(name, arguments)
    Ai::Llm::Response.new(content: nil, finish_reason: "tool_calls",
                          tool_calls: [ { id: "call_1", name: name, arguments: arguments } ])
  end

  def names(tools)
    tools.map { |t| t[:name] || t.dig(:function, :name) }
  end

  it "dispatches a local tool call to the local executor, never to the platform registrar" do
    client = llm_client_class.new("anthropic", [ tool_call_response("write_file", { path: "a.go" }) ])
    expect(Ai::Tools::McpPlatformToolRegistrar).not_to receive(:execute_tool)

    result = bridge.execute_tool_loop(llm_client: client, messages: [ { role: "user", content: "go" } ], model: "m",
                                      local_tool_definitions: local_definitions, local_tool_executor: local_executor)

    expect(local_executor.calls).to eq([ [ "write_file", { path: "a.go" } ] ])
    expect(result[:tool_calls_log].map { |l| l[:tool] }).to eq([ "write_file" ])
    tool_message = client.requests.last[:messages].find { |m| m[:role] == "tool" }
    expect(tool_message[:content]).to include("0123456789abcdef0123456789abcdef01234567")
  end

  it "routes a name the local executor does not own to the platform registrar" do
    client = llm_client_class.new("anthropic", [ tool_call_response("discover_skills", { task: "x" }) ])
    expect(Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
      .with("platform.discover_skills", hash_including(account: account)).and_return({ success: true })

    bridge.execute_tool_loop(llm_client: client, messages: [ { role: "user", content: "go" } ], model: "m",
                             local_tool_definitions: local_definitions, local_tool_executor: local_executor)

    expect(local_executor.calls).to be_empty
  end

  it "advertises local tools and keeps them when the provider cap trims the platform list" do
    # 150 platform tools that ALL match the detected intent (monitoring: "health",
    # "status"), so the relevance filter must truncate. write_file matches no
    # intent pattern: only the cap reservation keeps it, wherever it would sit.
    platform = Array.new(150) do |i|
      { name: "integration_health_#{i}", description: "health probe #{i}",
        parameters: { type: "object", properties: {}, required: [] } }
    end
    allow(bridge).to receive(:tool_definitions_for_llm).and_return(platform)
    client = llm_client_class.new("openai", [])

    bridge.execute_tool_loop(llm_client: client, messages: [ { role: "user", content: "show the integration health status" } ],
                             model: "m", local_tool_definitions: local_definitions, local_tool_executor: local_executor)

    sent = names(client.requests.first[:tools])
    expect(sent.first).to eq("write_file")
    expect(sent.size).to eq(described_class::OPENAI_TOOL_CAP)
  end

  it "advertises no local tool when none is supplied" do
    client = llm_client_class.new("anthropic", [])

    bridge.execute_tool_loop(llm_client: client, messages: [ { role: "user", content: "go" } ], model: "m")

    expect(names(client.requests.first[:tools])).not_to include("write_file")
  end
end
