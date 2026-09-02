# frozen_string_literal: true

require "rails_helper"

# IMP-1635cb7fa768 item 2 — WIDENING A ROLE RETROACTIVELY WIDENED EVERY
# DELEGATION MINTED AGAINST IT.
#
# A delegation with an EMPTY custom set falls back to the role's FULL permission
# set (Account::Delegation#configured_permissions_for), read LIVE. For such a row
# the role IS the authority. Conferring it was authorised once, at mint time,
# against the delegator's own permissions (Role#assignable_by?); nothing re-asked
# the question when the role changed underneath. So a SECOND admin editing that
# role — Api::V1::RolesController#update gates on the EDITOR's grantable set,
# never on the delegations already outstanding — silently handed the delegate
# authority its delegator never held and could not have conferred.
#
# THE ANSWER IS THE PROPAGATION QUESTION, NOT THE GATING ONE. Tightening
# RolesController#update alone would narrow who can trigger this and leave the
# propagation unanswered, so the bound is applied where the delegation RESOLVES:
# a role-backed delegation carries the role's live grants INTERSECTED with what
# its delegator actually holds. At mint that intersection is the whole role (the
# conferral guard guarantees the subset), so nothing legitimate changes; after a
# widening it is still the whole role for anything the delegator could itself
# have conferred, and nothing more.
#
# NOT A MINT-TIME SNAPSHOT. Freezing the set at mint would reintroduce
# IMP-7964b5d261b4: the live read is the only reason a role-side REVOKE reaches
# a delegation-borne grant at all. The narrowing example below pins that.
#
# REAL SEEDED ROLES for every actor: the bound reads the delegator's whole
# permission set, and a synthetic `permissions: [...]` holder is structurally
# blind to the catalog grants that decide it.
RSpec.describe "delegation resolution after a role is widened", type: :model do
  let(:account) { create(:account) }
  let(:outsider) { create(:user, account: create(:account)) }

  let(:held_permission) { "report.generate" }
  let(:also_held_permission) { "report.export" }
  let(:unheld_permission) { "admin.user.delete" }

  let(:delegator) do
    user = create(:user, :manager, account: account)
    role = user.roles.first
    role.role_permissions.find_or_create_by!(permission_name: "accounts.manage")
    role.role_permissions.find_or_create_by!(permission_name: held_permission)
    role.role_permissions.find_or_create_by!(permission_name: also_held_permission)
    user.reload
    user
  end

  # Every grant on it is one the delegator holds => conferrable at mint.
  let(:delegated_role) do
    role = create(:role, name: "widening.target", display_name: "Widening Target", role_type: "user")
    role.role_permissions.find_or_create_by!(permission_name: held_permission)
    role
  end

  let(:service) { Accounts::DelegationService.new(delegator, account) }

  # A ROLE-BACKED row: no custom permission names, so it resolves through the
  # role fallback — the branch this defect lives in.
  let(:delegation) do
    result = service.create_delegation(delegated_user_email: outsider.email, role_id: delegated_role.id)
    raise "delegation setup failed: #{result[:errors]&.join(', ')}" unless result[:success]

    result[:delegation]
  end

  # POSITIVE CONTROLS. #effective_permissions answers [] for any non-active row,
  # so without these each assertion below would pass on a refusal AND on a crash.
  describe "premises" do
    it "the delegator holds the role's grants and not the escalation target" do
      expect(delegator.has_permission?(held_permission)).to be(true),
        "the manager role is not carrying #{held_permission}; the examples would pass vacuously"
      expect(delegator.has_permission?(unheld_permission)).to be false
      expect(delegator.has_permission?("system.admin")).to be false
    end

    it "the row is active, role-backed, and carries the role's set" do
      expect(delegation).to be_active
      expect(delegation.permission_names).to be_empty
      expect(delegation.effective_permissions).to include(held_permission)
    end
  end

  describe "a second operator widens the role underneath the delegation" do
    before { delegation }

    it "does not confer a permission the delegator never held" do
      delegated_role.add_permission(unheld_permission)

      expect(delegation.reload.effective_permissions).not_to include(unheld_permission),
        "widening the role retroactively grew what an existing delegation carries"
    end

    it "does not answer has_permission? for it either" do
      delegated_role.add_permission(unheld_permission)

      expect(delegation.reload.has_permission?(unheld_permission)).to be false
    end

    it "keeps carrying what it legitimately carried" do
      delegated_role.add_permission(unheld_permission)

      expect(delegation.reload.effective_permissions).to include(held_permission)
    end
  end

  describe "no lockout" do
    before { delegation }

    it "a widening WITHIN the delegator's own authority still propagates" do
      delegated_role.add_permission(also_held_permission)

      expect(delegation.reload.effective_permissions).to include(also_held_permission)
    end

    it "a role-side REVOKE still propagates (the live read is why this is not a snapshot)" do
      delegated_role.remove_permission(held_permission)

      expect(delegation.reload.effective_permissions).not_to include(held_permission)
    end

    it "a system.admin delegator's delegation carries the whole widened role" do
      other_account = create(:account)
      super_admin = create(:user, :super_admin, account: other_account)
      other_outsider = create(:user, account: create(:account))
      wide_role = create(:role, name: "widening.wide", display_name: "Widening Wide", role_type: "user")
      wide_role.role_permissions.find_or_create_by!(permission_name: held_permission)

      result = Accounts::DelegationService.new(super_admin, other_account).create_delegation(
        delegated_user_email: other_outsider.email, role_id: wide_role.id
      )
      expect(result[:success]).to be(true), "setup failed: #{result[:errors]&.join(', ')}"

      wide_role.add_permission(unheld_permission)

      expect(result[:delegation].reload.effective_permissions).to include(unheld_permission)
    end

    it "an explicit custom set is unaffected by the role fallback bound" do
      other_account = create(:account)
      custom_delegator = create(:user, :manager, account: other_account)
      custom_delegator.roles.first.role_permissions.find_or_create_by!(permission_name: held_permission)
      custom_delegator.reload
      other_outsider = create(:user, account: create(:account))
      custom_role = create(:role, name: "widening.custom", display_name: "Widening Custom", role_type: "user")
      custom_role.role_permissions.find_or_create_by!(permission_name: held_permission)

      result = Accounts::DelegationService.new(custom_delegator, other_account).create_delegation(
        delegated_user_email: other_outsider.email,
        role_id: custom_role.id,
        permission_names: [ held_permission ]
      )
      expect(result[:success]).to be(true), "setup failed: #{result[:errors]&.join(', ')}"

      expect(result[:delegation].reload.effective_permissions).to eq([ held_permission ])
    end
  end
end
