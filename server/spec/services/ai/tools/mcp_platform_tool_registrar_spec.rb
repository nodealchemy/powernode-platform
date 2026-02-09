# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::McpPlatformToolRegistrar do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    # Reset memoized tool_classes between tests
    described_class.instance_variable_set(:@tool_classes, nil)
  end

  describe ".register_all!" do
    it "registers all unique tool classes to the MCP registry" do
      registry = instance_double(::Mcp::RegistryService)
      allow(::Mcp::RegistryService).to receive(:new).with(account: account).and_return(registry)
      allow(registry).to receive(:register_tool)

      described_class.register_all!(account: account)

      unique_tools = Ai::Tools::PlatformApiToolRegistry::TOOLS.values.uniq
      expect(registry).to have_received(:register_tool).exactly(unique_tools.size).times
    end

    it "registers tools with string keys and valid manifest structure" do
      registry = instance_double(::Mcp::RegistryService)
      allow(::Mcp::RegistryService).to receive(:new).with(account: account).and_return(registry)

      registered_manifests = []
      allow(registry).to receive(:register_tool) do |tool_id, manifest|
        registered_manifests << { id: tool_id, manifest: manifest }
      end

      described_class.register_all!(account: account)

      registered_manifests.each do |entry|
        expect(entry[:id]).to start_with("platform.")
        manifest = entry[:manifest]
        expect(manifest).to have_key("name")
        expect(manifest).to have_key("description")
        expect(manifest).to have_key("type")
        expect(manifest).to have_key("version")
        expect(manifest).to have_key("inputSchema")
        expect(manifest).to have_key("outputSchema")
        expect(manifest["type"]).to eq("platform_tool")
        expect(manifest["version"]).to eq("1.0.0")
      end
    end

    it "includes required_permissions in manifest" do
      registry = instance_double(::Mcp::RegistryService)
      allow(::Mcp::RegistryService).to receive(:new).with(account: account).and_return(registry)

      registered_manifests = {}
      allow(registry).to receive(:register_tool) do |tool_id, manifest|
        registered_manifests[tool_id] = manifest
      end

      described_class.register_all!(account: account)

      agent_manifest = registered_manifests["platform.agent_management"]
      expect(agent_manifest["required_permissions"]).to eq(["ai.agents.execute"])
    end

    it "silently handles ToolConflictError for already-registered tools" do
      registry = instance_double(::Mcp::RegistryService)
      allow(::Mcp::RegistryService).to receive(:new).with(account: account).and_return(registry)
      allow(registry).to receive(:register_tool)
        .and_raise(::Mcp::RegistryService::ToolConflictError, "already exists")

      expect { described_class.register_all!(account: account) }.not_to raise_error
    end

    it "logs warnings for other registration failures" do
      registry = instance_double(::Mcp::RegistryService)
      allow(::Mcp::RegistryService).to receive(:new).with(account: account).and_return(registry)
      allow(registry).to receive(:register_tool)
        .and_raise(StandardError, "unexpected error")

      expect(Rails.logger).to receive(:warn).at_least(:once)
        .with(/Failed to register/)

      described_class.register_all!(account: account)
    end
  end

  describe ".execute_tool" do
    let(:tool_instance) { instance_double(Ai::Tools::AgentManagementTool) }

    before do
      allow(Ai::Tools::AgentManagementTool).to receive(:new)
        .with(account: account).and_return(tool_instance)
    end

    it "routes to the correct tool class and returns result" do
      expected_result = { success: true, agents: [] }
      allow(tool_instance).to receive(:execute)
        .with(params: { action: "list_agents" })
        .and_return(expected_result)

      allow(user).to receive(:has_permission?).with("ai.agents.execute").and_return(true)

      result = described_class.execute_tool(
        "platform.agent_management",
        params: { "action" => "list_agents" },
        account: account,
        user: user
      )

      expect(result).to eq(expected_result)
    end

    it "symbolizes string param keys before calling execute" do
      allow(user).to receive(:has_permission?).with("ai.agents.execute").and_return(true)
      allow(tool_instance).to receive(:execute) do |args|
        expect(args[:params].keys).to all(be_a(Symbol))
        { success: true }
      end

      described_class.execute_tool(
        "platform.agent_management",
        params: { "action" => "list_agents", "name" => "test" },
        account: account,
        user: user
      )
    end

    context "permission enforcement" do
      it "raises PermissionDeniedError when user lacks required permission" do
        allow(user).to receive(:has_permission?).with("ai.agents.execute").and_return(false)

        expect {
          described_class.execute_tool(
            "platform.agent_management",
            params: { "action" => "list_agents" },
            account: account,
            user: user
          )
        }.to raise_error(
          ::Mcp::ProtocolService::PermissionDeniedError,
          /requires 'ai.agents.execute'/
        )
      end

      it "raises PermissionDeniedError when no user is provided" do
        expect {
          described_class.execute_tool(
            "platform.agent_management",
            params: { "action" => "list_agents" },
            account: account,
            user: nil
          )
        }.to raise_error(
          ::Mcp::ProtocolService::PermissionDeniedError,
          /Authentication required/
        )
      end
    end

    it "raises ArgumentError for unknown tool" do
      expect {
        described_class.execute_tool(
          "platform.nonexistent_tool",
          params: {},
          account: account,
          user: user
        )
      }.to raise_error(ArgumentError, /Unknown platform tool/)
    end

    context "rate limiting" do
      let(:agent_id) { SecureRandom.uuid }

      before do
        allow(user).to receive(:has_permission?).with("ai.agents.execute").and_return(true)
        allow(tool_instance).to receive(:execute).and_return({ success: true })
      end

      it "applies rate limiting when agent_id is provided" do
        allow(Ai::Introspection::RateLimiter).to receive(:check!)

        described_class.execute_tool(
          "platform.agent_management",
          params: { "action" => "list_agents" },
          account: account,
          user: user,
          agent_id: agent_id
        )

        expect(Ai::Introspection::RateLimiter).to have_received(:check!).with(
          agent_id: agent_id,
          max_calls: Ai::Tools::BaseTool::MAX_CALLS_PER_EXECUTION,
          window: 60
        )
      end

      it "skips rate limiting when no agent_id" do
        allow(Ai::Introspection::RateLimiter).to receive(:check!)

        described_class.execute_tool(
          "platform.agent_management",
          params: { "action" => "list_agents" },
          account: account,
          user: user,
          agent_id: nil
        )

        expect(Ai::Introspection::RateLimiter).not_to have_received(:check!)
      end
    end
  end

  describe ".build_manifest (private)" do
    it "sets type to platform_tool" do
      manifest = described_class.send(:build_manifest, Ai::Tools::AgentManagementTool)
      expect(manifest["type"]).to eq("platform_tool")
    end

    it "includes required_permissions array" do
      manifest = described_class.send(:build_manifest, Ai::Tools::PipelineManagementTool)
      expect(manifest["required_permissions"]).to eq(["git.pipelines.manage"])
    end

    it "includes metadata with tool_class name" do
      manifest = described_class.send(:build_manifest, Ai::Tools::AgentManagementTool)
      expect(manifest["metadata"]["tool_class"]).to eq("Ai::Tools::AgentManagementTool")
    end
  end

  describe ".convert_to_json_schema (private)" do
    it "correctly maps required and optional parameters" do
      params = {
        action: { type: "string", required: true, description: "The action" },
        name: { type: "string", required: false, description: "The name" }
      }

      schema = described_class.send(:convert_to_json_schema, params)

      expect(schema["type"]).to eq("object")
      expect(schema["properties"]["action"]["type"]).to eq("string")
      expect(schema["properties"]["action"]["description"]).to eq("The action")
      expect(schema["properties"]["name"]["type"]).to eq("string")
      expect(schema["required"]).to eq(["action"])
      expect(schema["required"]).not_to include("name")
    end

    it "returns empty schema for nil parameters" do
      schema = described_class.send(:convert_to_json_schema, nil)

      expect(schema["type"]).to eq("object")
      expect(schema["properties"]).to eq({})
      expect(schema["required"]).to eq([])
    end
  end
end
