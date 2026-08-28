# frozen_string_literal: true

require "rails_helper"

# Regression cover for the fail-open tool-discovery branch.
#
# Two independent defects sat on the same path:
#   1. Mcp::ProtocolService#list_tools skipped its permission filter entirely
#      unless BOTH `user` and `@account` were present, and McpChannel called it
#      with no `user:` at all — so the filter never ran on the WebSocket path.
#   2. Inside the filter, a tool with no McpTool row was admitted unconditionally
#      ("legacy tools"), without ever constructing a PermissionValidator.
#
# Neither was exploitable when found: RegistryService is per-instance in-memory
# (`@tools = {}`), its persistence hooks are intentionally inert, and nothing
# registers tools into the per-connection instance, so the live list was empty.
# These examples register tools explicitly to exercise the branch that WOULD be
# live the moment anything populates that registry.
RSpec.describe Mcp::ProtocolService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account: account) }

  def manifest(name, required_permissions: nil)
    m = {
      "name" => name,
      "description" => "fixture tool #{name}",
      "type" => "ai_agent",
      "version" => "1.0.0",
      "inputSchema" => { "type" => "object", "properties" => {}, "required" => [] },
      "outputSchema" => { "type" => "object", "properties" => {}, "required" => [] }
    }
    m["required_permissions"] = required_permissions if required_permissions
    m
  end

  def listed_names(result)
    result["tools"].map { |t| t["name"] }
  end

  describe "#list_tools authorization filtering" do
    context "when a registered tool has no McpTool record" do
      it "excludes it when the manifest declares a permission the user lacks" do
        service.register_tool(manifest("zz_authz_fixture_declared", required_permissions: [ "nonexistent.permission" ]))

        expect(McpTool.find_by(name: "zz_authz_fixture_declared")).to be_nil
        expect(listed_names(service.list_tools({}, user: user))).not_to include("zz_authz_fixture_declared")
      end

      it "excludes it when the manifest declares no permissions at all" do
        # Fail closed: discovery must not advertise a tool whose authorization
        # cannot be determined. This is the branch that previously read
        # `next true unless mcp_tool`.
        service.register_tool(manifest("zz_authz_fixture_undeclared"))

        expect(listed_names(service.list_tools({}, user: user))).not_to include("zz_authz_fixture_undeclared")
      end

      it "includes it when the user holds every declared permission" do
        allow(user).to receive(:permission_names).and_return([ "zz.fixture.read" ])
        service.register_tool(manifest("zz_authz_fixture_granted", required_permissions: [ "zz.fixture.read" ]))

        expect(listed_names(service.list_tools({}, user: user))).to include("zz_authz_fixture_granted")
      end
    end

    context "when no user is supplied" do
      it "returns no tools rather than the unfiltered catalog" do
        service.register_tool(manifest("zz_authz_fixture_nouser"))

        expect(listed_names(service.list_tools({}))).to be_empty
      end
    end
  end
end
