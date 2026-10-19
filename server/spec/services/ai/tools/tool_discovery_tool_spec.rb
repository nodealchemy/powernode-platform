# frozen_string_literal: true

require "rails_helper"

# C3-3 — platform.discover_tools: find a verb by intent instead of by exact name
# or by scanning every one-liner in tools/list. Ranks with
# Ai::Tools::SemanticToolDiscoveryService (embeddings, keyword fallback) and
# answers with the names a client actually calls, the one-line summary
# tools/list carries, the declared family and the declared read/write hints.
RSpec.describe Ai::Tools::ToolDiscoveryTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  def discover(**params)
    tool.send(:call, params)
  end

  before do
    Rails.cache.clear
    allow_any_instance_of(Ai::Tools::SemanticToolDiscoveryService)
      .to receive(:find_embedding_provider).and_return(nil)
  end

  it "is registered, declared read-only and in the discovery family" do
    expect(Ai::Tools::PlatformApiToolRegistry.all_tools["discover_tools"]).to eq(described_class.name)
    expect(described_class.declared_action("discover_tools")).to include(mutating: false)
    expect(Ai::Tools::PlatformApiToolRegistry.family_for("discover_tools")).to eq("discovery")
  end

  it "returns exact MCP names with summary, family, hints and how to load the schema" do
    result = discover(query: "kill switch status")

    expect(result[:success]).to be(true)
    hit = result[:data][:tools].find { |entry| entry[:name] == "platform.kill_switch_status" }
    expect(hit).to include(family: "governance", read_only: true, destructive: false)
    expect(hit[:summary]).to be_present
    expect(hit[:summary]).not_to include("\n")
    expect(result[:data][:describe_with]).to include("platform.describe_tool")
  end

  it "publishes the destructive hint from the declaration" do
    hit = discover(query: "emergency halt")[:data][:tools].find { |entry| entry[:name] == "platform.emergency_halt" }

    expect(hit).to include(read_only: false, destructive: true)
  end

  it "answers only platform registry actions, never agents or MCP-server rows" do
    create(:ai_agent, account: account, name: "Halt Helper", description: "emergency halt helper", status: "active")

    names = discover(query: "emergency halt", limit: 25)[:data][:tools].map { |entry| entry[:name] }

    expect(names).to all(start_with("platform."))
  end

  it "narrows to one declared family" do
    tools = discover(query: "list", family: "docker", limit: 25)[:data][:tools]

    expect(tools).not_to be_empty
    expect(tools.map { |entry| entry[:family] }.uniq).to eq([ "docker" ])
  end

  it "narrows to read-only verbs, and to writes" do
    reads = discover(query: "skill", read_only: true, limit: 25)[:data][:tools]
    writes = discover(query: "skill", read_only: "false", limit: 25)[:data][:tools]

    expect(reads).not_to be_empty
    expect(writes).not_to be_empty
    expect(reads.map { |entry| entry[:read_only] }.uniq).to eq([ true ])
    expect(writes.map { |entry| entry[:read_only] }.uniq).to eq([ false ])
  end

  it "caps the answer at limit, ten by default" do
    expect(discover(query: "list")[:data][:tools].size).to eq(10)
    expect(discover(query: "list", limit: 3)[:data][:tools].size).to eq(3)
  end

  it "refuses a missing query and an unknown family by name" do
    expect(discover(query: " ")).to include(success: false)

    unknown = discover(query: "list", family: "no_such_family")
    expect(unknown[:success]).to be(false)
    expect(unknown[:error]).to include("docker")
  end

  it "ranks by embedding similarity when embeddings are available" do
    provider = instance_double(Ai::Memory::EmbeddingService)
    allow(provider).to receive(:generate) { |text| text.to_s.include?("halt") ? [ 1.0, 0.0 ] : [ 0.0, 1.0 ] }
    allow_any_instance_of(Ai::Tools::SemanticToolDiscoveryService)
      .to receive(:find_embedding_provider).and_return(provider)

    names = discover(query: "stop everything now halt", limit: 3)[:data][:tools].map { |entry| entry[:name] }

    expect(names).to include("platform.emergency_halt")
  end

  # Scoped like tools/list and describe_tool: a restricted principal must not
  # learn the names of verbs outside its grant through discovery.
  context "for an instance principal" do
    before { ::Mcp::Principal.tool_grant_resolver = ->(_instance) { [ "platform.kill_switch_status" ] } }
    after { ::Mcp::Principal.reset! }

    it "answers only names inside the grant (plus the bootstrap floor)" do
      tool.node_instance = double("NodeInstance", id: "11111111-1111-7111-8111-111111111111")
      tool.instance_authorized = true

      names = discover(query: "emergency halt kill switch", limit: 25)[:data][:tools].map { |entry| entry[:name] }

      expect(names).to include("platform.kill_switch_status")
      expect(names).not_to include("platform.emergency_halt")
    end
  end
end
