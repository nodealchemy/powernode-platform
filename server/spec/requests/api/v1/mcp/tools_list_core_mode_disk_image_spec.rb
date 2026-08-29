# frozen_string_literal: true

require "rails_helper"

# GUARD (IMP-8f6ade11fbdf): core mode (no `extensions/system` on disk) must not
# ADVERTISE the disk-image-operator actions.
#
# PlatformApiToolRegistry.available_tools rescues NameError around
# `class_name.constantize`, so extension-HOSTED tool classes (SystemFleetTool,
# SdwanTool, ...) drop out of tools/list by themselves when the extension is
# absent. Ai::Tools::DiskImageOperatorTool is core-HOSTED but extension-BACKED
# (::System::DiskImageWebhook), so it constantizes fine in core mode and its
# three actions stayed advertised — and provision_disk_image_webhook /
# bootstrap_disk_image_ci answered a tools/call with -32603 "Internal error:
# uninitialized constant System::DiskImageWebhook".
#
# This is the SECOND tool of this shape (IMP-2836d290f99a fixed the first,
# Ai::Tools::DockerProvisioningTool, whose commit named this one as
# known-incomplete). `provision_ci_worker` is NOT part of the guarded set: it
# depends only on core's own ::Worker model, so it must stay advertised and
# working with the extension absent.
#
# WHY THIS IS A REQUEST SPEC, not a unit spec on the tool class: the property
# under test is "the advertised catalog is honest", which only the real
# tools/list path can express. Asserting `DiskImageOperatorTool.permitted?`
# directly would pass whether or not anything consults it — the guard has to be
# REACHED by handle_tools_list -> PlatformApiToolRegistry.tool_definitions ->
# .available_tools -> klass.permitted?, and this spec drives that whole chain
# over HTTP. The extension's ABSENCE is the only thing simulated.
#
# FIDELITY of the simulation: hide_const("System") removes the extension's
# model/service namespace, which is what the guarded actions actually depend
# on. It leaves the extension's own tool CLASSES defined (a real core-mode
# boot would never load them), so the simulated catalog is a superset of a
# real core-mode one — it cannot manufacture the exclusion asserted here.
RSpec.describe "MCP tools/list in core mode (system extension absent)", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("system.platforms.publish_disk_image", account: account) }
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
  let(:extension_backed_actions) do
    %w[
      platform.provision_disk_image_webhook
      platform.bootstrap_disk_image_ci
    ]
  end

  def advertised_tools
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["result"]).to be_present, "tools/list errored: #{body["error"].inspect}"
    expect(body["result"]["nextCursor"]).to be_nil
    body.dig("result", "tools").map { |t| t["name"] }
  end

  # One example, not two: the "extension present" leg is the control arm of the
  # same comparison, and building the full-size catalog over HTTP is the
  # expensive part.
  it "advertises the extension-backed actions with the extension, and drops every one without it, " \
     "while provision_ci_worker (core-only) stays advertised" do
    with_extension = advertised_tools

    hide_const("System")
    without_extension = advertised_tools

    expect(with_extension).to include(*extension_backed_actions)
    expect(without_extension).not_to include(*extension_backed_actions)
    expect(with_extension - without_extension).to include(*extension_backed_actions)

    # provision_ci_worker depends only on ::Worker (core), not ::System::*.
    expect(with_extension).to include("platform.provision_ci_worker")
    expect(without_extension).to include("platform.provision_ci_worker")
  end

  # Both actions that actually raised NameError in core mode. The assertions are
  # POSITIVE on the tool's own envelope as well as negative on -32603: a
  # negative-only oracle would also pass on any other early return (e.g.
  # "label required"), which is not the property under test.
  %w[provision_disk_image_webhook bootstrap_disk_image_ci].each do |action|
    it "answers a direct tools/call to #{action} with the extension-missing envelope, not -32603" do
      hide_const("System")

      post "/api/v1/mcp/message",
           params: { jsonrpc: "2.0", id: 2, method: "tools/call",
                     params: { name: "platform.#{action}",
                               arguments: { label: "test", owner: "acme", repo: "widgets" } } }.to_json,
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
