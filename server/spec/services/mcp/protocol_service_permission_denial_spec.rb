# frozen_string_literal: true

require "rails_helper"

# End-to-end cover for the MCP permission-denial path.
#
# Mcp::ProtocolService#invoke_tool calls
# `@telemetry.track_tool_permission_denied(...)` immediately before raising
# PermissionDeniedError. Mcp::TelemetryService did not define that method (and
# defines no method_missing), so every denial for a tool that HAS an McpTool row
# raised NoMethodError instead of the intended PermissionDeniedError. The refusal
# still happened — it failed CLOSED — but the caller never received the error the
# taxonomy promises, and the denial was never recorded.
#
# These examples deliberately drive a REAL denial through the real
# PermissionValidator, the real registry and the real TelemetryService. Nothing
# on the denial path is stubbed: a spec that asserted the telemetry method merely
# EXISTS would reproduce the same blind spot one level up — the shipped call site
# was itself proof that a call alone is no evidence of a method.
#
# Both surviving taxonomy entries are exercised separately: "permission_level"
# and "required_permissions". (The third, "scope_permissions", was vacuous and
# was deleted in IMP-37471f8e1619 — see mcp/permission_validator.rb.)
RSpec.describe Mcp::ProtocolService, type: :service do
  let(:account) { create(:account) }
  # `permissions: []` — the FIRST user in an account otherwise gets the owner
  # role and its whole permission catalogue (see spec/factories/users.rb).
  let(:user) { create(:user, account: account, permissions: []) }
  let(:mcp_server) { create(:mcp_server, account: account) }
  let(:service) { described_class.new(account: account) }

  def manifest(name)
    {
      "name" => name,
      "description" => "fixture tool #{name}",
      "type" => "ai_agent",
      "version" => "1.0.0",
      "inputSchema" => { "type" => "object", "properties" => {}, "required" => [] },
      "outputSchema" => { "type" => "object", "properties" => {}, "required" => [] }
    }
  end

  # Registers the manifest in the in-memory registry AND creates the backing
  # McpTool row, so #invoke_tool takes the `mcp_tool && user` branch — the one
  # that consults PermissionValidator and emits denial telemetry.
  def register_backed_tool(name, permission_level:, required_permissions: [])
    tool = create(:mcp_tool,
                  mcp_server: mcp_server,
                  name: name,
                  permission_level: permission_level,
                  required_permissions: required_permissions)
    tool_id = service.register_tool(manifest(name))
    [ tool_id, tool ]
  end

  describe "#invoke_tool permission denial" do
    it "raises PermissionDeniedError carrying the permission_level refusal" do
      tool_id, tool = register_backed_tool("zz_denial_fixture_level", permission_level: "admin")

      # Precondition: the row exists, so this is the McpTool-backed branch.
      expect(McpTool.find_by(name: "zz_denial_fixture_level")).to eq(tool)

      # Precondition: the validator refuses with exactly the permission_level entry.
      result = Mcp::PermissionValidator.new(tool: tool, user: user, account: account).authorization_result
      expect(result[:authorized]).to be(false)
      expect(result[:errors].map { |e| e[:type] }).to eq([ "permission_level" ])

      expect {
        service.invoke_tool(tool_id, {}, user: user)
      }.to raise_error(Mcp::ProtocolService::PermissionDeniedError, /requires 'admin' level access/)
    end

    it "raises PermissionDeniedError carrying the required_permissions refusal" do
      tool_id, tool = register_backed_tool("zz_denial_fixture_perms",
                                           permission_level: "account",
                                           required_permissions: [ "zz.fixture.never_granted" ])

      result = Mcp::PermissionValidator.new(tool: tool, user: user, account: account).authorization_result
      expect(result[:errors].map { |e| e[:type] }).to eq([ "required_permissions" ])

      expect {
        service.invoke_tool(tool_id, {}, user: user)
      }.to raise_error(Mcp::ProtocolService::PermissionDeniedError,
                       /Missing required permissions: zz\.fixture\.never_granted/)
    end

    it "surfaces both taxonomy entries when both gates refuse" do
      tool_id, tool = register_backed_tool("zz_denial_fixture_both",
                                           permission_level: "admin",
                                           required_permissions: [ "zz.fixture.never_granted" ])

      result = Mcp::PermissionValidator.new(tool: tool, user: user, account: account).authorization_result
      expect(result[:errors].map { |e| e[:type] }).to match_array(%w[permission_level required_permissions])

      expect {
        service.invoke_tool(tool_id, {}, user: user)
      }.to raise_error(Mcp::ProtocolService::PermissionDeniedError) { |error|
        expect(error.message).to include("requires 'admin' level access")
        expect(error.message).to include("Missing required permissions: zz.fixture.never_granted")
      }
    end

    it "records the denial with its taxonomy type instead of dropping it" do
      allow(Rails.logger).to receive(:info).and_call_original
      tool_id, = register_backed_tool("zz_denial_fixture_observed", permission_level: "admin")

      expect {
        service.invoke_tool(tool_id, {}, user: user)
      }.to raise_error(Mcp::ProtocolService::PermissionDeniedError)

      expect(Rails.logger).to have_received(:info)
        .with(/\[MCP_TELEMETRY\] tool_permission_denied.*permission_level/)
    end

    it "does not record a refused call as a started invocation" do
      # A denial is refused BEFORE track_tool_invocation_start; counting it as a
      # started invocation would skew the success-rate metrics.
      allow(Rails.logger).to receive(:info).and_call_original
      tool_id, = register_backed_tool("zz_denial_fixture_notstarted", permission_level: "admin")

      expect {
        service.invoke_tool(tool_id, {}, user: user)
      }.to raise_error(Mcp::ProtocolService::PermissionDeniedError)

      expect(Rails.logger).not_to have_received(:info).with(/\[MCP_TELEMETRY\] tool_invocation_start/)
    end
  end
end
