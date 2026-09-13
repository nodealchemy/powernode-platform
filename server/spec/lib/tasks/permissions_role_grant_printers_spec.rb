# frozen_string_literal: true

require "rails_helper"
require "rake"

# IMP-01a06af0 — the OPERATOR-run role-grant doors say what the boot door says.
#
# IMP-222dd9bce564 gave Permissions::RoleGrantReconciler a ledger so a
# re-creation that UNDOES a revocation could be told apart from a grant that
# never landed, and wired it into the hub image's per-boot
# role-grants-reconcile.rb: its own `RE-CREATED grant (reversal)` line plus a
# System::FleetEvent. It left `Result#recreated_grants` and
# `DriftReport#previously_held` unread by the two rake tasks, and said so —
# "Wiring both printers to these members is a follow-up in
# lib/tasks/permissions.rake; do not describe the rake output as
# distinguishing them until it does."
#
# So an operator running the tasks BY HAND — the documented remediation, and
# the only door on an install with no hub image — saw one undifferentiated
# `+ grant` per creation and one undifferentiated `MISSING` per absent grant.
# The one case the ledger exists to surface, a deliberate revocation being
# silently undone, was invisible at exactly the door a human is watching.
#
# THE ORACLE IS THE THREE-STATE SEQUENCE from
# role_grant_reconciler_reversal_spec: reconcile (creates), revoke, reconcile
# again. A single pass cannot see the defect — asserting only that the reversal
# wording appears would pass on a printer that says it for every creation, so
# every example below pins BOTH halves: the reversal line present on the second
# pass and ABSENT on the first, and the plain line the other way round.
#
# THE LEDGER-DEGRADED HALF. `reconcile!` carries `Result#ledger_error` and the
# boot runner prints it, because a ledger fault makes `recreated_grants=0` mean
# "detection is broken", not "nothing was reversed". `drift` discarded the same
# error (`ledger, _error = load_ledger`), so an unreadable ledger made
# `previously_held` come back EMPTY and the report read clean in precisely the
# case the ledger exists to catch. DriftReport now carries it too, and both
# tasks say so.
RSpec.describe "permissions role-grant rake printers (IMP-01a06af0)" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("permissions:reconcile_role_grants") }

  let(:new_permission) { "spec.role_grant_printers.widget" }
  let(:key) { "admin/#{new_permission}" }
  let(:admin_role) { Role.find_by!(name: "admin", account_id: nil) }

  def register!
    Permissions.register_permissions(new_permission => "Spec-only permission")
    Permissions.register_role_permissions("admin", [ new_permission ])
  end

  after do
    Permissions.extension_permissions.delete(new_permission)
    Permissions.extension_role_permissions["admin"]&.delete(new_permission)
  end

  def revoke!
    admin_role.role_permissions.where(permission_name: new_permission).delete_all
  end

  # Both tasks print to a mix of $stdout and $stderr and one of them exits 1;
  # capture both streams together and swallow the SystemExit so the exit code
  # is not the assertion (the LINES are).
  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    out = StringIO.new
    err = StringIO.new
    original_out, original_err = $stdout, $stderr
    $stdout, $stderr = out, err
    begin
      task.invoke
    rescue SystemExit
      nil
    ensure
      $stdout, $stderr = original_out, original_err
    end
    out.string + err.string
  end

  def reconcile_output = run_task("permissions:reconcile_role_grants")
  def drift_output     = run_task("permissions:role_grant_drift")

  describe "permissions:reconcile_role_grants" do
    it "calls the second creation a REVERSAL and the first a plain creation" do
      register!
      revoke!

      # State 1 -> 2: never landed. A plain `+ grant`, and NO reversal wording.
      first = reconcile_output
      expect(first).to include("+ grant #{key}")
      expect(first).not_to match(/RE-CREATED/i)

      # State 2 -> 3: revoked outside the catalog, then reconciled again.
      revoke!
      second = reconcile_output

      expect(second).to match(/RE-CREATED grant \(reversal\): #{Regexp.escape(key)}/)
      # The remediation an operator needs on seeing it: deleting the row again
      # will not hold.
      expect(second).to include("remove the grant from the catalog")
      # Not ALSO printed as an ordinary creation — one row, one line.
      expect(second).not_to include("+ grant #{key}")
    end
  end

  describe "permissions:role_grant_drift" do
    it "separates a grant that never landed from one this deployment HELD" do
      register!
      revoke!

      # Never landed: an undifferentiated MISSING, and no reversal wording.
      first = drift_output
      expect(first).to include("MISSING #{key}")
      expect(first).not_to match(/previously held/i)

      # Land it (which writes the ledger), then revoke outside the catalog.
      reconcile_output
      revoke!

      second = drift_output
      expect(second).to match(/MISSING #{Regexp.escape(key)}.*previously held/i)
      expect(second).to include("remove the grant from the catalog")
    end
  end

  # A ledger fault must not read as "no reversals" at EITHER door.
  describe "when the ledger cannot be read" do
    # A REAL fault, not a stub: the ledger row exists but does not parse. That
    # is the shape #load_ledger actually rescues, and it keeps this example
    # independent of which accessor the reconciler reads the row through.
    before do
      row = SiteSetting.find_or_initialize_by(key: Permissions::RoleGrantReconciler::LEDGER_SETTING)
      row.value = "{not json"
      row.save!(validate: false)
    end

    it "says the reversal signal is DEGRADED on the reconcile door" do
      register!
      revoke!

      expect(reconcile_output).to match(/ledger unavailable \(reversal detection degraded\)/i)
    end

    it "says the reversal signal is DEGRADED on the drift door" do
      register!
      revoke!

      expect(drift_output).to match(/ledger unavailable \(reversal detection degraded\)/i)
    end
  end
end
