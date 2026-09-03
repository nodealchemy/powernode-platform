# frozen_string_literal: true

require 'rails_helper'

# IMP-ee308f92ea6a — the ROLE-side residue of the delegation escalation fixes.
#
# 4da742156 gated what a delegation may carry, splitting the question in two:
# custom permission NAMES are bound by User#grantable_permission_names (applied
# in the service), and a whole ROLE is bound by Role#assignable_by? (applied
# only by Api::V1::DelegationsController#authorize_delegated_role!). 9f56d08b6
# and 27bf93398 then closed the widening and the staleness on the NAME half.
# Nothing moved the ROLE half below the controller.
#
# WHY THE ROLE HALF MATTERS AT ALL, given 27bf93398 bounds the explicit set by
# the live role: because a delegation with an EMPTY custom set falls back to the
# role's FULL permission set (Account::Delegation#configured_permissions_for).
# For such a row the role IS the authority, so changing it is the same authority
# transfer as assigning the role — and Accounts::DelegationService applied only
# a `name == "Owner"` check to it.
#
# ORACLES. Every escalation assertion here is on the resolved EFFECTIVE SET, not
# on delegation_permissions rows and not on a result hash alone: the rows are
# what shrink when the set grows, so a row-level assertion is blind to this
# family by construction. And #effective_permissions answers [] for any
# NON-ACTIVE row, so each example that reads it either asserts the row is active
# or drives the row through activation first — otherwise the assertion would
# pass vacuously on a refusal AND on a crash.
RSpec.describe Accounts::DelegationService, type: :service do
  let(:account) { create(:account) }
  let(:external_account) { create(:account) }
  let(:delegated_user) { create(:user, account: external_account) }

  # Real catalog permissions. `held` is one the manager role actually grants;
  # `unheld` is the escalation target the delegator must never be able to confer.
  let(:held_permission) { 'report.generate' }
  let(:also_held_permission) { 'report.export' }
  let(:unheld_permission) { 'admin.user.delete' }

  # A REAL seeded role, not a `permissions: [...]` synthetic actor: the
  # conferral rule reads the delegator's whole permission set, and a synthetic
  # holder is structurally blind to the catalog grants that decide it.
  let(:delegator) do
    user = create(:user, :manager, account: account)
    role = user.roles.first
    role.role_permissions.find_or_create_by!(permission_name: 'accounts.manage')
    role.role_permissions.find_or_create_by!(permission_name: held_permission)
    role.role_permissions.find_or_create_by!(permission_name: also_held_permission)
    user.reload
    user
  end

  let(:service) { described_class.new(delegator, account) }

  # Every permission on this role is one the delegator holds => assignable.
  let(:safe_role) do
    role = create(:role, name: 'conferral.safe', display_name: 'Conferral Safe', role_type: 'user')
    role.role_permissions.find_or_create_by!(permission_name: held_permission)
    role
  end

  # Carries a permission the delegator does NOT hold => not assignable by it.
  let(:escalating_role) do
    role = create(:role, name: 'conferral.escalating', display_name: 'Conferral Escalating', role_type: 'user')
    role.role_permissions.find_or_create_by!(permission_name: held_permission)
    role.role_permissions.find_or_create_by!(permission_name: unheld_permission)
    role
  end

  # POSITIVE CONTROLS. Without these, every refusal example below would pass for
  # the wrong reason — an actor with no permission rows at all refuses
  # everything, and an inactive row resolves to [] whatever the guard does.
  describe 'premises' do
    it 'the delegator holds the safe permissions and not the escalation target' do
      expect(delegator.has_permission?(held_permission)).to be(true),
        'the manager role is not carrying report.generate; the positive examples would pass vacuously'
      expect(delegator.has_permission?(also_held_permission)).to be true
      expect(delegator.has_permission?(unheld_permission)).to be false
      expect(delegator.has_permission?('system.admin')).to be false
      expect(delegator.has_permission?('admin.access')).to be false
    end

    it 'the safe role is conferrable by the delegator and the escalating role is not' do
      expect(safe_role.assignable_by?(delegator)).to be true
      expect(escalating_role.assignable_by?(delegator)).to be false
    end

    it 'the escalating role genuinely carries the escalation target' do
      expect(escalating_role.permission_names).to include(unheld_permission)
    end
  end

  # ITEM 1. A role change on a role-ONLY delegation replaces the delegation's
  # entire authority. The service applied no conferral rule to it.
  describe '#update_delegation with a role change' do
    let(:delegation) do
      create(:account_delegation, :active, account: account, delegated_by: delegator,
                                           delegated_user: delegated_user, role: safe_role)
    end

    it 'starts from an ACTIVE role-only row whose effective set is really the role' do
      # Non-vacuity guard for every example in this group: the assertions below
      # read #effective_permissions, which is [] for any non-active row.
      expect(delegation).to be_active
      expect(delegation.permission_names).to be_empty
      expect(delegation.effective_permissions).to contain_exactly(held_permission)
    end

    it 'refuses to move the delegation onto a role the delegator cannot confer' do
      result = service.update_delegation(delegation: delegation, role_id: escalating_role.id)

      expect(result[:success]).to be false
      expect(result[:errors].join(' ')).to include(escalating_role.name)

      delegation.reload
      expect(delegation).to be_active
      expect(delegation.role).to eq(safe_role)
      expect(delegation.effective_permissions).not_to include(unheld_permission)
      expect(delegation.effective_permissions).to contain_exactly(held_permission)
    end

    # NO-LOCKOUT: the ordinary, legitimate role change must still work.
    it 'still moves the delegation onto a role the delegator can confer' do
      other_safe = create(:role, name: 'conferral.safe_two', display_name: 'Conferral Safe Two', role_type: 'user')
      other_safe.role_permissions.find_or_create_by!(permission_name: also_held_permission)

      result = service.update_delegation(delegation: delegation, role_id: other_safe.id)

      expect(result[:success]).to be true
      delegation.reload
      expect(delegation).to be_active
      expect(delegation.effective_permissions).to contain_exactly(also_held_permission)
    end

    # NO-LOCKOUT, and the reason this half is Role#assignable_by? rather than the
    # grantable (held-minus-system-tier) rule: extensions register real system.*
    # names onto the seeded global admin/manager roles, so a grantable-based test
    # would make the platform's broadest roles undelegatable by everyone,
    # including a system.admin holder.
    it 'still lets an admin move the delegation onto a seeded global role carrying system-tier permissions' do
      admin_delegator = create(:user, :admin, account: account)
      global_admin_role = Role.find_by(name: 'admin')
      expect(global_admin_role).to be_present
      expect(global_admin_role.permission_names.select { |n| n.start_with?('system.') }).not_to be_empty

      result = described_class.new(admin_delegator, account)
                              .update_delegation(delegation: delegation, role_id: global_admin_role.id)

      expect(result[:success]).to be true
      expect(delegation.reload.role).to eq(global_admin_role)
    end
  end

  # SAME RULE ON THE MINT PATH. 4da742156 put this check in the controller only,
  # so a non-controller caller of create_delegation skips it exactly as
  # update_delegation's caller would — iteration 518's rule.
  describe '#create_delegation with a role' do
    it 'refuses to mint a delegation on a role the delegator cannot confer' do
      expect {
        result = service.create_delegation(delegated_user_email: delegated_user.email,
                                           role_id: escalating_role.id)
        expect(result[:success]).to be false
      }.not_to change(Account::Delegation, :count)

      conferred = Account::Delegation.for_user(delegated_user).flat_map(&:effective_permissions)
      expect(conferred).not_to include(unheld_permission)
    end

    it 'still mints a delegation on a role the delegator can confer' do
      result = service.create_delegation(delegated_user_email: delegated_user.email, role_id: safe_role.id)

      expect(result[:success]).to be true
      minted = result[:delegation]
      expect(minted).to be_active
      expect(minted.effective_permissions).to contain_exactly(held_permission)
    end

    # The role check sits AHEAD of the custom-permission block, so this is the
    # happy path that proves it does not swallow a legitimate role+custom mint.
    it 'still mints a delegation with a conferrable role AND a narrower custom set' do
      safe_role.role_permissions.find_or_create_by!(permission_name: also_held_permission)

      result = service.create_delegation(delegated_user_email: delegated_user.email,
                                         role_id: safe_role.id,
                                         permission_names: [ held_permission ])

      expect(result[:success]).to be true
      minted = result[:delegation]
      expect(minted).to be_active
      # Narrowed to the custom set, not promoted to the whole role.
      expect(minted.effective_permissions).to contain_exactly(held_permission)
    end

    # THE FORWARD/LEGACY SPLIT, asserted in both directions so the two answers
    # this file gives about the same row shape are deliberate and visible.
    #
    # A custom+role row whose role the delegator cannot confer may NOT be minted
    # (here) — matching the controller, and stricter than strictly necessary,
    # since such a row's effective set is bounded by its custom set either way.
    # But a row that ALREADY EXISTS in that shape must still activate: see
    # '#activate_delegation and the role on a custom+role row' below.
    it 'refuses a custom+role mint on an unconferrable role even when every custom name is grantable' do
      expect(delegator.can_grant_permission?(held_permission)).to be true

      expect {
        result = service.create_delegation(delegated_user_email: delegated_user.email,
                                           role_id: escalating_role.id,
                                           permission_names: [ held_permission ])
        expect(result[:success]).to be false
        expect(result[:errors].join(' ')).to include(escalating_role.name)
      }.not_to change(Account::Delegation, :count)
    end
  end

  # ITEM 2. THE DECISION, recorded as executable pins rather than prose.
  #
  # activate_delegation re-checks the CUSTOM set (Accounts::DelegationService
  # #unconferrable_reason) but re-checks the ROLE only on a row with no custom
  # set. The question raised was whether it should also re-vet the role on a
  # custom+role row. It should NOT, and the reason is a property, not a
  # convenience: since 27bf93398 a non-empty custom set is resolved as
  # `custom` filtered BY the role, so on such a row the role can only ever
  # SUBTRACT from the set. It confers nothing the custom set does not already
  # carry, and the custom set is what activation vets.
  #
  # The two rows the brief distinguished therefore get the answer they need
  # without a new guard: a row whose role WAS conferrable at mint and no longer
  # is still activates (below), and a row whose role was NEVER conferrable
  # confers nothing beyond its vetted custom set (below). Re-vetting the role
  # here would buy no narrowing and would strand the first row permanently.
  #
  # These are PINS, not red-first oracles — they pass before the fix. Be precise
  # about what they pin, because it is easy to overclaim here: they pin the
  # DECISION (adding a role re-check to the custom branch reddens the first
  # example), NOT the role filter in #configured_permissions_for. Deleting that
  # filter leaves every example in this file green, because it can only ever
  # subtract — before IMP-7964b5d261b4 the method read `return custom if
  # custom.any?`, so removing the filter returns `custom` verbatim rather than
  # the role. The filter has its own pins in spec/models/account_delegation_spec.rb
  # ('explicit custom set bounded by the live role'). What actually stands
  # between a custom+role row and its role is the fallback KEY — only an EMPTY
  # custom set resolves from the role.
  describe '#activate_delegation and the role on a custom+role row' do
    let(:custom_and_role_delegation) do
      delegation = create(:account_delegation, :inactive, account: account, delegated_by: delegator,
                                                          delegated_user: delegated_user, role: escalating_role)
      delegation.delegation_permissions.create!(permission_name: held_permission)
      delegation
    end

    # The LEGACY half of the split asserted in the create group: this row can no
    # longer be minted, but one that already exists must still go live.
    it 'activates a row whose role the activator could never confer, carrying only the vetted custom set' do
      expect(escalating_role.assignable_by?(delegator)).to be false

      result = service.activate_delegation(custom_and_role_delegation)

      expect(result[:success]).to be true
      custom_and_role_delegation.reload
      # Asserted alongside the set, so a vacuous [] from a refusal cannot pass.
      expect(custom_and_role_delegation).to be_active
      expect(custom_and_role_delegation.effective_permissions).to contain_exactly(held_permission)
      expect(custom_and_role_delegation.effective_permissions).not_to include(unheld_permission)
    end

    # The security case is already carried by the CUSTOM-set check, and it must
    # keep biting: a row whose custom set exceeds the activator does not go live.
    it 'still refuses a row whose custom set exceeds the activator' do
      delegation = create(:account_delegation, :inactive, account: account, delegated_by: delegator,
                                                          delegated_user: delegated_user, role: escalating_role)
      delegation.delegation_permissions.create!(permission_name: unheld_permission)

      result = service.activate_delegation(delegation)

      expect(result[:success]).to be false
      expect(delegation.reload).not_to be_active
      expect(delegation.effective_permissions).to be_empty
    end

    # And the role-ONLY row, where the role IS the authority, keeps its existing
    # role re-check.
    it 'still refuses a role-only row whose role the activator cannot confer' do
      delegation = create(:account_delegation, :inactive, account: account, delegated_by: delegator,
                                                          delegated_user: delegated_user, role: escalating_role)

      result = service.activate_delegation(delegation)

      expect(result[:success]).to be false
      expect(delegation.reload).not_to be_active
      expect(delegation.effective_permissions).not_to include(unheld_permission)
    end
  end

  # ITEM 3. #assign_permission returned true unconditionally after a bare
  # `create`, so any record that failed to persist was reported as a success.
  # The return value is load-bearing: update_delegation's rewrite loop rolls the
  # whole transaction back on a false, and a silent success there leaves the
  # custom set EMPTY — which falls back to the role
  # (Account::Delegation#role_backed_permissions), the exact promotion
  # 9f56d08b6 exists to prevent.
  describe 'Account::Delegation#assign_permission return contract' do
    let(:role_less_delegation) do
      create(:account_delegation, :active, account: account, delegated_by: delegator,
                                           delegated_user: delegated_user, role: nil)
    end

    it 'reports false when the permission row does not persist' do
      # A blank name is the REACHABLE instance of the unsaved-record path: it
      # fails the presence validation. The before_create :abort in
      # Account::DelegationPermission is the unreachable one — #assign_permission
      # has its own role-scope early return ahead of it — so it cannot be used
      # to drive this without editing the model under test.
      expect(role_less_delegation.assign_permission('')).to be false

      role_less_delegation.reload
      expect(role_less_delegation.permission_names).to be_empty
      expect(role_less_delegation.configured_permissions).to be_empty
      expect(role_less_delegation.effective_permissions).to be_empty
    end

    it 'still reports true for an assignment that persists' do
      expect(role_less_delegation.assign_permission(held_permission)).to be true
      expect(role_less_delegation.reload.effective_permissions).to contain_exactly(held_permission)
    end
  end
end
