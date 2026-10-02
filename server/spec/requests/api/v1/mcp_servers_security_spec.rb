# frozen_string_literal: true

require "rails_helper"

# IMP-cdda895b07a8 — the operator-only stdio sandbox capabilities (allow_network,
# allow_extended_commands, egress_allowlist; IMP-a50680fd53d8 / IMP-bf72723ef161) could be set
# only from the Rails console: the user controller permits config: {} only, the frontend sends no
# capabilities, and no MCP tool writes an McpServer. PATCH /api/v1/mcp_servers/:id/security is
# their one door: its OWN permission (mcp.servers.security_manage, deliberately not part of
# mcp.servers.write, like mcp.servers.native_execution), the model's own validations, every
# change audited.
RSpec.describe "Api::V1::McpServers security capabilities", type: :request do
  let(:account) { create(:account) }
  let(:owner) { create(:user, :owner, account: account) }
  let(:manager) { create(:user, :manager, account: account) }
  let(:operator) do
    create(:user, account: account, permissions: %w[mcp.servers.read mcp.servers.security_manage])
  end
  let(:reader) { create(:user, account: account, permissions: %w[mcp.servers.read]) }
  let(:server) do
    create(:mcp_server, :disconnected, :stdio, account: account,
                                                capabilities: { "strict_environment" => true, "config" => { "log_level" => "info" } })
  end
  let(:path) { "/api/v1/mcp_servers/#{server.id}/security" }

  def patch_security(body, as: operator, target: path)
    patch target, params: { security: body }, headers: auth_headers_for(as), as: :json
  end

  def caps
    server.reload.capabilities
  end

  def security_audits
    AuditLog.where(action: "mcp.servers.security_update", resource_id: server.id)
  end

  describe "the permission" do
    it "exists, the owner carries it, and a manager with mcp.servers.write does not" do
      expect(Permissions::RESOURCE_PERMISSIONS.keys).to include("mcp.servers.security_manage")
      expect(owner.has_permission?("mcp.servers.security_manage")).to be true
      expect(manager.has_permission?("mcp.servers.write")).to be true
      expect(manager.has_permission?("mcp.servers.security_manage")).to be false
    end
  end

  describe "authorization" do
    it "401s without auth" do
      patch path, params: { security: { allow_network: true } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "403s a manager who can manage servers but lacks mcp.servers.security_manage, changing nothing" do
      patch_security({ allow_network: true }, as: manager)

      expect_error_response("Insufficient permissions to manage MCP server security settings", 403)
      expect(caps["allow_network"]).to be_nil
      expect(security_audits).to be_empty
    end

    it "403s a user who holds mcp.servers.security_manage but not mcp.servers.read (the response carries the server)" do
      only_manage = create(:user, account: account, permissions: %w[mcp.servers.security_manage])

      patch_security({ allow_network: true }, as: only_manage)

      expect(response).to have_http_status(:forbidden)
      expect(caps["allow_network"]).to be_nil
    end

    it "403s a reader" do
      patch_security({ allow_network: true }, as: reader)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s another account's server" do
      other = create(:mcp_server, :disconnected, :stdio, account: create(:account))

      patch_security({ allow_network: true }, target: "/api/v1/mcp_servers/#{other.id}/security")

      expect(response).to have_http_status(:not_found)
      expect(other.reload.capabilities["allow_network"]).to be_nil
    end
  end

  describe "setting the capabilities" do
    it "sets allow_network and allow_extended_commands, keeping every other capability and the config" do
      patch_security({ allow_network: true, allow_extended_commands: true })

      expect(response).to have_http_status(:ok)
      expect(caps).to include("allow_network" => true, "allow_extended_commands" => true,
                              "strict_environment" => true, "config" => { "log_level" => "info" })
      expect(json_response_data["mcp_server"]["security"])
        .to include("allow_network" => true, "allow_extended_commands" => true, "egress_allowlist" => [])
    end

    it "is a partial update: only the keys sent change" do
      server.update!(capabilities: server.capabilities.merge("allow_extended_commands" => true))

      patch_security({ allow_network: true })

      expect(caps).to include("allow_network" => true, "allow_extended_commands" => true)
    end

    it "sets an egress allowlist of hostnames, IPs and CIDRs, and an empty list clears it" do
      patch_security({ egress_allowlist: [ "api.example.test", "203.0.113.7", "198.51.100.0/24" ] })

      expect(response).to have_http_status(:ok)
      expect(caps["egress_allowlist"]).to eq([ "api.example.test", "203.0.113.7", "198.51.100.0/24" ])

      patch_security({ egress_allowlist: [] })

      expect(response).to have_http_status(:ok)
      expect(caps["egress_allowlist"]).to be_blank
    end

    it "turns a capability back off" do
      server.update!(capabilities: server.capabilities.merge("allow_network" => true))

      patch_security({ allow_network: false })

      expect(response).to have_http_status(:ok)
      expect(caps["allow_network"]).to be false
    end

    it "serializes the security block on show for a plain reader" do
      server.update!(capabilities: server.capabilities.merge("allow_network" => true))

      get "/api/v1/mcp_servers/#{server.id}", headers: auth_headers_for(reader), as: :json

      expect(json_response_data["mcp_server"]["security"]).to include("allow_network" => true)
    end
  end

  describe "the model's own validations are the only rules" do
    it "refuses allow_network together with an egress_allowlist, changing nothing" do
      patch_security({ allow_network: true, egress_allowlist: [ "api.example.test" ] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/cannot both be set/)
      expect(caps["allow_network"]).to be_nil
      expect(security_audits).to be_empty
    end

    it "refuses allow_network when an allowlist is already stored (the model sees the merged result)" do
      server.update!(capabilities: server.capabilities.merge("egress_allowlist" => [ "api.example.test" ]))

      patch_security({ allow_network: true })

      expect(response).to have_http_status(:unprocessable_content)
      expect(caps["allow_network"]).to be_nil
    end

    it "refuses loopback, link-local, metadata and full-open entries" do
      [ "127.0.0.1", "169.254.169.254", "fe80::1", "0.0.0.0/0", "::1" ].each do |entry|
        patch_security({ egress_allowlist: [ entry ] })

        expect(response).to have_http_status(:unprocessable_content), entry
        expect(caps["egress_allowlist"]).to be_blank
      end
    end

    it "refuses more than the maximum number of entries" do
      entries = Array.new(McpServer::MAX_EGRESS_ALLOWLIST_ENTRIES + 1) { |i| "h#{i}.example.test" }

      patch_security({ egress_allowlist: entries })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/at most #{McpServer::MAX_EGRESS_ALLOWLIST_ENTRIES}/)
    end
  end

  describe "strict input" do
    it "refuses a non-boolean allow_network or allow_extended_commands" do
      [ "yes", "true", 1, nil, [ true ] ].each do |value|
        patch_security({ allow_network: value })
        expect(response).to have_http_status(:unprocessable_content), value.inspect
        expect(caps["allow_network"]).to be_nil
      end
      patch_security({ allow_extended_commands: "on" })
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses an allowlist that is not an array of strings" do
      [ "api.example.test", { "a" => 1 }, [ 1 ], [ [ "x" ] ], [ nil ] ].each do |value|
        patch_security({ egress_allowlist: value })
        expect(response).to have_http_status(:unprocessable_content), value.inspect
      end
    end

    it "refuses any other capability key: this door sets only the three sandbox capabilities" do
      patch_security({ strict_environment: false })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/strict_environment/)
      expect(caps["strict_environment"]).to be true
    end

    it "refuses allowlist entries carrying newlines, NUL or spaces" do
      [ "api.example.test\nevil.test", "a\u0000b.test", "api.example.test ", " api.example.test" ].each do |entry|
        patch_security({ egress_allowlist: [ entry ] })
        expect(response).to have_http_status(:unprocessable_content), entry.inspect
      end
    end

    it "refuses an empty or missing security object" do
      patch_security({})
      expect(response).to have_http_status(:unprocessable_content)

      patch path, params: {}, headers: auth_headers_for(operator), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a server that is not stdio: the sandbox only applies to stdio children" do
      http = create(:mcp_server, :disconnected, :http_connection, account: account)

      patch_security({ allow_network: true }, target: "/api/v1/mcp_servers/#{http.id}/security")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(/stdio/)
      expect(http.reload.capabilities["allow_network"]).to be_nil
    end
  end

  describe "concurrent capability writers" do
    it "keeps a capability another writer set between load and save (the merge runs under the row lock)" do
      allow_any_instance_of(McpServer).to receive(:with_lock).and_wrap_original do |orig, *args, &block|
        # another writer lands first
        McpServer.where(id: server.id).update_all(capabilities: server.capabilities.merge("strict_environment" => false, "late" => "kept"))
        orig.call(*args, &block)
      end

      patch_security({ allow_network: true })

      expect(response).to have_http_status(:ok)
      expect(caps).to include("allow_network" => true, "late" => "kept", "strict_environment" => false)
    end
  end

  describe "the audit trail" do
    it "writes one high-severity row naming the actor, with the before and after of the three settings" do
      expect { patch_security({ allow_network: true }) }.to change { security_audits.count }.by(1)

      row = security_audits.last
      expect(row.user_id).to eq(operator.id)
      expect(row.metadata["before"]).to include("allow_network" => false, "allow_extended_commands" => false)
      expect(row.metadata["after"]).to include("allow_network" => true)
      expect(row.metadata["changed"]).to eq([ "allow_network" ])
      expect(row.severity).to eq("high")
    end

    it "records a clear of the allowlist too" do
      server.update!(capabilities: server.capabilities.merge("egress_allowlist" => [ "api.example.test" ]))

      patch_security({ egress_allowlist: [] })

      expect(security_audits.last.metadata["changed"]).to eq([ "egress_allowlist" ])
    end

    it "writes no row when nothing changes" do
      patch_security({ allow_network: false })

      expect(response).to have_http_status(:ok)
      expect(security_audits).to be_empty
    end

    it "is a registered audit action" do
      expect(AuditActions::MCP_ACTIONS).to include("mcp.servers.security_update")
    end
  end

  describe "the general update endpoint still cannot set them" do
    it "ignores capabilities sent to PATCH /mcp_servers/:id" do
      patch "/api/v1/mcp_servers/#{server.id}", params: { mcp_server: { description: "x", capabilities: { allow_network: true } } },
                                                  headers: auth_headers_for(owner), as: :json

      expect(caps["allow_network"]).to be_nil
    end
  end
end
