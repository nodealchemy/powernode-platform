# frozen_string_literal: true

require "rails_helper"

# IMP-a33f7a833313 — a park made through a TOOL-SPECIFIC gate records the same
# principal block the generic park (BaseTool#deferred_tool_call_context) does.
#
# Before this, only DeferredToolCall parks carried `params["principal"]`, so an
# instance principal that parked a request through a bespoke gate_context (a
# sdwan gated result, a fleet gate context, the docker provisioning executor
# params) could never read it back: AgentAutonomyTool#get_approval_request
# fails closed on a row that names no principal. The stamp is ONE builder,
# Ai::Approvals::ParkPrincipal, applied at the chokepoint every declared gate
# passes (BaseTool#run_through_autonomy_gate) and at the hand-placed tool sites.
#
# These examples park through a BESPOKE gate context, never the generic one,
# and read back through the real MCP surface, so a stamp that stops covering
# tool-specific parks breaks the scoping here rather than passing unseen.
RSpec.describe "tool-specific gate parks record the originating principal" do
  let(:account) { create(:account) }
  let(:reader)  { create(:user, account: account, permissions: %w[ai.agents.read]) }
  let(:parker)  { create(:user, account: account, permissions: %w[ai.agents.read]) }

  let(:own_instance)   { Struct.new(:id).new(SecureRandom.uuid) }
  let(:other_instance) { Struct.new(:id).new(SecureRandom.uuid) }

  let(:not_found) { { success: false, error: "Approval request not found" } }

  before do
    ::Ai::InterventionPolicy.register_category!("spec.bespoke.write")
    ::Ai::InterventionPolicy.create!(
      account: account, action_category: "spec.bespoke.write",
      scope: "global", policy: "require_approval", priority: 5, is_active: true
    )
    stub_const("SpecBespokeExecutor", Class.new do
      def self.execute(_params, deferred_operation:) = { success: true }
      def self.preview(_params, deferred_operation: nil) = { summary: "bespoke" }
    end)
    stub_const("SpecBespokeTool", Class.new(::Ai::Tools::BaseTool) do
      def self.definition
        { name: "spec_bespoke_tool", description: "bespoke-gate probe",
          parameters: { action: { type: "string", required: false } } }
      end

      # A gate context of its OWN, the shape SdwanTool / SystemFleetTool /
      # DockerProvisioningTool use: executor params the tool assembles, with no
      # DeferredToolCall packing and (before the stamp) no principal at all.
      declare_action "spec_bespoke_write",
                     mutating: true,
                     action_category: "spec.bespoke.write",
                     executor_class: "SpecBespokeExecutor",
                     gate_context: :bespoke_gate_context,
                     on_proceed: :bespoke_done

      def bespoke_gate_context(params)
        executor_params = { widget_id: params[:widget_id].to_s }
        # A caller-influenced principal, in BOTH key shapes a hash can carry
        # into JSONB. The stamp must replace it, not fill in around it.
        if params[:spoof_as].present?
          spoof = { "kind" => "instance", "node_instance_id" => params[:spoof_as].to_s }
          executor_params = executor_params.merge("principal" => spoof, principal: spoof)
        end
        { executor_params: executor_params, description: "bespoke write" }
      end

      def bespoke_done(_params, _gate) = success_result(ran: true)

      def call(_params) = success_result(ran: true)
    end)
    SpecBespokeTool.const_set(:REQUIRED_PERMISSION, "ai.agents.read")
  end

  after { ::Mcp::Principal.reset! }

  def instance_tool(node_instance)
    tool = SpecBespokeTool.new(account: account, user: nil)
    tool.instance_authorized = true
    tool.node_instance = node_instance
    tool.call_origin = "mcp_instance"
    tool
  end

  def park!(tool, params = {})
    result = tool.execute(params: { action: "spec_bespoke_write", widget_id: "w-1" }.merge(params))
    expect(result).to include(success: true), result.inspect
    expect(result[:data]).to include(pending: true)
    ::Ai::DeferredOperation.find(result[:data][:deferred_operation_id])
  end

  def read_as_instance(operation, node_instance:)
    ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
      "platform.get_approval_request",
      params: { "deferred_operation_id" => operation.id },
      account: account, user: nil, instance_authorized: true, node_instance: node_instance
    )
  end

  describe "an instance park through a bespoke gate context" do
    it "is readable by the parking instance and by no other instance" do
      operation = park!(instance_tool(own_instance))

      own = read_as_instance(operation, node_instance: own_instance)
      expect(own).to include(success: true, deferred_operation_id: operation.id, call_origin: "mcp_instance")
      expect(read_as_instance(operation, node_instance: other_instance)).to eq(not_found)

      expect(operation.params["principal"]).to include("kind" => "instance", "node_instance_id" => own_instance.id,
                                                       "origin" => "mcp_instance")
      # The tool's own params stay where the gate context put them.
      expect(operation.params["widget_id"]).to eq("w-1")
    end

    it "records the tool's OWN principal over one the executor params carry, in either key shape" do
      operation = park!(instance_tool(own_instance), spoof_as: other_instance.id)

      expect(operation.params["principal"]).to include("kind" => "instance", "node_instance_id" => own_instance.id)
      expect(operation.params.keys.count { |key| key.to_s == "principal" }).to eq(1)

      expect(read_as_instance(operation, node_instance: own_instance)[:success]).to be(true)
      expect(read_as_instance(operation, node_instance: other_instance)).to eq(not_found)
    end
  end

  describe "the same descriptor every other principal's bespoke park records" do
    it "records a user principal the way the generic park does" do
      tool = SpecBespokeTool.new(account: account, user: parker)
      tool.call_origin = "mcp_oauth"
      operation = park!(tool)

      expect(operation.params["principal"]).to eq(
        "kind" => "user", "user_id" => parker.id, "agent_id" => nil, "internal" => false, "origin" => "mcp_oauth"
      )
      # A person's park is never an instance's.
      expect(read_as_instance(operation, node_instance: own_instance)).to eq(not_found)
    end

    it "records the descriptor a generic park of the same tool state records, byte for byte" do
      tool = instance_tool(own_instance)
      generic = ::Ai::Executors::DeferredToolCall.pack(
        tool_class: "SpecBespokeTool", action: "spec_bespoke_write", tool_params: {},
        principal: tool.send(:caller_principal_descriptor, "spec_bespoke_write")
      )["principal"]

      expect(park!(tool).params["principal"]).to eq(generic)
    end
  end

  # The hand-placed core site: DockerProvisioningTool#gated builds its own
  # executor params and calls the gate directly, outside #run_through_autonomy_gate.
  describe "DockerProvisioningTool#gated" do
    it "stamps the parking instance, never the node instance the call targets" do
      skip "needs the system extension's provisioner" unless ::Ai::Tools::DockerProvisioningTool.extension_available?

      target = create(:system_node_instance, account: account)
      result = ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.system_provision_docker_runtime",
        params: { "node_instance_id" => target.id },
        account: account, user: nil, instance_authorized: true, node_instance: own_instance, origin: "mcp_instance"
      )
      expect(result).to include(success: true, pending: true), result.inspect
      operation = ::Ai::DeferredOperation.find(result[:deferred_operation_id])

      expect(read_as_instance(operation, node_instance: own_instance)[:success]).to be(true)
      expect(read_as_instance(operation, node_instance: other_instance)).to eq(not_found)
      expect(read_as_instance(operation, node_instance: target)).to eq(not_found)

      expect(operation.params).to include("instance_id" => target.id)
      expect(operation.params["principal"]).to include("kind" => "instance", "node_instance_id" => own_instance.id,
                                                       "granted_tool_name" => "system_provision_docker_runtime")
    end
  end
end
