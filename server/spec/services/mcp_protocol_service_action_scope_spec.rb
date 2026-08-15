# frozen_string_literal: true

require "rails_helper"

# IMP-3024cfb1d850 — the action-scope fence (IMP-e8138c2714fb) guards ONE of the
# two entry points into Ai::Tools::McpPlatformToolRegistrar.execute_tool.
#
# Door 1: Api::V1::Mcp::StreamableHttpController#handle_tools_call routes a
#   "platform."-prefixed name straight to the registrar, passing
#   instance_authorized — so the fence runs.
#
# Door 2: any OTHER name falls to Mcp::ProtocolService#invoke_tool, whose
#   registry lookup resolves it through a name→ID index keyed on the UNPREFIXED
#   manifest name (Mcp::RegistryService#get_tool). A "platform_tool" manifest
#   then reaches the same registrar via #execute_tool_by_type — which passed
#   neither a principal nor instance_authorized, so the fence never ran and a
#   caller-supplied :action executed unchecked.
#
# Five tool classes have REQUIRED_PERMISSION == nil, so enforce_permission!
# returns without checking anything: on door 2 they had NO gate on the action at
# all. These examples are the contract that both doors refuse the same thing.
#
# AgentAutonomyTool was the sixth and is the exemplar these examples used to
# reach for. It now carries a floor plus a per-action map (IMP-e8adfcfcab9b), so
# a principal-less call to it is refused EARLIER — by enforce_permission!'s
# authentication raise, above the fence — and it can no longer stand in for a
# class the fence is the only bound on. ProvisioningTool takes that role here;
# AgentAutonomyTool keeps its own coverage below in the shape it is actually
# called in.
#
# Door 2 is INERT at runtime today, and these examples reach it by calling
# #execute_tool_by_type directly for that reason: #invoke_tool hard-denies
# user.nil? (protocol_service.rb:230-232) before the branch, and an instance
# principal always has current_user nil. So this is insurance for the next call
# site, not a live hole being closed — it fires the day that deny is relaxed.
#
# What is NOT the barrier is the registry: an agent's mcp_tool_manifest is
# mass-assignable through the agents API (ai/agent_helpers.rb agent_params /
# agent_update_params), and RegistryService#load_existing_tools indexes every
# active agent's manifest by name with no check on "type" — so a manifest
# declaring "platform_tool" can reach @tools by that route.
RSpec.describe "MCP platform-tool action scope (both entry points)", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:protocol_service) { Mcp::ProtocolService.new(account: account) }
  let(:registrar) { Ai::Tools::McpPlatformToolRegistrar }

  before do
    registrar.instance_variable_set(:@tool_classes, nil)
  end

  # Drive door 2 exactly as invoke_tool does: the real manifest the registry
  # holds, and the real execution context invoke_tool builds.
  def call_via_protocol_service(tool_class, params, options = {})
    manifest = registrar.send(:build_manifest, tool_class)
    tool_id = manifest["name"]
    context = protocol_service.send(:build_execution_context, tool_id, params, options)
    protocol_service.send(:execute_tool_by_type, manifest, params, context)
  end

  describe "door 2: Mcp::ProtocolService#execute_tool_by_type" do
    let(:provisioning_tool) { instance_double(Ai::Tools::ProvisioningTool) }

    before do
      allow(Ai::Tools::ProvisioningTool).to receive(:new)
        .with(account: account, user: nil, agent: nil).and_return(provisioning_tool)
      allow(provisioning_tool).to receive(:instance_authorized=)
      allow(provisioning_tool).to receive(:node_instance=)
      allow(provisioning_tool).to receive(:execute).and_return({ success: true })
    end

    it "refuses a caller-supplied action from a principal-less call" do
      # ProvisioningTool::REQUIRED_PERMISSION is nil and this call carries no
      # user and no agent, so nothing downstream bounds the action: without the
      # fence, "platform_provisioning_capture_brief" simply runs.
      expect(Ai::Tools::ProvisioningTool::REQUIRED_PERMISSION).to be_nil

      expect {
        call_via_protocol_service(
          Ai::Tools::ProvisioningTool,
          { "action" => "platform_provisioning_capture_brief", "description" => "x" }
        )
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /platform_provisioning_capture_brief/)

      expect(provisioning_tool).not_to have_received(:execute)
    end

    # AgentAutonomyTool now refuses this call one layer higher — the floor's
    # authentication raise — so the fence is no longer what stops it. Pinned
    # because "refused by something else" is exactly how a fence quietly stops
    # being tested.
    it "refuses a principal-less call to AgentAutonomyTool at the permission floor" do
      autonomy_tool = instance_double(Ai::Tools::AgentAutonomyTool)
      allow(Ai::Tools::AgentAutonomyTool).to receive(:new).and_return(autonomy_tool)
      allow(autonomy_tool).to receive(:execute).and_return({ success: true })

      expect {
        call_via_protocol_service(
          Ai::Tools::AgentAutonomyTool,
          { "action" => "request_code_change", "description" => "x" }
        )
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /Authentication required/)

      expect(autonomy_tool).not_to have_received(:execute)
    end

    it "covers every tool class whose REQUIRED_PERMISSION is nil" do
      # The five multi-action classes that enforce_permission! waves through.
      # Each is invoked under its own manifest name with a foreign action.
      # AgentAutonomyTool left this set in IMP-e8adfcfcab9b.
      no_permission_classes = [
        Ai::Tools::ProvisioningTool,
        Ai::Tools::AgentMemoryManagementTool,
        Ai::Tools::SelfImprovementTool,
        Ai::Tools::GovernanceTool,
        Ai::Tools::CoordinationTool
      ]

      no_permission_classes.each do |tool_class|
        expect(tool_class::REQUIRED_PERMISSION).to(
          be_nil, "expected #{tool_class} to have no REQUIRED_PERMISSION"
        )

        double = instance_double(tool_class)
        allow(tool_class).to receive(:new)
          .with(account: account, user: nil, agent: nil).and_return(double)
        allow(double).to receive(:instance_authorized=)
        allow(double).to receive(:node_instance=)
        allow(double).to receive(:execute).and_return({ success: true })

        expect {
          call_via_protocol_service(tool_class, { "action" => "some_sibling_action" })
        }.to raise_error(
          ::Mcp::ProtocolService::PermissionDeniedError,
          /some_sibling_action/
        ), "expected #{tool_class} to pin the executed action to its tool name"

        expect(double).not_to have_received(:execute)
      end
    end

    it "leaves the user-principal path on this door unchanged" do
      # A user is bounded by the tool's own per-action permission map, which
      # reads the same caller-supplied action — that path must not change shape.
      autonomy_for_user = instance_double(Ai::Tools::AgentAutonomyTool)
      allow(Ai::Tools::AgentAutonomyTool).to receive(:new)
        .with(account: account, user: user, agent: nil).and_return(autonomy_for_user)
      allow(autonomy_for_user).to receive(:execute).and_return({ success: true })

      call_via_protocol_service(
        Ai::Tools::AgentAutonomyTool,
        { "action" => "list_agent_goals" },
        { user: user }
      )

      expect(autonomy_for_user).to have_received(:execute) do |args|
        expect(args[:params][:action]).to eq("list_agent_goals")
      end
    end

    it "still injects the action when the caller supplies none" do
      single = instance_double(Ai::Tools::IntegrationHealthTool)
      allow(Ai::Tools::IntegrationHealthTool).to receive(:new)
        .with(account: account, user: nil, agent: nil).and_return(single)
      allow(single).to receive(:instance_authorized=)
      allow(single).to receive(:execute).and_return({ success: true })

      call_via_protocol_service(Ai::Tools::IntegrationHealthTool, {})

      expect(single).to have_received(:execute)
    end
  end

  describe "both doors agree" do
    let(:provisioning_tool) { instance_double(Ai::Tools::ProvisioningTool) }
    let(:smuggled) { { "action" => "platform_provisioning_capture_brief", "description" => "x" } }

    before do
      allow(Ai::Tools::ProvisioningTool).to receive(:new)
        .with(account: account, user: nil, agent: nil).and_return(provisioning_tool)
      allow(provisioning_tool).to receive(:instance_authorized=)
      allow(provisioning_tool).to receive(:node_instance=)
      allow(provisioning_tool).to receive(:execute).and_return({ success: true })
    end

    it "refuses the same smuggled action through the registrar and through the protocol service" do
      door_1 = nil
      door_2 = nil

      begin
        registrar.execute_tool(
          "platform.provisioning",
          params: smuggled,
          account: account,
          user: nil,
          instance_authorized: true
        )
      rescue ::Mcp::ProtocolService::PermissionDeniedError => e
        door_1 = e
      end

      begin
        call_via_protocol_service(Ai::Tools::ProvisioningTool, smuggled)
      rescue ::Mcp::ProtocolService::PermissionDeniedError => e
        door_2 = e
      end

      expect(door_1).to be_a(::Mcp::ProtocolService::PermissionDeniedError)
      expect(door_2).to be_a(::Mcp::ProtocolService::PermissionDeniedError)
      expect(door_2.message).to eq(door_1.message)
      expect(provisioning_tool).not_to have_received(:execute)
    end
  end
end
