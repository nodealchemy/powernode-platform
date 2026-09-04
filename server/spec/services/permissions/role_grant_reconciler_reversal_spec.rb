# frozen_string_literal: true

require "rails_helper"

# IMP-222dd9bce564 — the reconciler cannot tell a grant that never landed from
# a grant an operator deliberately revoked.
#
# Both are simply ABSENT at reconcile time, and before this the reconciler held
# no state that separated them: the same `created grant:` line was emitted for a
# first-time creation and for the re-creation that undoes a console
# `Role#remove_permission` five minutes earlier. Nothing marked the second as a
# reversal of a human decision.
#
# THE ORACLE is a THREE-STATE sequence, and a single-pass example cannot see the
# defect: reconcile (creates), delete the row, reconcile again — the second pass
# must report the reversal AND the first must not. Asserting only that the
# signal fires would pass on an implementation that flags every creation.
#
# The behaviour stays ADDITIVE: detection never suppresses the re-creation
# (operator direction — suppression would give the reconciler hidden state that
# silently denies a legitimate catalog grant). Only the REPORTING changes.
RSpec.describe Permissions::RoleGrantReconciler, "reversal reporting (IMP-222dd9bce564)" do
  let(:new_permission) { "spec.role_grant_reversal.widget" }
  let(:key) { "admin/#{new_permission}" }

  def register(name, roles: [])
    Permissions.register_permissions(name => "Spec-only permission")
    roles.each { |r| Permissions.register_role_permissions(r, [ name ]) }
  end

  def unregister(name, roles: [])
    Permissions.extension_permissions.delete(name)
    roles.each { |r| Permissions.extension_role_permissions[r].delete(name) }
  end

  after { unregister(new_permission, roles: %w[admin]) }

  let(:admin_role) { Role.find_by!(name: "admin", account_id: nil) }

  def revoke!
    admin_role.role_permissions.where(permission_name: new_permission).delete_all
  end

  describe "#reconcile! — THE THREE-STATE ORACLE" do
    it "reports the second creation as a reversal and the first as a plain creation" do
      register(new_permission, roles: %w[admin])
      revoke!

      # State 1 -> 2: a grant that never landed. Plain creation, NO signal.
      first = described_class.new.reconcile!
      expect(first.created_grants).to include(key)
      expect(first.recreated_grants).to eq([])
      expect(admin_role.reload.role_permissions.exists?(permission_name: new_permission)).to be(true)

      # State 2 -> 3: an operator revokes it — the console route the class
      # comment names, a raw delete that fires no model callback.
      revoke!
      expect(admin_role.reload.role_permissions.exists?(permission_name: new_permission)).to be(false)

      # A NEW instance: the memory must live in the database, not the object.
      second = described_class.new.reconcile!

      # The signal — and it names the grant, not just a count.
      expect(second.recreated_grants).to eq([ key ])
      # ADDITIVE, not suppressed: the row is back and it is still counted as
      # created. Detection changes what is REPORTED, never what is done.
      expect(second.created_grants).to include(key)
      expect(admin_role.reload.role_permissions.exists?(permission_name: new_permission)).to be(true)
    end

    it "flags a revocation of a grant it merely OBSERVED present, never created" do
      # The realistic case: the grant landed with first-boot db:seed long before
      # the reconciler existed. A ledger of grants the reconciler CREATED would
      # miss exactly the population an operator is most likely to revoke.
      register(new_permission, roles: %w[admin])
      admin_role.role_permissions.find_or_create_by!(permission_name: new_permission)

      observed = described_class.new.reconcile!
      expect(observed.created_grants).not_to include(key)

      revoke!
      result = described_class.new.reconcile!

      expect(result.recreated_grants).to eq([ key ])
    end

    it "stays silent across an ordinary idempotent re-run" do
      # CONTAINMENT half: nothing was deleted, so nothing is a reversal.
      register(new_permission, roles: %w[admin])
      revoke!
      described_class.new.reconcile!

      expect(described_class.new.reconcile!.recreated_grants).to eq([])
    end

    it "does not flag a grant the CATALOG revoked and later re-declared" do
      # The proper revocation route: the grant leaves the catalog, the row is
      # then removed. Re-adding the grant to the catalog months later is a
      # deliberate widening, not a reversal — the memory must be dropped when
      # the catalog itself withdraws the grant.
      register(new_permission, roles: %w[admin])
      revoke!
      described_class.new.reconcile!

      Permissions.extension_role_permissions["admin"].delete(new_permission)
      expect(Permissions.permission_exists?(new_permission)).to be(true)
      described_class.new.reconcile!
      revoke!

      Permissions.register_role_permissions("admin", [ new_permission ])
      result = described_class.new.reconcile!

      expect(result.created_grants).to include(key)
      expect(result.recreated_grants).to eq([])
    end

    it "keeps its memory across a boot that did not compose the grant's extension" do
      # Permissions.all_permissions is process-local. A boot without an extension
      # sees NONE of its permissions — that is "unknown", not "revoked by the
      # catalog", and forgetting the grant there would turn the very next
      # revocation into an unflagged one.
      register(new_permission, roles: %w[admin])
      revoke!
      described_class.new.reconcile!

      unregister(new_permission, roles: %w[admin])
      expect(Permissions.permission_exists?(new_permission)).to be(false)
      described_class.new.reconcile!

      register(new_permission, roles: %w[admin])
      revoke!
      result = described_class.new.reconcile!

      expect(result.recreated_grants).to eq([ key ])
    end
  end

  describe "#reconcile! — a ledger it cannot READ" do
    # SiteSetting.get's json branch is `JSON.parse(setting.value) rescue {}`
    # (app/models/site_setting.rb), so a corrupt value read through it comes
    # back as an EMPTY hash with nothing to say it was corrupt. That is the one
    # state the design forbids: recreated_grants=0 would read as clean, this run
    # would re-record every key as first-seen, and the NEXT revocation would go
    # unflagged. The row is operator-editable through
    # Api::V1::SiteSettingsController#update, so it is reachable.
    let(:corrupt) { "{ not json" }

    before do
      SiteSetting.create!(key: described_class::LEDGER_SETTING, value: corrupt,
                          setting_type: "json", is_public: false)
      register(new_permission, roles: %w[admin])
      revoke!
    end

    it "reports a malformed ledger as an ERROR rather than as an empty one" do
      result = described_class.new.reconcile!

      expect(result.ledger_error).to be_present
      expect(result.ledger_error).to include("malformed")
      # The reconcile itself is unaffected — a ledger fault degrades the
      # signal, it never withholds a catalog grant.
      expect(result.created_grants).to include(key)
      expect(admin_role.reload.role_permissions.exists?(permission_name: new_permission)).to be(true)
    end

    it "does not OVERWRITE memory it could not read" do
      described_class.new.reconcile!

      # Writing this run's observations over an unreadable ledger would replace
      # the deployment's memory with one where every key is first-seen NOW.
      expect(SiteSetting.find_by(key: described_class::LEDGER_SETTING).value).to eq(corrupt)
    end

    it "reads as NO memory in #drift rather than raising" do
      # DriftReport carries no error member, so an unreadable ledger degrades
      # #drift to silence — it names the missing grant but cannot say it was
      # previously held. The read must not raise on the way there.
      expect(described_class.new.drift.previously_held).to eq([])
    end
  end

  describe "#drift — the same memory read from the other direction" do
    it "names a missing grant that was previously held, before the boot undoes the revocation" do
      register(new_permission, roles: %w[admin])
      revoke!
      described_class.new.reconcile!
      revoke!

      report = described_class.new.drift

      expect(report.missing_grants).to include(key)
      expect(report.previously_held).to eq([ key ])
    end

    it "does not name a missing grant that never landed" do
      register(new_permission, roles: %w[admin])
      revoke!

      report = described_class.new.drift

      expect(report.missing_grants).to include(key)
      expect(report.previously_held).to eq([])
    end
  end
end
