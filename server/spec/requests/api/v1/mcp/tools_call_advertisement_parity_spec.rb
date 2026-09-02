# frozen_string_literal: true

require "rails_helper"

# GUARD (IMP-128fe17fd8c8): ADVERTISEMENT AND INVOCATION MUST AGREE ON HTTP.
#
# IMP-5039d026da0d unified the four ADVERTISEMENT surfaces behind
# PlatformApiToolRegistry.advertised_action?, and recorded in its own comments
# that the invocation half was deliberately left alone: tools/call on the
# streamable-HTTP transport resolves through
# McpPlatformToolRegistrar#find_tool_class, which reads
# PlatformApiToolRegistry.all_tools RAW. The ActionCable transport did not
# diverge that way — though not for the reason recorded here at the time, as
# IMP-8e3bd13d0136 established: Mcp::ProtocolService#invoke_tool looks the
# manifest up in a Mcp::RegistryService that register_all! never populates (it
# builds and discards one of its own), so a de-advertised tool is un-invocable
# there — and so is an advertised one. IMP-8e3bd13d0136 made that transport
# answer the de-advertised case with this same envelope instead of a -32601.
#
# The result was a TRANSPORT DIVERGENCE: an action absent from tools/list (the
# docker-runtime actions in core mode, the extension-backed disk-image actions)
# was still dispatched into the tool by a client that knew the name. Each of the
# two core-hosted/extension-backed tools happens to carry its own guard in
# #call, so the observable outcome was a refusal either way — but the refusal
# came from the tool BODY, one class at a time, and nothing at the seam held the
# property. This spec pins the property at the seam.
#
# AVAILABILITY, NOT AUTHORIZATION. The refusal is a RESULT envelope (success
# false), not a JSON-RPC error and not a permission denial, and it is checked
# with `agent: nil` — i.e. it asks only "does this control plane offer the
# action?", never "may this caller run it?". Every existing permission gate runs
# first and is unchanged; see the sibling
# mcp_platform_tool_registrar_permission_ladder_spec.rb.
#
# FIDELITY of the simulation: hide_const("System") removes the extension
# namespace the actions actually depend on, exactly as
# tools_list_core_mode_docker_runtime_spec.rb does for the listing half. It
# leaves the extension's own tool classes defined, so the simulated catalog is a
# superset of a real core-mode one and cannot manufacture the refusals asserted
# here.
RSpec.describe "MCP tools/call advertisement parity", type: :request do
  let(:account) { create(:account) }
  let(:user) do
    user_with_permissions("devops.docker.manage", "system.platforms.publish_disk_image", account: account)
  end
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    { "Authorization" => "Bearer #{oauth_token.plaintext_token}",
      "Content-Type" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25" }
  end

  def tools_call(name, arguments = {})
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 7, method: "tools/call",
                   params: { name: name, arguments: arguments } }.to_json,
         headers: headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  # The de-advertised action is named directly. RED before the fix:
  # DockerProvisioningTool IS constructed and its own #call answers.
  it "refuses a de-advertised action at the seam instead of dispatching it" do
    hide_const("System")
    expect(::Ai::Tools::DockerProvisioningTool).not_to receive(:new)

    body = tools_call("platform.system_provision_docker_runtime",
                      { "node_instance_id" => SecureRandom.uuid })

    expect(body["error"]).to be_nil, "expected a result envelope, got #{body["error"].inspect}"
    expect(body.dig("result", "structuredContent", "success")).to be(false)
    expect(body.dig("result", "structuredContent", "error"))
      .to match(/not offered by this control plane/)
    expect(body.dig("result", "isError")).to be(true)
  end

  # The SECOND door to the same defect: for a caller whose action is not pinned
  # to the tool name, execute_tool lets a supplied :action win over the registry
  # key, so an advertised name can carry a de-advertised action into the tool.
  # RED before the fix: DiskImageOperatorTool is constructed with
  # action=bootstrap_disk_image_ci.
  it "refuses a de-advertised action supplied through the :action param" do
    hide_const("System")
    expect(::Ai::Tools::DiskImageOperatorTool).not_to receive(:new)

    body = tools_call("platform.provision_ci_worker",
                      { "action" => "bootstrap_disk_image_ci", "owner" => "acme", "repo" => "images" })

    expect(body["error"]).to be_nil, "expected a result envelope, got #{body["error"].inspect}"
    expect(body.dig("result", "structuredContent", "success")).to be(false)
    expect(body.dig("result", "structuredContent", "error"))
      .to match(/not offered by this control plane/)
  end

  # CONTROL ARM — the refusal is per ACTION, not per CLASS. provision_ci_worker
  # is core-only and stays advertised in core mode even though two of its
  # sibling actions on the same class do not, so it must still reach the tool.
  # The tool is doubled rather than executed: what is under test is that
  # dispatch HAPPENS, not what the action does.
  it "still dispatches a core-only action whose class siblings are de-advertised" do
    hide_const("System")
    tool = instance_double(::Ai::Tools::DiskImageOperatorTool)
    allow(tool).to receive(:node_instance=)
    allow(tool).to receive(:instance_authorized=)
    allow(tool).to receive(:execute).and_return({ success: true, data: { control: true } })
    expect(::Ai::Tools::DiskImageOperatorTool).to receive(:new).and_return(tool)

    body = tools_call("platform.provision_ci_worker", { "name" => "release-pipeline-runner" })

    expect(body["error"]).to be_nil, "expected a result envelope, got #{body["error"].inspect}"
    expect(body.dig("result", "structuredContent", "success")).to be(true)
  end
end
