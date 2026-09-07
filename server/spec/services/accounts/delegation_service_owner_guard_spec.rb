# frozen_string_literal: true

require 'rails_helper'

# IMP-e85001682ade — "Cannot delegate Owner role" has never refused anything.
#
# Accounts::DelegationService guarded the owner role by comparing Role#name to
# the string "Owner" at three sites — now Role::OWNER at :46, :170 and :368,
# plus a fourth arm at :668 covering activation. Role#name holds the canonical
# lowercase KEY; the display form is "Account Owner". So the literal matched
# NEITHER column and the comparison was false for every role that exists.
#
# (Those line numbers moved by 15 when Role::OWNER was added above
# #assignable_by?, and the first version of this header shipped the pre-fix
# numbers — the same "reference that names nothing" defect this spec exists to
# close, in the artifact documenting it. Cited by SYMBOL below wherever a
# symbol will do.)
#
# WHY THAT IS NOT MERELY DEAD DEFENSIVE CODE. The task direction required this
# be settled rather than assumed, because the answer decides the severity: does
# the Role#assignable_by? check immediately below (:44-46) independently refuse
# the owner role?
#
# It does not, and the reason is structural rather than incidental:
#   * `owner` is role_type "user" (config/permissions.rb), NOT a system role, so
#     the system-role gate in Role#assignable_by? never engages;
#   * the remaining test is a SUBSET test — the delegator must hold every
#     permission the role grants;
#   * an account owner holds every owner permission by definition, so they pass
#     it trivially.
#
# The delegator best positioned to confer ownership is therefore exactly the one
# the subset test waves through. The guard fails OPEN, which is what separates
# this from its siblings: Account::Delegation#can_manage_account? carries the
# same casing defect but DENIES, and a capability that always answers false
# surfaces the first time someone needs it.
#
# WHAT THE HOLE IS, PRECISELY — it is not escalation past the delegator.
# Api::V1::RolesController#assign_to_user already confers the owner role through
# the same Role#assignable_by?, so an owner could always hand owner-level
# authority to another MEMBER. What the broken guard added is that
# #create_delegation refuses a delegated_user who is already an account member,
# so this lane conferred owner-level authority on a NON-MEMBER. An
# authority-boundary crossing, not a privilege escalation.
#
# These examples are the red-first proof. Before the fix, the first one fails
# because the delegation is CREATED.
RSpec.describe Accounts::DelegationService, type: :service do
  let(:account)        { create(:account) }
  let(:other_account)  { create(:account) }
  let(:delegated_user) { create(:user, account: other_account) }

  # A real seeded owner, not a synthetic permission holder: the subset test
  # reads the delegator's whole catalog grant set, and a synthetic actor is
  # structurally blind to the very thing that makes this reachable.
  let(:delegator) { create(:user, :owner, account: account) }
  let(:owner_role) { Role.find_by(name: 'owner') }

  let(:service) { described_class.new(delegator, account) }

  describe 'the canonical role key, not the display form' do
    it 'has no role named "Owner" — the literal the guard compares against' do
      # Pins the premise the whole finding rests on. If a role named "Owner"
      # ever exists, the guards below are testing something else.
      expect(Role.find_by(name: 'Owner')).to be_nil
      expect(owner_role).to be_present
      expect(owner_role.display_name).to eq('Account Owner')
    end
  end

  describe '#create_delegation with the owner role' do
    it 'refuses to confer ownership' do
      result = service.create_delegation(
        delegated_user_email: delegated_user.email,
        role_id: owner_role.id
      )

      expect(result[:success]).to be(false)
      expect(result[:errors].join(' ')).to match(/owner/i)
    end

    it 'creates no delegation row' do
      expect {
        service.create_delegation(delegated_user_email: delegated_user.email, role_id: owner_role.id)
      }.not_to change(Account::Delegation, :count)
    end

    # THE DISCRIMINATOR. A refusal on its own does not prove the OWNER guard
    # fired — assignable_by? refuses plenty of roles, and a future change could
    # make it refuse this one for an unrelated reason. Establishing that the
    # subset test passes for this delegator is what shows the owner guard is
    # load-bearing rather than shadowed.
    it 'is refused by the owner guard, not by assignable_by?' do
      expect(owner_role.assignable_by?(delegator)).to be(true),
        'an account owner no longer passes Role#assignable_by? for the owner role — ' \
        'if that is deliberate, the owner guard is now shadowed and this spec is testing nothing'
    end
  end

  # THE FORWARD-ONLY GAP. Repairing create/update closes MINTING, not the rows
  # already minted — and the guard failed open for the life of the feature, so
  # such rows may exist. #activate_delegation gates on #unconferrable_reason,
  # which checked only the grantable rule for a custom set and
  # Role#assignable_by? for a role-only row; neither refuses the owner key, and
  # the custom-set branch returns before the role is looked at at all.
  #
  # So a pre-existing owner delegation could be deactivated and reactivated
  # freely after the fix. Closed by an owner arm ahead of both branches: unlike
  # the rest of #unconferrable_reason, this does not ask what the role
  # CONTRIBUTES beyond the custom set — the owner role must never be attached,
  # whatever sits beside it.
  describe 'a pre-existing owner delegation' do
    # Built by insert, deliberately: create_delegation now refuses this shape,
    # so the only way to obtain the row the guard must catch is the way
    # production obtained it — behind the broken guard.
    let!(:legacy) do
      Account::Delegation.create!(
        account: account,
        delegated_by: delegator,
        delegated_user: delegated_user,
        role: owner_role,
        status: 'inactive',
        expires_at: 1.year.from_now
      )
    end

    it 'cannot be reactivated' do
      result = service.activate_delegation(legacy)

      expect(result[:success]).to be(false)
      expect(result[:errors].join(' ')).to match(/owner/i)
      expect(legacy.reload.status).to eq('inactive')
    end
  end

  describe '#list_available_permissions_for_delegation with the owner role' do
    it 'offers nothing, because the role can never be conferred' do
      expect(service.list_available_permissions_for_delegation(role_id: owner_role.id)).to eq([])
    end
  end
end
