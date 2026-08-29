# frozen_string_literal: true

require "rails_helper"

# IMP-37471f8e1619 — guard pinning the REMOVAL of the `allowed_scopes` gate.
#
# Mcp::PermissionValidator used to run a third check, `validate_allowed_scopes`,
# and surface its failure through `authorization_result` as error type
# "scope_permissions". That gate could not refuse any tool the platform is able
# to produce, while the taxonomy asserted that it could.
#
# Why it was inert — established structurally, by enumerating every writer to the
# `mcp_tools` table rather than by counting keyword hits:
#
#   * The four writers, and what each of them assigns:
#       - Ai::Tools::McpPlatformToolRegistrar#upsert_mcp_tool!   (platform catalogue,
#         and the terminus of the mcp:sync_tools rake task) — explicit list
#       - Api::V1::Internal::McpServersController#register_tools (worker-discovered
#         tools of externally-registered MCP servers) — explicit, field by field
#       - db/seeds/mcp_servers_seeds.rb                          — explicit setters
#       - db/seeds/mcp_example_servers.rb                        — MASS ASSIGNMENT
#         (`tool.assign_attributes(tool_attrs)` over a literal hash). Reading the
#         call proves nothing here; the attribute list is in the data, and every
#         literal in that file carries only name, description, input_schema and
#         permission_level. This is the writer shape a column-name grep misses.
#     None of the four writes allowed_scopes.
#   * There is no create/update route for mcp_tools (`resources :mcp_tools,
#     only: [:index, :show]`), no `accepts_nested_attributes_for :mcp_tools`, and
#     no update_all / insert_all / upsert_all / raw UPDATE against the table.
#   * The manifest key the sibling validator reads —
#     Mcp::RegistryService#validate_allowed_scopes! keys off "allowedScopes" — is
#     emitted by no manifest builder, and Mcp::RegistryService keeps tools in
#     memory only: its #persist_tool_to_database is explicitly inert, so even a
#     populated manifest could not reach the column.
#   * A scope PAYLOAD does exist upstream — examples/mcp-servers/shared/mcp-base.js
#     puts `allowedScopes` on every advertised tool — but it is discarded on
#     ingest by worker .../mcp_tool_discovery_job.rb#normalize_tool, which keeps
#     only name/description/input_schema. Declared upstream, dropped before the DB.
#   * The column therefore stays at its `{}` schema default, and `{}.blank?`
#     short-circuited every scope check to `true`.
#
# It was vacuous a second, independent way: `find_unauthorized_scopes` returned
# `[]` unconditionally, so the "scope_permissions" entry carried an empty
# `unauthorized` list and never consulted the user at all. What remained was a
# manifest well-formedness check wearing a permission-refusal label.
#
# Wiring it instead of deleting it would need a scope -> permission mapping that
# exists nowhere on the MCP path, and that mapping would have to cover all EIGHT
# scopes Doorkeeper accepts (config/initializers/doorkeeper.rb), not the four
# advertised at well_known_controller.rb — a token minted with `admin` falls
# straight through a map built from the advertised list. Do not re-add the branch
# without both.
#
# These examples pin the new truth: no input can make this validator emit a
# scope-shaped refusal. Mcp::PermissionValidator::TOOL_PERMISSION_SCOPES survives
# for Mcp::RegistryService#validate_allowed_scopes!, which checks an in-memory
# MANIFEST key rather than the column and so is not defeated by the empty column.
# McpTool#validate_permission_fields reads the constant too, but behind
# `allowed_scopes.present?` — the same never-true guard — so it is not
# independent justification. Neither claims to be an authorization gate.
RSpec.describe Mcp::PermissionValidator, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:mcp_server) { create(:mcp_server, account: account) }

  def validator_for(tool)
    described_class.new(tool: tool, user: user, account: account)
  end

  describe "no scope-shaped refusal remains" do
    it "authorizes a tool whose stored scopes name a permission outside the catalogue" do
      # Valid category + array value, so McpTool's own validation persists this.
      tool = create(:mcp_tool,
                    mcp_server: mcp_server,
                    permission_level: "public",
                    required_permissions: [],
                    allowed_scopes: { "file_access" => %w[read_files zz_not_a_real_permission] })

      expect(validator_for(tool).authorized?).to be true
    end

    it "authorizes a tool whose stored scopes name an unknown category" do
      tool = create(:mcp_tool,
                    mcp_server: mcp_server,
                    permission_level: "public",
                    required_permissions: [],
                    allowed_scopes: {})
      # Bypasses model validation the way a raw UPDATE would.
      tool.update_column(:allowed_scopes, { "zz_bogus_category" => %w[anything] })

      expect(validator_for(tool.reload).authorized?).to be true
    end

    it "never puts a scope_permissions entry in the error taxonomy" do
      tool = create(:mcp_tool,
                    mcp_server: mcp_server,
                    permission_level: "public",
                    required_permissions: [],
                    allowed_scopes: { "file_access" => %w[zz_not_a_real_permission] })

      types = validator_for(tool).authorization_result[:errors].map { |e| e[:type] }
      expect(types).not_to include("scope_permissions")
    end

    it "emits no scope_permissions entry even when another gate is refusing" do
      tool = create(:mcp_tool,
                    mcp_server: mcp_server,
                    permission_level: "public",
                    required_permissions: [ "zz.permission.the.user.lacks" ],
                    allowed_scopes: { "network" => %w[zz_not_a_real_permission] })

      result = validator_for(tool).authorization_result
      types = result[:errors].map { |e| e[:type] }

      expect(result[:authorized]).to be false
      expect(types).to include("required_permissions")
      expect(types).not_to include("scope_permissions")
    end

    it "no longer defines a scope error class for the taxonomy to raise" do
      expect(described_class.const_defined?(:InvalidScopeError, false)).to be false
    end

    it "no longer exposes a scope_permitted? entry point" do
      expect(described_class.instance_methods).not_to include(:scope_permitted?)
    end
  end

  describe "the gates that do fire are untouched" do
    it "still refuses on permission level" do
      tool = create(:mcp_tool,
                    mcp_server: mcp_server,
                    permission_level: "admin",
                    required_permissions: [])

      expect(validator_for(tool).authorized?).to be false
      expect(validator_for(tool).authorization_result[:errors].map { |e| e[:type] })
        .to include("permission_level")
    end

    it "still refuses on missing required permissions" do
      tool = create(:mcp_tool,
                    mcp_server: mcp_server,
                    permission_level: "public",
                    required_permissions: [ "zz.permission.the.user.lacks" ])

      expect(validator_for(tool).authorized?).to be false
      expect(validator_for(tool).authorization_result[:errors].map { |e| e[:type] })
        .to include("required_permissions")
    end
  end
end
