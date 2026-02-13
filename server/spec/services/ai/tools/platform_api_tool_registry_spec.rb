# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::PlatformApiToolRegistry do
  let(:account) { create(:account) }

  describe "::TOOLS" do
    it "is a frozen hash" do
      expect(described_class::TOOLS).to be_frozen
    end

    it "maps tool names to class name strings" do
      described_class::TOOLS.each do |name, class_name|
        expect(name).to be_a(String)
        expect(class_name).to be_a(String)
        expect { class_name.constantize }.not_to raise_error
      end
    end

    it "includes expected tool entries" do
      expect(described_class::TOOLS).to include(
        "create_agent" => "Ai::Tools::AgentManagementTool",
        "list_agents" => "Ai::Tools::AgentManagementTool",
        "create_team" => "Ai::Tools::TeamManagementTool",
        "create_workflow" => "Ai::Tools::WorkflowManagementTool",
        "trigger_pipeline" => "Ai::Tools::PipelineManagementTool",
        "write_shared_memory" => "Ai::Tools::MemoryTool",
        "query_knowledge_base" => "Ai::Tools::KnowledgeTool",
        "get_api_reference" => "Ai::Tools::ApiReferenceTool",
        "dispatch_to_runner" => "Ai::Tools::RunnerDispatchTool",
        "create_gitea_repository" => "Ai::Tools::ProjectInitTool"
      )
    end
  end

  describe ".available_tools" do
    it "returns a hash of tool name to class" do
      tools = described_class.available_tools
      expect(tools).to be_a(Hash)
      tools.each do |name, klass|
        expect(name).to be_a(String)
        expect(klass).to be < Ai::Tools::BaseTool
      end
    end

    it "filters by agent permission when agent provided" do
      agent = create(:ai_agent, account: account)
      tools = described_class.available_tools(agent: agent)
      expect(tools).to be_a(Hash)
    end

    it "handles NameError for unavailable tool classes" do
      allow(Rails.logger).to receive(:warn)
      stub_const("Ai::Tools::PlatformApiToolRegistry::TOOLS", { "broken" => "Nonexistent::Tool" })

      tools = described_class.available_tools
      expect(tools).to eq({})
    end
  end

  describe ".find_tool" do
    it "returns the tool class for a known static tool" do
      klass = described_class.find_tool("create_agent")
      expect(klass).to eq(Ai::Tools::AgentManagementTool)
    end

    it "returns nil for an unknown tool" do
      klass = described_class.find_tool("nonexistent_tool")
      expect(klass).to be_nil
    end
  end

  describe ".tool_definitions" do
    it "returns an array of tool definitions with names" do
      definitions = described_class.tool_definitions
      expect(definitions).to be_an(Array)
      definitions.each do |defn|
        expect(defn).to have_key(:name)
        expect(defn).to have_key(:description)
        expect(defn).to have_key(:parameters)
      end
    end
  end

  describe ".discover_tools" do
    it "delegates to SemanticToolDiscoveryService" do
      service = instance_double(Ai::Tools::SemanticToolDiscoveryService)
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).with(account: account).and_return(service)
      allow(service).to receive(:discover).with(query: "deploy", capabilities: nil, limit: 10).and_return([])

      result = described_class.discover_tools(query: "deploy", account: account)
      expect(result).to eq([])
    end

    it "passes capabilities and limit" do
      service = instance_double(Ai::Tools::SemanticToolDiscoveryService)
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).with(account: account).and_return(service)
      allow(service).to receive(:discover).with(query: "test", capabilities: ["ci"], limit: 5).and_return([])

      described_class.discover_tools(query: "test", account: account, capabilities: ["ci"], limit: 5)
      expect(service).to have_received(:discover).with(query: "test", capabilities: ["ci"], limit: 5)
    end
  end

  describe ".register_dynamic_tool" do
    it "delegates to SemanticToolDiscoveryService" do
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:register_dynamic_tool).and_return({ id: "dynamic.test" })

      result = described_class.register_dynamic_tool(
        account: account, name: "test", description: "Test tool",
        parameters: {}, handler: "Ai::Tools::BaseTool"
      )
      expect(result[:id]).to eq("dynamic.test")
    end
  end

  describe ".unregister_dynamic_tool" do
    it "delegates to SemanticToolDiscoveryService" do
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:unregister_dynamic_tool)

      described_class.unregister_dynamic_tool(account: account, name: "test")
      expect(Ai::Tools::SemanticToolDiscoveryService).to have_received(:unregister_dynamic_tool).with(account: account, name: "test")
    end
  end

  describe ".dynamic_tools" do
    it "returns empty array when no account" do
      expect(described_class.dynamic_tools(account: nil)).to eq([])
    end

    it "reads from cache for the account" do
      cached = [{ name: "custom_tool", description: "Custom" }]
      allow(Rails.cache).to receive(:read).with("tool_discovery:#{account.id}:dynamic_tools").and_return(cached)

      result = described_class.dynamic_tools(account: account)
      expect(result).to eq(cached)
    end

    it "returns empty array when cache is empty" do
      allow(Rails.cache).to receive(:read).with("tool_discovery:#{account.id}:dynamic_tools").and_return(nil)

      result = described_class.dynamic_tools(account: account)
      expect(result).to eq([])
    end
  end
end
