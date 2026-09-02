# frozen_string_literal: true

require "rails_helper"

# GUARD (IMP-8e3bd13d0136): THE REFUSAL SHAPE FOR A DE-ADVERTISED ACTION IS THE
# SAME ON BOTH TRANSPORTS.
#
# IMP-128fe17fd8c8 gave the streamable-HTTP tools/call path an availability
# refusal at the seam: McpPlatformToolRegistrar.execute_tool answers a
# de-advertised action with a RESULT envelope ({success: false, error: "Tool not
# available: ..."}), which the controller renders as structuredContent +
# isError. The ActionCable path did not follow: Mcp::ProtocolService#invoke_tool
# looks the manifest up in a Mcp::RegistryService and raised ToolNotFoundError —
# a JSON-RPC -32601 — when the lookup missed. A client reads -32601 as a
# TRANSPORT/method fault (a name this server does not implement) and retries;
# the envelope is a terminal, self-describing answer about availability.
#
# NOTE ON THE MECHANISM, because the neighbouring comments used to state it
# wrongly: the miss is NOT "register_all! publishes only the advertised classes
# into this registry". register_all! builds a RegistryService of its own and
# discards it, so NO platform manifest is visible on this path — advertised or
# not. The fix therefore re-resolves the name through the registrar rather than
# reading the miss, and an advertised platform action is still un-invocable
# here for that same, separate, pre-existing plumbing reason.
#
# Operator ruling 2026-09-02 (bulk review D15): the RESULT ENVELOPE on both
# transports; ToolNotFoundError stays for names the platform has never heard of.
#
# BYTE-EQUAL, NOT MERELY SIMILAR. The parity example below compares the two
# transports' refusal strings with `eq`, because the two producers drifting
# apart is exactly the defect: two hand-written sentences saying the same thing
# is what a client cannot rely on. The fix makes ProtocolService ask the same
# producer the HTTP seam asks.
#
# AVAILABILITY, NOT AUTHORIZATION. As on the HTTP seam, the predicate is asked
# with the default `agent: nil`, so it answers only "does this control plane
# offer the action?" — never "may this caller run it?". hide_const("System")
# simulates core mode exactly as the sibling
# spec/requests/api/v1/mcp/tools_call_advertisement_parity_spec.rb does for the
# HTTP half.
#
# ...AND AUTHORIZATION STILL COMES FIRST. The HTTP seam gates on the tool's
# REQUIRED_PERMISSION before it refuses on availability, so answering the
# envelope ahead of that gate here would have replaced the divergence being
# closed with a new one — and disclosed which extensions are loaded to a caller
# who may not run the action. The last example pins that both transports answer
# such a caller with the same PermissionDeniedError sentence, which is why the
# `user` below carries both permissions the two exercised tools require (the
# same pair the HTTP parity spec grants).
RSpec.describe Mcp::ProtocolService, type: :service do
  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account,
                  permissions: ["devops.docker.manage", "system.platforms.publish_disk_image"])
  end
  let(:service) { described_class.new(account: account) }

  # The de-advertised action: DockerProvisioningTool gates its whole class on
  # ::System::DockerDaemonProvisionerService, so in core mode none of its
  # actions is offered.
  let(:tool_id) { "platform.system_provision_docker_runtime" }
  let(:arguments) { { "node_instance_id" => SecureRandom.uuid } }

  describe "#invoke_tool on a de-advertised action" do
    before { hide_const("System") }

    it "answers with a result envelope instead of raising ToolNotFoundError" do
      expect(::Ai::Tools::DockerProvisioningTool).not_to receive(:new)

      response = service.invoke_tool(tool_id, arguments, { user: user })

      expect(response[:result]).to be_a(Hash)
      expect(response[:result][:success]).to be(false)
      expect(response[:result][:error]).to match(/not offered by this control plane/)
    end

    it "returns the byte-equal refusal the streamable-HTTP seam returns" do
      http_refusal = ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        tool_id, params: arguments, account: account, user: user
      )
      cable_refusal = service.invoke_tool(tool_id, arguments, { user: user })[:result]

      expect(http_refusal[:success]).to be(false)
      expect(cable_refusal[:error]).to eq(http_refusal[:error])
      expect(cable_refusal).to eq(http_refusal)
    end

    # THE SECOND DOOR: a supplied :action, not just the invoked name, is what
    # would actually run for a caller whose action is not pinned to the tool
    # name — so the :action must be threaded into the refusal seam.
    #
    # SCOPE, stated honestly: this pins the THREADING, not a production path
    # through an advertised name. A name that has a manifest never reaches the
    # branch under test; it is dispatched via #execute_tool_by_type into
    # McpPlatformToolRegistrar.execute_tool, where the identical
    # #unadvertised_refusal already fires — a door IMP-128fe17fd8c8 closed, and
    # one the sibling HTTP request spec exercises end to end. Here the manifest
    # is absent for every platform name (see the mechanism note at the top), so
    # what this example proves is that the supplied action reaches
    # .unavailable_action_refusal and is refused on its own merits.
    it "refuses a de-advertised action supplied through the :action param" do
      expect(::Ai::Tools::DiskImageOperatorTool).not_to receive(:new)

      response = service.invoke_tool(
        "platform.provision_ci_worker",
        { "action" => "bootstrap_disk_image_ci", "owner" => "acme", "repo" => "images" },
        { user: user }
      )

      expect(response[:result][:success]).to be(false)
      expect(response[:result][:error]).to match(/bootstrap_disk_image_ci is not offered/)
    end
  end

  # THE BOUNDARY the ruling draws: a name the platform has never registered is
  # still a JSON-RPC method fault, not an availability envelope. Without this
  # arm the fix could degenerate into "never raise ToolNotFoundError".
  it "still raises ToolNotFoundError for a name that was never registered" do
    expect {
      service.invoke_tool("platform.zz_not_a_registered_tool_at_all", {}, { user: user })
    }.to raise_error(described_class::ToolNotFoundError, /Tool not found/)
  end

  # ORDERING PARITY. A caller without the tool's REQUIRED_PERMISSION must be
  # answered the SAME permission denial on both transports, and must not be
  # handed the availability envelope — which would tell an unauthorized caller
  # which extensions this control plane has loaded, and would be a fresh
  # transport divergence in place of the one being closed. Compared by SENTENCE,
  # not just by class, because both sides are meant to come off the one
  # #enforce_permission!.
  describe "#invoke_tool on a de-advertised action the caller may not run" do
    before { hide_const("System") }

    let(:unpermitted_user) { create(:user, account: account, permissions: ["ai.agents.read"]) }

    it "denies with the same sentence the streamable-HTTP seam denies with" do
      http_message = begin
        ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
          tool_id, params: arguments, account: account, user: unpermitted_user
        )
        nil
      rescue described_class::PermissionDeniedError => e
        e.message
      end

      cable_message = begin
        service.invoke_tool(tool_id, arguments, { user: unpermitted_user })
        nil
      rescue described_class::PermissionDeniedError => e
        e.message
      end

      expect(http_message).to match(/requires 'devops.docker.manage'/)
      expect(cable_message).to eq(http_message)
    end
  end
end
