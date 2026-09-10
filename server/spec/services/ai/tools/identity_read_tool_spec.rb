# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment E1 — identity over MCP is READ-ONLY.
#
# The oracles that matter here are the ones a wrong implementation would pass:
# every verb refused WITHOUT its own read permission and allowed WITH it, no
# authentication material anywhere in a response (asserted by grepping the
# serialized JSON for the factory's real secret values, not by checking that a
# key is absent), and account isolation.
RSpec.describe Ai::Tools::IdentityReadTool do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  # The account's FIRST user takes the owner role, so make one before the
  # actors — otherwise a "refused" example could pass on an owner grant.
  let!(:first_user) { create(:user, account: account) }

  def actor(*permissions)
    described_class.new(account: account, user: create(:user, account: account, permissions: permissions))
  end

  def advertised_actions = %w[list_users get_user list_roles list_permissions list_audit_logs]

  # Every verb, with a params set that reaches its body.
  def sample_calls(user_id:)
    [
      { action: "list_users" },
      { action: "get_user", id: user_id },
      { action: "list_roles" },
      { action: "list_permissions" },
      { action: "list_audit_logs" }
    ]
  end

  describe "declarations" do
    it "declares every advertised action, all read-only, and advertises exactly these five" do
      advertised = ::Ai::Tools::PlatformApiToolRegistry.all_tools
                                                       .select { |_, klass| klass == described_class.name }
                                                       .keys.map(&:to_s)
      expect(advertised).to match_array(advertised_actions)

      advertised.each do |action|
        declaration = described_class.declared_action(action)
        expect(declaration).not_to be_nil, "#{action} is advertised but not declared"
        expect(declaration[:mutating]).to be(false), "#{action} is declared mutating — identity writes are operator-only"
      end
    end

    it "carries readOnlyHint on the wire for every verb" do
      catalog = ::Mcp::ToolCatalog.new(protocol_version: ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.max)
      entries = catalog.list_entries.index_by { |t| t["name"] }

      advertised_actions.each do |action|
        entry = entries["platform.#{action}"]
        expect(entry).not_to be_nil, "platform.#{action} is not in the catalog"
        expect(entry["annotations"]).to include("readOnlyHint" => true), "platform.#{action} carries no read-only hint"
      end
    end

    it "names a catalogued permission on every action, and floors on the REST door's own names" do
      expect(::Permissions.permission_exists?(described_class::REQUIRED_PERMISSION)).to be true
      described_class::ACTION_PERMISSIONS.each_value do |permission|
        expect(::Permissions.permission_exists?(permission)).to be true
      end
      expect(described_class::ACTION_PERMISSIONS).to eq(
        "list_users" => "admin.user.read",
        "get_user" => "admin.user.read",
        "list_roles" => "admin.role.read",
        "list_permissions" => "admin.role.read",
        "list_audit_logs" => "audit.read"
      )
    end
  end

  describe "permission enforcement, per verb" do
    it "refuses EVERY verb when the caller holds no permission at all" do
      stranger = actor
      sample_calls(user_id: first_user.id).each do |params|
        result = stranger.execute(params: params)
        expect(result[:success]).to be(false), "#{params[:action]} was allowed with no permission"
        expect(result[:data]).to be_nil
      end
    end

    # The arm that catches a tool flooring every verb on one permission: a
    # caller holding ONLY admin.user.read reaches the user verbs and nothing
    # else. A single shared gate would let all five through here.
    it "gates each verb on its OWN permission, not a shared floor" do
      user_reader = actor("admin.user.read")
      expect(user_reader.execute(params: { action: "list_users" })[:success]).to be true
      expect(user_reader.execute(params: { action: "get_user", id: first_user.id })[:success]).to be true
      expect(user_reader.execute(params: { action: "list_roles" })[:success]).to be false
      expect(user_reader.execute(params: { action: "list_audit_logs" })[:success]).to be false

      role_reader = actor("admin.role.read")
      expect(role_reader.execute(params: { action: "list_roles" })[:success]).to be true
      expect(role_reader.execute(params: { action: "list_permissions" })[:success]).to be true
      expect(role_reader.execute(params: { action: "list_users" })[:success]).to be false

      audit_reader = actor("audit.read")
      expect(audit_reader.execute(params: { action: "list_audit_logs" })[:success]).to be true
      expect(audit_reader.execute(params: { action: "list_users" })[:success]).to be false
    end

    it "allows every verb for a caller holding all three read permissions" do
      full = actor("admin.user.read", "admin.role.read", "audit.read")
      sample_calls(user_id: first_user.id).each do |params|
        expect(full.execute(params: params)[:success]).to be(true), "#{params[:action]} was refused for a holder"
      end
    end

    it "names the missing permission in the refusal so a caller can ask for the right one" do
      expect(actor.execute(params: { action: "list_audit_logs" })[:error]).to include("audit.read")
      expect(actor.execute(params: { action: "list_users" })[:error]).to include("admin.user.read")
    end
  end

  describe "list_users / get_user" do
    let(:tool) { actor("admin.user.read") }

    it "lists this account's users and never another account's" do
      mine = create(:user, account: account, name: "Mine Person")
      theirs = create(:user, account: other_account, name: "Theirs Person")

      result = tool.execute(params: { action: "list_users" })
      ids = result.dig(:data, :users).map { |u| u[:id] }

      expect(ids).to include(mine.id)
      expect(ids).not_to include(theirs.id)
      expect(result.to_json).not_to include("Theirs Person")
      expect(result.to_json).not_to include(theirs.email)
    end

    it "404s another account's user rather than confirming it exists" do
      foreign = create(:user, account: other_account)

      result = tool.execute(params: { action: "get_user", id: foreign.id })
      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end

    it "filters by status, both arms" do
      wanted = create(:user, account: account, name: "Findable Person", status: "inactive")
      create(:user, account: account, name: "Other Person", status: "active")

      ids = tool.execute(params: { action: "list_users", status: "inactive" })
                .dig(:data, :users).map { |u| u[:id] }
      expect(ids).to eq([ wanted.id ])
    end

    # `email` is encrypted DETERMINISTICALLY, so equality works; `name` is not,
    # so no substring search is offered at all. Both arms, plus the arm that
    # proves the filter is real rather than a pass-through.
    it "filters by exact email and is case-insensitive" do
      wanted = create(:user, account: account, email: "findable@example.test")
      other = create(:user, account: account, email: "other@example.test")

      %w[findable@example.test FINDABLE@EXAMPLE.TEST].each do |needle|
        ids = tool.execute(params: { action: "list_users", email: needle })
                  .dig(:data, :users).map { |u| u[:id] }
        expect(ids).to eq([ wanted.id ]), "email filter failed for #{needle}"
        expect(ids).not_to include(other.id)
      end

      expect(tool.execute(params: { action: "list_users", email: "nobody@example.test" })
                 .dig(:data, :users)).to be_empty
    end

    it "returns roles, and permission names only on the detail verb" do
      member = create(:user, :member, account: account)

      listed = tool.execute(params: { action: "list_users" })
                   .dig(:data, :users).find { |u| u[:id] == member.id }
      expect(listed[:roles].map { |r| r[:name] }).to eq([ "member" ])
      expect(listed).not_to have_key(:permissions)

      detail = tool.execute(params: { action: "get_user", id: member.id }).dig(:data, :user)
      expect(detail[:permissions]).to include("platform.status.read")
    end

    # THE SECRET ORACLE. Not "is the key absent" — that passes if the
    # serializer renames it. Grep the rendered JSON for the ACTUAL secret
    # values this user carries.
    it "leaks no authentication material for any user, in either verb" do
      subject_user = create(:user, account: account)
      digest = subject_user.password_digest
      expect(digest).to be_present, "the factory stopped setting a password — this oracle would pass vacuously"

      listed = tool.execute(params: { action: "list_users" }).to_json
      detailed = tool.execute(params: { action: "get_user", id: subject_user.id }).to_json

      [ listed, detailed ].each do |body|
        expect(body).not_to include(digest)
        expect(body).not_to include(TestUsers::PASSWORD)
        %w[password_digest encrypted_password otp_secret two_factor reset_password_token
           confirmation_token session_token jwt].each do |forbidden|
          expect(body).not_to include(forbidden)
        end
      end
    end
  end

  describe "list_roles" do
    let(:tool) { actor("admin.role.read") }

    it "returns global and account-scoped roles, and scopes them both ways" do
      custom = create(:role, name: "custom_role_for_this_account", account_id: account.id)

      all = tool.execute(params: { action: "list_roles", limit: 500 }).dig(:data, :roles)
      expect(all.map { |r| r[:name] }).to include("member", custom.name)

      globals = tool.execute(params: { action: "list_roles", scope: "global", limit: 500 }).dig(:data, :roles)
      expect(globals.map { |r| r[:scope] }.uniq).to eq([ "global" ])
      expect(globals.map { |r| r[:name] }).not_to include(custom.name)

      # The ad-hoc `test_role_*` rows the user factory mints for a
      # `permissions:` actor are ALSO account-scoped, so this asserts
      # membership and the scope label rather than an exact list.
      scoped = tool.execute(params: { action: "list_roles", scope: "account", limit: 500 }).dig(:data, :roles)
      expect(scoped.map { |r| r[:name] }).to include(custom.name)
      expect(scoped.map { |r| r[:scope] }.uniq).to eq([ "account" ])
      expect(scoped.map { |r| r[:name] }).not_to include("member")
    end

    it "never returns another account's custom role" do
      foreign = create(:role, name: "foreign_role_other_account", account_id: other_account.id)

      body = tool.execute(params: { action: "list_roles", limit: 500 }).to_json
      expect(body).not_to include(foreign.name)
    end

    it "refuses an unknown scope instead of silently listing everything" do
      result = tool.execute(params: { action: "list_roles", scope: "everything" })
      expect(result[:success]).to be false
      expect(result[:error]).to include("scope must be one of")
    end

    it "carries each role's permission names" do
      roles = tool.execute(params: { action: "list_roles", scope: "global", limit: 500 }).dig(:data, :roles)
      member = roles.find { |r| r[:name] == "member" }
      expect(member[:permissions]).to include("platform.status.read")
    end
  end

  describe "list_permissions" do
    let(:tool) { actor("admin.role.read") }

    it "returns the code-defined catalog with descriptions, and filters by prefix both ways" do
      all = tool.execute(params: { action: "list_permissions" })
      expect(all.dig(:data, :count)).to eq(::Permissions.all_permissions.size)
      entry = all.dig(:data, :permissions).find { |p| p[:name] == "platform.status.read" }
      expect(entry[:description]).to include("component status plane")

      filtered = tool.execute(params: { action: "list_permissions", prefix: "platform." })
      names = filtered.dig(:data, :permissions).map { |p| p[:name] }
      expect(names).to include("platform.status.read")
      expect(names).not_to include("audit.read")
      expect(names.size).to be < ::Permissions.all_permissions.size
    end
  end

  describe "list_audit_logs" do
    let(:tool) { actor("audit.read") }

    # `action` and `source` are validated against AuditActions.all_actions /
    # .all_sources (391 registered actions), and severity/risk_level against a
    # four-value list — so this uses the factory's own vocabulary rather than
    # invented strings, which the model rejects.
    def audit_row(**attrs)
      create(:audit_log, **{ account: account, user: first_user, severity: "low", risk_level: "low" }.merge(attrs))
    end

    it "returns this account's rows and never another account's" do
      audit_row(action: "create", resource_id: "mine-resource")
      create(:audit_log, account: other_account, action: "delete", resource_id: "theirs-resource",
                         severity: "low", risk_level: "low")

      result = tool.execute(params: { action: "list_audit_logs" })
      resources = result.dig(:data, :audit_logs).map { |r| r[:resource_id] }
      expect(resources).to include("mine-resource")
      expect(result.to_json).not_to include("theirs-resource")
    end

    it "filters by audited action, resource type and risk level, both arms" do
      audit_row(action: "create", resource_type: "Widget", resource_id: "wanted", risk_level: "high")
      audit_row(action: "delete", resource_type: "Gadget", resource_id: "unwanted", risk_level: "low")

      def refs(result) = result.dig(:data, :audit_logs).map { |r| r[:resource_id] }

      expect(refs(tool.execute(params: { action: "list_audit_logs", audit_action: "create" }))).to eq([ "wanted" ])
      expect(refs(tool.execute(params: { action: "list_audit_logs", resource_type: "Widget" }))).to eq([ "wanted" ])
      expect(refs(tool.execute(params: { action: "list_audit_logs", risk_level: "low" }))).to eq([ "unwanted" ])
    end

    it "refuses an unparseable `since` rather than ignoring the bound" do
      audit_row
      result = tool.execute(params: { action: "list_audit_logs", since: "last tuesday" })
      expect(result[:success]).to be false
      expect(result[:error]).to include("ISO8601")
    end

    it "honours a valid `since`, both arms" do
      old = audit_row(resource_id: "old-row")
      old.update_column(:created_at, 3.days.ago)
      audit_row(resource_id: "new-row")

      result = tool.execute(params: { action: "list_audit_logs", since: 1.day.ago.iso8601 })
      resources = result.dig(:data, :audit_logs).map { |r| r[:resource_id] }
      expect(resources).to include("new-row")
      expect(resources).not_to include("old-row")
    end

    # THE SECRET ORACLE FOR THE AUDIT LOG. `metadata` has no redaction filter
    # of its own (only old_values/new_values do), so it is withheld entirely.
    # Asserted by planting a real secret in it and grepping the response.
    it "never returns the unredacted metadata column" do
      planted = "sk-live-#{SecureRandom.hex(16)}"
      row = audit_row(resource_id: "leaky-row", metadata: { "context" => { "api_key" => planted } })
      expect(row.reload.metadata.dig("context", "api_key")).to eq(planted),
                                                               "the row did not store the planted secret — this oracle would pass vacuously"

      body = tool.execute(params: { action: "list_audit_logs" }).to_json
      expect(body).to include("leaky-row")
      expect(body).not_to include(planted)
      expect(body).not_to include("metadata")
    end

    it "does return old_values and new_values, which the model redacts at write time" do
      # `status`, not `name`: User.filter_attributes lists :name and :email, so
      # a `name` key is legitimately rewritten to [FILTERED] by the model's own
      # redaction — using it here would have asserted the wrong thing.
      audit_row(old_values: { "status" => "before" }, new_values: { "status" => "after" })

      row = tool.execute(params: { action: "list_audit_logs" }).dig(:data, :audit_logs).first
      expect(row[:old_values]).to eq("status" => "before")
      expect(row[:new_values]).to eq("status" => "after")
    end

    # The other arm of the same rule: the redaction the tool RELIES ON is live.
    # Without this, "old_values passes through" would be indistinguishable from
    # "old_values is unredacted", which is the failure mode that matters.
    it "passes through the model's redaction rather than around it" do
      audit_row(new_values: { "name" => "Real Name", "status" => "active" })

      row = tool.execute(params: { action: "list_audit_logs" }).dig(:data, :audit_logs).first
      expect(row[:new_values]["name"]).to eq("[FILTERED]")
      expect(row[:new_values]["status"]).to eq("active")
    end
  end

  it "refuses an action it does not advertise" do
    expect(actor("admin.user.read").execute(params: { action: "delete_user" })[:success]).to be false
  end
end
