# frozen_string_literal: true

require "rails_helper"

# GUARD: tools/list advertisement MUST stay filtered through the live principal
# gate (Mcp::Principal#granted_tool_patterns -> #may_invoke? -> #filter_tools).
#
# Why this lives at the REQUEST level and not in the model spec: the codebase
# previously carried a second, consumer-free accessor (#capability_scope) that
# returned a DIFFERENT answer for instance principals — the node's SELF-DECLARED
# capabilities rather than the server-side grant. A model spec asserting either
# accessor passed whether or not advertisement was actually gated, so it could
# not distinguish a working system from a broken one. Only an end-to-end
# assertion — narrow the gate, watch the advertised catalog shrink — can.
RSpec.describe "MCP tools/list principal filtering", type: :request do
  let(:account) { create(:account, status: "active") }
  let(:partner) do
    create(:federation_partner, :active, account: account,
           allowed_capabilities: [ "platform.read_shared_memory", "platform.write_shared_memory" ])
  end

  def advertised_tools
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json",
                    "X-Federation-Organization" => partner.organization_id,
                    "Authorization" => "Bearer test_token" }
    JSON.parse(response.body).dig("result", "tools").map { |t| t["name"] }
  end

  it "advertises only what the principal's granted patterns allow" do
    names = advertised_tools

    expect(names).to include("platform.read_shared_memory", "platform.write_shared_memory")
    # Not granted, and destroy-shaped: excluded by the gate and by the overlay.
    expect(names).not_to include("platform.kb_publish")
    expect(names).not_to include("platform.system_destroy_instance")
  end

  it "shrinks the advertised catalog when the granted patterns narrow" do
    wide = advertised_tools

    allow_any_instance_of(Mcp::Principal)
      .to receive(:granted_tool_patterns).and_return([ "platform.read_shared_memory" ])

    narrow = advertised_tools

    expect(wide).to include("platform.write_shared_memory")
    expect(narrow).to include("platform.read_shared_memory")
    expect(narrow).not_to include("platform.write_shared_memory")
    expect(narrow.size).to be < wide.size
  end

  it "never advertises a destroy-shaped tool even when the gate would allow it" do
    allow_any_instance_of(Mcp::Principal)
      .to receive(:granted_tool_patterns).and_return([ "platform.*" ])

    expect(advertised_tools).not_to include("platform.system_destroy_instance")
  end
end
