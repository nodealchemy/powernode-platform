# frozen_string_literal: true

require "rails_helper"

# IMP-c043800b3f21 — catalog grants never actuate on an installed platform.
#
# `Role.sync_from_config!` is the ONLY config->DB path for role grants, and all
# three of its non-test callers are first-install-only (db/seeds.rb:86,
# Setup::FirstAdminService — which returns early once super_admin exists — and
# lib/tasks/powernode_setup.rake, which bails when any Account exists). The hub's
# rails-start.sh seeds only behind a durable .db-initialized marker. So every
# catalog grant added after a deployment's first boot is INERT there.
#
# THE ORACLE below therefore starts from a DB state that LACKS the row. A spec
# that starts from the synced state rails_helper builds would prove nothing.
RSpec.describe Permissions::RoleGrantReconciler do
  # A permission name that exists in NO catalog until a test registers it, which
  # is what makes "added to the catalog after this install was seeded" testable.
  new_permission  = "spec.role_grant_reconciler.widget"
  stale_permission = "spec.role_grant_reconciler.retired"

  def register(name, roles: [])
    Permissions.register_permissions(name => "Spec-only permission")
    roles.each { |r| Permissions.register_role_permissions(r, [ name ]) }
  end

  def unregister(name, roles: [])
    Permissions.extension_permissions.delete(name)
    roles.each { |r| Permissions.extension_role_permissions[r].delete(name) }
  end

  after do
    unregister(new_permission, roles: %w[admin])
    unregister(stale_permission, roles: %w[admin])
  end

  let(:admin_role) { Role.find_by!(name: "admin", account_id: nil) }

  describe "#reconcile! — THE ORACLE" do
    it "lands a catalog grant added AFTER this deployment was seeded" do
      # 1. The installed state: the deployment was seeded before the grant existed.
      register(new_permission, roles: %w[admin])
      admin_role.role_permissions.where(permission_name: new_permission).delete_all
      expect(admin_role.reload.has_permission?(new_permission)).to be(false)

      # 2. The mechanism under test — no seed, no manual sync, no migration.
      result = described_class.new.reconcile!

      # 3. The STATE oracle: a real role_permissions row, not a config lookup.
      expect(admin_role.reload.role_permissions.exists?(permission_name: new_permission)).to be(true)
      expect(result.created_grants).to include("admin/#{new_permission}")
    end

    it "makes the grant reachable through User#has_permission?, which reads the TABLE" do
      register(new_permission, roles: %w[admin])
      admin_role.role_permissions.where(permission_name: new_permission).delete_all

      account = create(:account)
      user = create(:user, account: account)
      user.assign_role(admin_role)
      expect(user.has_permission?(new_permission)).to be(false)

      described_class.new.reconcile!

      # has_permission? is an uncached live query against role_permissions —
      # the same oracle the runtime authorization check uses.
      expect(user.reload.has_permission?(new_permission)).to be(true)
    end

    it "is idempotent — a second run creates nothing" do
      register(new_permission, roles: %w[admin])
      admin_role.role_permissions.where(permission_name: new_permission).delete_all

      described_class.new.reconcile!

      # ASSERT THE ROW BEFORE ASSERTING THE COUNTS. Without this line the
      # example cannot tell "idempotent" from "never wrote anything": delete
      # the find_or_create_by! in #reconcile! and both runs create zero, so
      # `second.created == 0` and `second.changed? == false` still hold and
      # this example goes on passing. It survived exactly that mutant.
      expect(admin_role.reload.role_permissions.exists?(permission_name: new_permission)).to be(true)

      second = described_class.new.reconcile!

      expect(second.created).to eq(0)
      expect(second.changed?).to be(false)
      # And the row the FIRST run created is still there — idempotent must mean
      # "no further change", never "undone and not recreated".
      expect(admin_role.reload.role_permissions.exists?(permission_name: new_permission)).to be(true)
    end

    it "creates a global role that the catalog declares but the database lacks" do
      # Without this, a role added to the catalog after first boot has nowhere
      # for its grants to hang, and the reconciler would silently report zero
      # missing grants for it — the "permanently skipped set" trap.
      Role.where(name: "admin", account_id: nil).destroy_all
      expect(Role.exists?(name: "admin", account_id: nil)).to be(false)

      result = described_class.new.reconcile!

      role = Role.find_by(name: "admin", account_id: nil)
      expect(role).to be_present
      expect(result.created_roles).to include("admin")
      expect(role.role_permissions.count).to be > 0

      # The attribute mapping, not just the row's existence: a role created with
      # the wrong role_type or is_system is a different role from the one the
      # catalog declares, and Role#assignable_by? branches on system_role?.
      config = Permissions.all_roles["admin"]
      expect(role.display_name).to eq(config[:display_name])
      expect(role.role_type).to eq(config[:role_type])
      expect(role.is_system).to eq(config[:is_system] || config[:role_type] == "system")
    end
  end

  describe "#reconcile! — THE CONVERSE (decision: grants are PRESERVED, never removed)" do
    it "preserves a DB grant whose permission has left the catalog" do
      register(stale_permission, roles: %w[admin])
      admin_role.role_permissions.create!(permission_name: stale_permission)
      unregister(stale_permission, roles: %w[admin])
      expect(Permissions.permission_exists?(stale_permission)).to be(false)

      described_class.new.reconcile!

      expect(admin_role.reload.role_permissions.exists?(permission_name: stale_permission)).to be(true)
    end

    it "preserves a DB grant the catalog does not give this role" do
      # The permission is in the catalog but is NOT granted to admin. A
      # destructive reconciliation would delete it; absence-only must not.
      register(stale_permission)
      admin_role.role_permissions.create!(permission_name: stale_permission)
      expect(Permissions.permissions_for_role("admin")).not_to include(stale_permission)

      described_class.new.reconcile!

      expect(admin_role.reload.role_permissions.exists?(permission_name: stale_permission)).to be(true)
    end

    it "is the whole difference from Role.sync_from_config!, which DELETES that grant" do
      # Pins WHY this class exists rather than a boot-time sync_from_config!.
      # Note what makes this more than a hypothetical: Permissions.all_permissions
      # is core + LOADED extensions, so a boot that composes without an extension
      # drops every one of its permissions out of the catalog — and a destructive
      # sync would then delete every grant for them.
      register(stale_permission, roles: %w[admin])
      admin_role.role_permissions.create!(permission_name: stale_permission)
      unregister(stale_permission, roles: %w[admin])

      Role.sync_from_config!

      expect(admin_role.reload.role_permissions.exists?(permission_name: stale_permission)).to be(false)
    end
  end

  describe "#reconcile! — SCOPE BOUNDARY" do
    it "never touches account-scoped custom roles" do
      # Population (1) of the prior art's analysis: sync_from_config! iterates
      # only find_or_initialize_by(name:, account_id: nil), so account-scoped
      # roles are unreachable BY CONSTRUCTION. This reconciler keeps that
      # boundary deliberately — widening into it is a separate design question.
      register(new_permission, roles: %w[admin])
      account = create(:account)
      custom = Role.create!(
        name: "spec_custom_role", display_name: "Spec Custom",
        role_type: "user", account_id: account.id
      )
      custom.role_permissions.create!(permission_name: "users.read")

      described_class.new.reconcile!

      expect(custom.reload.permission_names).to eq(%w[users.read])
      expect(custom.role_permissions.exists?(permission_name: new_permission)).to be(false)
    end
  end

  describe "#drift — an UNDECLARED role key cannot be certified clean" do
    # Nothing validates the role key at registration time: register_role_permissions
    # takes any string and the catalog DSL's `grant:` hash autovivifies on any key.
    # each_declared_role only ever yields Permissions.all_roles, so a grant keyed
    # to a name outside it is skipped with NO error, NO failed entry and NO
    # missing_grants entry — and before this, `permissions:role_grant_drift`
    # printed "✅ No role-grant drift" over it. A silent skip wearing an
    # affirmative clean bill is worse than the silence it replaced.
    orphan_role = "spec_role_that_is_not_declared"

    after { Permissions.extension_role_permissions.delete(orphan_role) }

    it "names the undeclared role key and counts it as drift" do
      register(new_permission)
      Permissions.register_role_permissions(orphan_role, [ new_permission ])
      expect(Permissions.all_roles.keys.map(&:to_s)).not_to include(orphan_role)

      report = described_class.new.drift

      expect(report.orphan_grants).to include(orphan_role)
      expect(report).to be_drifted
    end

    it "reports no orphan keys when every grant is keyed to a declared role" do
      # CONTAINMENT half of the pair. Its real target is the filter's DIRECTION:
      # invert `reject { declared.include?(k) }` to `select` and every declared
      # role becomes an "orphan", which the sibling example above cannot see
      # because it only asserts that its own key IS included. A reconcile first,
      # deliberately, because permissions_for_role indexes the autovivifying
      # extension hash and so leaves an empty key for every declared role —
      # this pins that a normal run stays quiet.
      described_class.new.reconcile!

      expect(described_class.new.drift.orphan_grants).to eq([])
    end

    it "also detects an undeclared key registered through the catalog `grant:` hash" do
      # The other grant source. permissions_for_role merges THREE hashes and
      # orphan_grant_keys reads two of them; without this, deleting the
      # catalog_grants branch entirely leaves the suite green.
      Permissions.catalog_grants[orphan_role] << new_permission

      expect(described_class.new.drift.orphan_grants).to include(orphan_role)
    ensure
      Permissions.catalog_grants.delete(orphan_role)
    end

    it "does not report a declared role whose grant list was emptied" do
      # What the empty-list skip ACTUALLY guards (the code comment used to give
      # a different, false reason): a key holding no grants is not an orphan,
      # it is nothing. Registering then emptying leaves exactly that shape.
      Permissions.register_role_permissions(orphan_role, [ new_permission ])
      Permissions.extension_role_permissions[orphan_role].clear

      expect(described_class.new.drift.orphan_grants).not_to include(orphan_role)
    end
  end

  describe "#drift — reports without writing" do
    it "names the missing grant and creates nothing" do
      register(new_permission, roles: %w[admin])
      admin_role.role_permissions.where(permission_name: new_permission).delete_all

      report = described_class.new.drift

      expect(report).to be_drifted
      expect(report.missing_grants).to include("admin/#{new_permission}")
      expect(admin_role.reload.role_permissions.exists?(permission_name: new_permission)).to be(false)
    end

    it "names an out-of-catalog grant as extra WITHOUT counting it as drift" do
      # These are the rows a destructive Role.sync_from_config! would delete.
      # Reporting them is the operator-facing half of the preserve decision;
      # treating them as drift would make the reconciler look obliged to act.
      register(stale_permission, roles: %w[admin])
      admin_role.role_permissions.create!(permission_name: stale_permission)
      unregister(stale_permission, roles: %w[admin])

      report = described_class.new.drift

      expect(report.extra_grants).to include("admin/#{stale_permission}")
      expect(report.missing_grants).not_to include("admin/#{stale_permission}")
      expect(report).not_to be_drifted
    end

    it "reports no drift once reconciled" do
      register(new_permission, roles: %w[admin])
      admin_role.role_permissions.where(permission_name: new_permission).delete_all
      described_class.new.reconcile!

      expect(described_class.new.drift).not_to be_drifted
    end
  end
end
