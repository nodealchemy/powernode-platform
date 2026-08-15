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
# A tool class whose REQUIRED_PERMISSION is nil makes enforce_permission! return
# without checking anything, so on door 2 there is NO gate on the action at all
# and the fence is the only bound. These examples are the contract that both
# doors refuse the same thing.
#
# NO core class plays that role any more. AgentAutonomyTool left the set in
# IMP-e8adfcfcab9b, and the remaining five (ProvisioningTool,
# AgentMemoryManagementTool, SelfImprovementTool, GovernanceTool,
# CoordinationTool) left it in IMP-6fbfeff384fa — each now carries a floor, so a
# principal-less call is refused EARLIER, by enforce_permission!'s authentication
# raise ABOVE the fence. That is a strictly better outcome and it is pinned
# below, but it would also have quietly retired this fence's only oracle: every
# example here would still pass, for a reason that has nothing to do with the
# fence. So the fence is now exercised through a purpose-built stub class
# (FenceProbeTool) that has the property under test — nil permission, several
# actions — instead of borrowing whichever real class happened to have it.
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

  # The stand-in for "a multi-action tool class the registrar waves through":
  # REQUIRED_PERMISSION nil (inherited), an :action parameter so
  # action_dispatched? is true, and more than one action to smuggle between.
  # Registered into the registry the same way a real tool is, so resolution,
  # manifest building and dispatch all run unmodified.
  before do
    stub_const("Ai::Tools::FenceProbeTool", Class.new(::Ai::Tools::BaseTool) do
      def self.definition
        {
          name: "fence_probe",
          description: "spec-only probe for the action-scope fence",
          parameters: { action: { type: "string", required: true } }
        }
      end

      def self.action_definitions
        {
          "fence_probe_read" => { description: "read", parameters: {} },
          "fence_probe_write" => { description: "write", parameters: {} }
        }
      end
    end)

    allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:all_tools).and_wrap_original do |original|
      original.call.merge(
        "fence_probe" => "Ai::Tools::FenceProbeTool",
        "fence_probe_read" => "Ai::Tools::FenceProbeTool",
        "fence_probe_write" => "Ai::Tools::FenceProbeTool"
      )
    end

    registrar.instance_variable_set(:@tool_classes, nil)
  end

  after do
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
    let(:probe_tool) { instance_double(Ai::Tools::FenceProbeTool) }

    before do
      allow(Ai::Tools::FenceProbeTool).to receive(:new)
        .with(account: account, user: nil, agent: nil).and_return(probe_tool)
      allow(probe_tool).to receive(:instance_authorized=)
      allow(probe_tool).to receive(:node_instance=)
      allow(probe_tool).to receive(:execute).and_return({ success: true })
    end

    it "refuses a caller-supplied action from a principal-less call" do
      # FenceProbeTool::REQUIRED_PERMISSION is nil and this call carries no user
      # and no agent, so nothing downstream bounds the action: without the fence,
      # "fence_probe_write" simply runs.
      expect(Ai::Tools::FenceProbeTool::REQUIRED_PERMISSION).to be_nil

      expect {
        call_via_protocol_service(
          Ai::Tools::FenceProbeTool,
          { "action" => "fence_probe_write" }
        )
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /fence_probe_write/)

      expect(probe_tool).not_to have_received(:execute)
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

    # The five classes this spec used to enumerate as "waved through" were fixed
    # in IMP-6fbfeff384fa. They are still worth driving down door 2 — but the
    # property they now demonstrate is the opposite one: a principal-less call is
    # refused at the FLOOR, above the fence.
    it "refuses a principal-less call to each former nil-permission class at its floor" do
      [
        Ai::Tools::ProvisioningTool,
        Ai::Tools::AgentMemoryManagementTool,
        Ai::Tools::SelfImprovementTool,
        Ai::Tools::GovernanceTool,
        Ai::Tools::CoordinationTool
      ].each do |tool_class|
        expect(tool_class::REQUIRED_PERMISSION).to(
          be_present, "expected #{tool_class} to declare a permission floor"
        )

        double = instance_double(tool_class)
        allow(tool_class).to receive(:new).and_return(double)
        allow(double).to receive(:instance_authorized=)
        allow(double).to receive(:node_instance=)
        allow(double).to receive(:execute).and_return({ success: true })

        expect {
          call_via_protocol_service(tool_class, { "action" => "some_sibling_action" })
        }.to raise_error(
          ::Mcp::ProtocolService::PermissionDeniedError,
          /Authentication required/
        ), "expected #{tool_class} to refuse a principal-less call at its floor"

        expect(double).not_to have_received(:execute)
      end
    end

    # The generalisation of that fix, and the guard that matters going forward: a
    # NEW multi-action tool added without a REQUIRED_PERMISSION reopens exactly
    # the hole IMP-e8adfcfcab9b and IMP-6fbfeff384fa closed, and nothing else in
    # the suite would notice. Single-action classes are exempt: they cannot
    # smuggle a sibling action, and IntegrationHealthTool sets nil deliberately.
    it "leaves no action-dispatched tool class waved through enforce_permission!" do
      waved = registrar.send(:tool_classes).select do |tool_class|
        next false if tool_class == Ai::Tools::FenceProbeTool

        registrar.send(:action_dispatched?, tool_class) && tool_class::REQUIRED_PERMISSION.nil?
      end

      expect(waved).to be_empty,
                       "multi-action tools with no REQUIRED_PERMISSION: #{waved.map(&:name).join(', ')}"
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

  # Driven through the probe class for the same reason as above: with a floor in
  # place the two doors refuse at DIFFERENT layers (door 1 carries
  # instance_authorized, which enforce_permission! honours before the
  # authentication raise; door 2 carries no principal and is refused by that
  # raise), so a real class can no longer show that the FENCE's two refusals
  # agree. The probe keeps both doors landing on the fence.
  describe "both doors agree" do
    let(:probe_tool) { instance_double(Ai::Tools::FenceProbeTool) }
    let(:smuggled) { { "action" => "fence_probe_write" } }

    before do
      allow(Ai::Tools::FenceProbeTool).to receive(:new)
        .with(account: account, user: nil, agent: nil).and_return(probe_tool)
      allow(probe_tool).to receive(:instance_authorized=)
      allow(probe_tool).to receive(:node_instance=)
      allow(probe_tool).to receive(:execute).and_return({ success: true })
    end

    it "refuses the same smuggled action through the registrar and through the protocol service" do
      door_1 = nil
      door_2 = nil

      begin
        registrar.execute_tool(
          "platform.fence_probe",
          params: smuggled,
          account: account,
          user: nil,
          instance_authorized: true
        )
      rescue ::Mcp::ProtocolService::PermissionDeniedError => e
        door_1 = e
      end

      begin
        call_via_protocol_service(Ai::Tools::FenceProbeTool, smuggled)
      rescue ::Mcp::ProtocolService::PermissionDeniedError => e
        door_2 = e
      end

      expect(door_1).to be_a(::Mcp::ProtocolService::PermissionDeniedError)
      expect(door_2).to be_a(::Mcp::ProtocolService::PermissionDeniedError)
      expect(door_2.message).to eq(door_1.message)
      expect(probe_tool).not_to have_received(:execute)
    end
  end
end
