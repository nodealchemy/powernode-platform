# frozen_string_literal: true

require "rails_helper"

# GUARD (IMP-2836d290f99a): core mode (no `extensions/system` on disk) must not
# ADVERTISE the docker-runtime actions.
#
# PlatformApiToolRegistry.available_tools rescues NameError around
# `class_name.constantize`, so extension-HOSTED tool classes (SystemFleetTool,
# SdwanTool, ...) drop out of tools/list by themselves when the extension is
# absent. Ai::Tools::DockerProvisioningTool is core-HOSTED but extension-BACKED
# (System::DockerDaemonProvisionerService, System::NodeInstance), so it
# constantizes fine in core mode and its four actions stayed advertised — and
# system_provision_docker_runtime answered a tools/call with -32603 "Internal
# error: uninitialized constant System::...".
#
# It is not the only tool of that shape — Ai::Tools::DiskImageOperatorTool has
# the same problem via ::System::DiskImageWebhook and is filed separately, so
# this spec is scoped to the four docker-runtime actions, not to the property in
# general.
#
# WHY THIS IS A REQUEST SPEC, not a unit spec on the tool class: the property
# under test is "the advertised catalog is honest", which only the real
# tools/list path can express. Asserting `DockerProvisioningTool.permitted?`
# directly would pass whether or not anything consults it — the guard has to be
# REACHED by handle_tools_list -> PlatformApiToolRegistry.tool_definitions ->
# .available_tools -> klass.permitted?, and this spec drives that whole chain
# over HTTP. The extension's ABSENCE is the only thing simulated.
#
# FIDELITY of the simulation: hide_const("System") removes the extension's
# model/service namespace, which is what the four actions actually depend on.
# It leaves the extension's own tool CLASSES defined (a real core-mode boot
# would never load them), so the simulated catalog is a superset of a real
# core-mode one — it cannot manufacture the exclusion asserted here. Several of
# those tools do drop out anyway, because SystemFleetTool and SystemAcmeTool
# already carry this same `defined?(::System)` guard on .permitted?; the fix
# under test puts the core-hosted, extension-backed DockerProvisioningTool on
# the same footing. That is why the assertion below is "these four crossed from
# advertised to not-advertised", not "these four are the whole difference".
RSpec.describe "MCP tools/list in core mode (system extension absent)", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("devops.docker.manage", account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    { "Authorization" => "Bearer #{oauth_token.plaintext_token}",
      "Content-Type" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25" }
  end

  # A `let`, not a top-level constant: a constant assigned inside a block lands
  # on Object and can be clobbered by a same-named one in another spec file.
  let(:docker_runtime_actions) do
    %w[
      platform.system_provision_docker_runtime
      platform.system_decommission_docker_runtime
      platform.system_mark_docker_ready
      platform.system_list_managed_docker_hosts
    ]
  end

  def advertised_tools
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["result"]).to be_present, "tools/list errored: #{body["error"].inspect}"
    # TOOLS_PAGE_SIZE is 1000 and the catalog is ~611; assert we got one page.
    expect(body["result"]["nextCursor"]).to be_nil
    body.dig("result", "tools").map { |t| t["name"] }
  end

  # One example, not two: the "extension present" leg is the control arm of the
  # same comparison, and building the ~611-entry catalog over HTTP is the
  # expensive part.
  it "advertises the docker-runtime actions with the extension, and drops every one without it" do
    with_extension = advertised_tools

    hide_const("System")
    without_extension = advertised_tools

    expect(with_extension).to include(*docker_runtime_actions)
    expect(without_extension).not_to include(*docker_runtime_actions)
    expect(with_extension - without_extension).to include(*docker_runtime_actions)
  end

  # Both actions that actually raised NameError in core mode. The assertions are
  # POSITIVE on the tool's own envelope as well as negative on -32603: a
  # negative-only oracle would also pass on any other early return (e.g.
  # "node_instance_id is required"), which is not the property under test.
  %w[system_provision_docker_runtime system_mark_docker_ready].each do |action|
    it "answers a direct tools/call to #{action} with the extension-missing envelope, not -32603" do
      hide_const("System")

      post "/api/v1/mcp/message",
           params: { jsonrpc: "2.0", id: 2, method: "tools/call",
                     params: { name: "platform.#{action}",
                               arguments: { node_instance_id: SecureRandom.uuid,
                                            host_id: SecureRandom.uuid } } }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("uninitialized constant")
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).not_to eq(-32603)
      expect(body.dig("result", "structuredContent", "success")).to be(false)
      expect(body.dig("result", "structuredContent", "error")).to match(/requires the 'system' extension/)
    end
  end
end
