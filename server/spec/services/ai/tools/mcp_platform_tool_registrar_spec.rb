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

      unique_tools = Ai::Tools::PlatformApiToolRegistry.all_tools.values.uniq
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
        .with(account: account, user: user, agent: nil).and_return(tool_instance)
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

    it "allows indifferent access to param keys before calling execute" do
      allow(user).to receive(:has_permission?).with("ai.agents.execute").and_return(true)
      allow(tool_instance).to receive(:execute) do |args|
        params = args[:params]
        expect(params).to respond_to(:with_indifferent_access)
        expect(params[:action]).to eq("list_agents")
        expect(params["action"]).to eq("list_agents")
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

      it "skips the user-permission check for a grant-authorized instance principal (BUG-R)" do
        # Instance principals (mTLS node cert, user: nil) are already may_invoke?-gated
        # by the streamable controller before this call; instance_authorized: true lets
        # them through instead of the user:nil hard-deny above.
        # Invoked by its FLATTENED name — the only shape an instance's catalog
        # advertises, and the one its grant is written against (IMP-e8138c2714fb).
        allow(Ai::Tools::AgentManagementTool).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(tool_instance)
        allow(tool_instance).to receive(:execute).and_return({ success: true })
        allow(tool_instance).to receive(:instance_authorized=)

        expect {
          described_class.execute_tool(
            "platform.list_agents",
            params: { "action" => "list_agents" },
            account: account,
            user: nil,
            instance_authorized: true
          )
        }.not_to raise_error

        # The grant-gate verdict must reach the tool: a tool whose own
        # per-action gate has to tell an instance principal apart from a bare
        # userless caller can only do so if this is set. (IMP-9030413bc292)
        expect(tool_instance).to have_received(:instance_authorized=).with(true)
      end

      it "does NOT mark user/agent-principal calls as instance-authorized (IMP-9030413bc292)" do
        allow(user).to receive(:has_permission?).with("ai.agents.execute").and_return(true)
        allow(tool_instance).to receive(:execute).and_return({ success: true })
        allow(tool_instance).to receive(:instance_authorized=)

        described_class.execute_tool(
          "platform.agent_management",
          params: { "action" => "list_agents" },
          account: account,
          user: user
        )

        expect(tool_instance).not_to have_received(:instance_authorized=)
      end
    end

    # IMP-e8138c2714fb — the action was injected only when the caller had not
    # supplied one, so a caller-supplied :action won. An instance principal
    # granted a benign flattened tool could name a DESTRUCTIVE SIBLING action on
    # the same tool class and reach it: may_invoke? had already passed against
    # the benign TOOL NAME, enforce_permission! returns early on
    # instance_authorized, and the tool's own per-action map is skipped for a
    # grant-gated instance. One argument defeated both the deny overlay and the
    # per-action permission map.
    context "caller-supplied action scope (instance principals)" do
      let(:memory_tool) { instance_double(Ai::Tools::MemoryTool) }

      before do
        allow(Ai::Tools::MemoryTool).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(memory_tool)
        allow(memory_tool).to receive(:instance_authorized=)
        allow(memory_tool).to receive(:execute).and_return({ success: true })
      end

      it "refuses an action that disagrees with the grant-checked tool name" do
        expect {
          described_class.execute_tool(
            "platform.read_shared_memory",
            params: { "action" => "delete_shared_memory", "pool_id" => "default", "key" => "k" },
            account: account,
            user: nil,
            instance_authorized: true
          )
        }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /delete_shared_memory/)

        expect(memory_tool).not_to have_received(:execute)
      end

      it "refuses it even though the deny overlay could never have granted that sibling by name" do
        # Pins WHY the escape mattered: delete_shared_memory is destroy-shaped, so
        # no grant — however broad — can reach it by name. Only the smuggled
        # action could.
        expect(::Mcp::Principal.destructive_tool?("platform.delete_shared_memory")).to be(true)
        expect(::Mcp::Principal.destructive_tool?("platform.read_shared_memory")).to be(false)
      end

      it "allows an action that agrees with the invoked tool name" do
        described_class.execute_tool(
          "platform.read_shared_memory",
          params: { "action" => "read_shared_memory", "key" => "k" },
          account: account,
          user: nil,
          instance_authorized: true
        )

        expect(memory_tool).to have_received(:execute)
      end

      it "allows the aliased internal action name for a renamed registry key" do
        kg_tool = instance_double(Ai::Tools::KnowledgeGraphTool)
        allow(Ai::Tools::KnowledgeGraphTool).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(kg_tool)
        allow(kg_tool).to receive(:instance_authorized=)
        allow(kg_tool).to receive(:execute).and_return({ success: true })

        described_class.execute_tool(
          "platform.search_knowledge_graph",
          params: { "action" => "search", "query" => "x" },
          account: account,
          user: nil,
          instance_authorized: true
        )

        expect(kg_tool).to have_received(:execute)
      end

      it "refuses a sibling alias that belongs to a different registry key" do
        kg_tool = instance_double(Ai::Tools::KnowledgeGraphTool)
        allow(Ai::Tools::KnowledgeGraphTool).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(kg_tool)
        allow(kg_tool).to receive(:instance_authorized=)
        allow(kg_tool).to receive(:execute).and_return({ success: true })

        expect {
          described_class.execute_tool(
            "platform.search_knowledge_graph",
            params: { "action" => "list_nodes" },
            account: account,
            user: nil,
            instance_authorized: true
          )
        }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError)

        expect(kg_tool).not_to have_received(:execute)
      end

      it "keeps the dev-loop instance path working (no action supplied — still injected)" do
        dev_tool = instance_double(Ai::Tools::DevLoopTool)
        allow(Ai::Tools::DevLoopTool).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(dev_tool)
        allow(dev_tool).to receive(:instance_authorized=)
        allow(dev_tool).to receive(:node_instance=)
        allow(dev_tool).to receive(:execute).and_return({ success: true })

        described_class.execute_tool(
          "platform.dev_next_task",
          params: { "loop_id" => "loop-1" },
          account: account,
          user: nil,
          instance_authorized: true
        )

        expect(dev_tool).to have_received(:execute) do |args|
          expect(args[:params][:action]).to eq("dev_next_task")
        end
      end

      it "requires EXACT agreement — a longer sibling that merely CONTAINS the granted name is refused" do
        # Guards the comparison itself, which nothing else here pins: relaxing
        # `==` to a substring test passes every other example, because the
        # destructive deny overlay independently blocks the grantable side of
        # each destroy-shaped pair. It would still silently widen ~23
        # same-class pairs whose names nest — system_create_provider ->
        # system_create_provider_connection, get_ralph_loop ->
        # get_ralph_loop_statistics. BOTH names below are non-destructive, so
        # the overlay cannot refuse this one; only exact equality can.
        ralph_tool = instance_double(Ai::Tools::RalphLoopTool)
        allow(Ai::Tools::RalphLoopTool).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(ralph_tool)
        allow(ralph_tool).to receive(:instance_authorized=)
        allow(ralph_tool).to receive(:execute).and_return({ success: true })

        expect(::Mcp::Principal.destructive_tool?("platform.get_ralph_loop")).to be(false)
        expect(::Mcp::Principal.destructive_tool?("platform.get_ralph_loop_statistics")).to be(false)

        expect {
          described_class.execute_tool(
            "platform.get_ralph_loop",
            params: { "action" => "get_ralph_loop_statistics", "loop_id" => "l-1" },
            account: account,
            user: nil,
            instance_authorized: true
          )
        }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError)

        expect(ralph_tool).not_to have_received(:execute)
      end

      it "refuses a CLASS-LEVEL tool name, which names no action at all" do
        # "platform.agent_management" is the tool class's own definition[:name],
        # reachable only through find_tool_class's fallback — tools/list
        # advertises registry keys only. It maps to NO action, so may_invoke?
        # against it tells you nothing about what will run: it is the escape in
        # its purest form (delete_agent is destroy-shaped and would be denied by
        # name, but "agent_management" is not). Instances get flattened names.
        agent_tool = instance_double(Ai::Tools::AgentManagementTool)
        allow(Ai::Tools::AgentManagementTool).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(agent_tool)
        allow(agent_tool).to receive(:instance_authorized=)
        allow(agent_tool).to receive(:execute).and_return({ success: true })

        expect(::Mcp::Principal.destructive_tool?("platform.delete_agent")).to be(true)
        expect(::Mcp::Principal.destructive_tool?("platform.agent_management")).to be(false)

        expect {
          described_class.execute_tool(
            "platform.agent_management",
            params: { "action" => "delete_agent", "agent_id" => "a-1" },
            account: account,
            user: nil,
            instance_authorized: true
          )
        }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError)

        expect(agent_tool).not_to have_received(:execute)
      end

      it "leaves the USER principal path unchanged — a mismatching action still runs" do
        # Users are bounded by the per-action permission map inside the tool, so
        # this path must not change shape. Byte-identical behavior is the point.
        allow(Ai::Tools::MemoryTool).to receive(:new)
          .with(account: account, user: user, agent: nil).and_return(memory_tool)
        allow(user).to receive(:has_permission?).with("ai.agents.read").and_return(true)

        described_class.execute_tool(
          "platform.read_shared_memory",
          params: { "action" => "delete_shared_memory", "key" => "k" },
          account: account,
          user: user
        )

        expect(memory_tool).to have_received(:execute) do |args|
          expect(args[:params][:action]).to eq("delete_shared_memory")
        end
      end
    end

    # IMP-3024cfb1d850 — the fence above was opt-in on instance_authorized, so
    # the OTHER entry point into this method (Mcp::ProtocolService's
    # platform_tool branch, which passes no principal at all) never ran it. The
    # trigger is now the principal itself: a call with nothing downstream
    # bounding the action it runs is pinned to the name it invoked, so a call
    # site that omits the flag tightens instead of opening a door. Both entry
    # points are held to this in
    # spec/services/mcp_protocol_service_action_scope_spec.rb.
    context "caller-supplied action scope (principal-less calls)" do
      let(:autonomy_tool) { instance_double(Ai::Tools::AgentAutonomyTool) }

      before do
        allow(Ai::Tools::AgentAutonomyTool).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(autonomy_tool)
        allow(autonomy_tool).to receive(:instance_authorized=)
        allow(autonomy_tool).to receive(:execute).and_return({ success: true })
      end

      it "pins the action for a call carrying neither a user nor an agent" do
        # REQUIRED_PERMISSION is nil here, so enforce_permission! waves the call
        # through without checking anything — the invoked name is the only bound
        # left on what runs.
        expect(Ai::Tools::AgentAutonomyTool::REQUIRED_PERMISSION).to be_nil

        expect {
          described_class.execute_tool(
            "platform.agent_autonomy",
            params: { "action" => "request_code_change" },
            account: account,
            user: nil
          )
        }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /request_code_change/)

        expect(autonomy_tool).not_to have_received(:execute)
      end

      it "leaves the agent tool-calling path unpinned even when the agent has no creator" do
        # AgentToolBridgeService passes user: agent.creator — nil for an agent
        # with no creator — alongside mcp_agent. An agent legitimately supplies
        # :action for a class that declares one, so this path must keep running
        # it rather than falling into the principal-less pin.
        agent = instance_double(Ai::Agent)
        allow(Ai::Tools::AgentAutonomyTool).to receive(:new)
          .with(account: account, user: nil, agent: agent).and_return(autonomy_tool)

        described_class.execute_tool(
          "platform.agent_autonomy",
          params: { "action" => "list_agent_goals" },
          account: account,
          user: nil,
          mcp_agent: agent
        )

        expect(autonomy_tool).to have_received(:execute) do |args|
          expect(args[:params][:action]).to eq("list_agent_goals")
        end
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
