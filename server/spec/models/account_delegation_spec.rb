# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Account::Delegation, type: :model do
  let(:account) { create(:account) }
  let(:delegator) { create(:user, account: account) }
  let(:delegated_user) { create(:user, account: account) }
  # Permissions are code-defined; grant real catalog permissions BY NAME.
  ROLE_PERMISSION_NAMES = %w[users.create analytics.read accounts.manage].freeze

  let(:admin_role) do
    role = create(:role, name: 'account.admin', display_name: 'Account Admin', role_type: 'user')
    ROLE_PERMISSION_NAMES.each do |name|
      role.role_permissions.find_or_create_by!(permission_name: name)
    end
    role
  end

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:delegated_user).class_name('User') }
    it { should belong_to(:delegated_by).class_name('User') }
    it { should belong_to(:revoked_by).class_name('User').optional }
    it { should belong_to(:role).optional }
    it { should have_many(:delegation_permissions).dependent(:destroy) }
  end

  describe 'validations' do
    subject { create(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user) }

    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[active inactive revoked]) }

    it 'validates uniqueness of delegated_by_id scoped to account_id and delegated_user_id' do
      create(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user)

      duplicate = build(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:delegated_by_id]).to include('has already delegated to this user for this account')
    end

    it 'allows multiple delegations for different accounts' do
      create(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user)
      other_account = create(:account)
      other_delegator = create(:user, account: other_account)
      other_delegated_user = create(:user, account: other_account)

      expect {
        create(:account_delegation, account: other_account, delegated_by: other_delegator, delegated_user: other_delegated_user)
      }.to change(Account::Delegation, :count).by(1)
    end

    it 'allows multiple delegations for different users in same account' do
      create(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user)
      another_user = create(:user, account: account)

      expect {
        create(:account_delegation, account: account, delegated_by: delegator, delegated_user: another_user)
      }.to change(Account::Delegation, :count).by(1)
    end
  end

  describe 'scopes' do
    # Create all delegations with unique delegated_users
    let!(:active_delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :active, account: account, delegated_by: delegator, delegated_user: user)
    end
    let!(:inactive_delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :inactive, account: account, delegated_by: delegator, delegated_user: user)
    end
    let!(:revoked_delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :revoked, account: account, delegated_by: delegator, delegated_user: user)
    end
    let!(:expired_delegation) do
      user = create(:user, account: account)
      create(:account_delegation, :expired, account: account, delegated_by: delegator, delegated_user: user)
    end
    let(:other_account) { create(:account) }
    let!(:other_account_delegation) do
      other_user = create(:user, account: other_account)
      create(:account_delegation, account: other_account, delegated_by: create(:user, account: other_account), delegated_user: other_user)
    end

    describe '.active' do
      it 'returns only delegations with active status' do
        results = Account::Delegation.active
        expect(results).to include(active_delegation, expired_delegation)
        expect(results).not_to include(inactive_delegation, revoked_delegation)
      end
    end

    describe '.inactive' do
      it 'returns only inactive delegations' do
        expect(Account::Delegation.inactive).to contain_exactly(inactive_delegation)
      end
    end

    describe '.revoked' do
      it 'returns only revoked delegations' do
        expect(Account::Delegation.revoked).to contain_exactly(revoked_delegation)
      end
    end

    describe '.for_account' do
      it 'returns delegations for specific account' do
        expect(Account::Delegation.for_account(account)).to contain_exactly(
          active_delegation, inactive_delegation, revoked_delegation, expired_delegation
        )
      end
    end

    describe '.for_user' do
      it 'returns delegations for specific user' do
        expect(Account::Delegation.for_user(active_delegation.delegated_user)).to contain_exactly(active_delegation)
      end
    end

    describe '.not_expired' do
      it 'returns delegations that have not expired' do
        results = Account::Delegation.not_expired
        expect(results).to include(active_delegation, inactive_delegation, revoked_delegation)
        expect(results).not_to include(expired_delegation)
      end

      it 'includes delegations with nil expires_at' do
        user = create(:user, account: account)
        no_expiry = create(:account_delegation, :no_expiration, account: account, delegated_by: delegator, delegated_user: user)
        expect(Account::Delegation.not_expired).to include(no_expiry)
      end
    end

    describe '.expired' do
      it 'returns only expired delegations' do
        expect(Account::Delegation.expired).to contain_exactly(expired_delegation)
      end

      it 'excludes delegations with nil expires_at' do
        user = create(:user, account: account)
        no_expiry = create(:account_delegation, :no_expiration, account: account, delegated_by: delegator, delegated_user: user)
        expect(Account::Delegation.expired).not_to include(no_expiry)
      end
    end

    describe '.with_role' do
      it 'returns delegations with specific role' do
        role = create(:role, name: 'test.role', display_name: 'Test Role')
        user = create(:user, account: account)
        with_role = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: role)

        expect(Account::Delegation.with_role(role)).to contain_exactly(with_role)
      end
    end

    describe '.by_role_name' do
      it 'returns delegations with specific role name' do
        role = create(:role, name: 'account.manager', display_name: 'Account Manager')
        user = create(:user, account: account)
        with_role = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: role)

        expect(Account::Delegation.by_role_name('account.manager')).to contain_exactly(with_role)
      end
    end
  end

  describe 'state management' do
    let(:delegation) { create(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user) }

    describe '#active?' do
      it 'returns true when status is active and not expired' do
        delegation.update!(status: 'active', expires_at: 30.days.from_now)
        expect(delegation.active?).to be true
      end

      it 'returns false when status is active but expired' do
        delegation.update!(status: 'active', expires_at: 1.day.ago)
        expect(delegation.active?).to be false
      end

      it 'returns false when status is not active' do
        delegation.update!(status: 'inactive', expires_at: 30.days.from_now)
        expect(delegation.active?).to be false
      end

      it 'returns true when status is active and expires_at is nil' do
        delegation.update!(status: 'active', expires_at: nil)
        expect(delegation.active?).to be true
      end
    end

    describe '#inactive?' do
      it 'returns true when status is inactive' do
        delegation.update!(status: 'inactive')
        expect(delegation.inactive?).to be true
      end

      it 'returns false when status is not inactive' do
        delegation.update!(status: 'active')
        expect(delegation.inactive?).to be false
      end
    end

    describe '#revoked?' do
      it 'returns true when status is revoked' do
        delegation.update!(status: 'revoked')
        expect(delegation.revoked?).to be true
      end

      it 'returns false when status is not revoked' do
        delegation.update!(status: 'active')
        expect(delegation.revoked?).to be false
      end
    end

    describe '#expired?' do
      it 'returns true when expires_at is in the past' do
        delegation.update!(expires_at: 1.day.ago)
        expect(delegation.expired?).to be true
      end

      it 'returns false when expires_at is in the future' do
        delegation.update!(expires_at: 30.days.from_now)
        expect(delegation.expired?).to be false
      end

      it 'returns falsy when expires_at is nil' do
        delegation.update!(expires_at: nil)
        expect(delegation.expired?).to be_falsey
      end
    end

    describe '#activate!' do
      it 'sets status to active' do
        delegation.update!(status: 'inactive')
        delegation.activate!
        expect(delegation.status).to eq('active')
      end
    end

    describe '#deactivate!' do
      it 'sets status to inactive' do
        delegation.update!(status: 'active')
        delegation.deactivate!
        expect(delegation.status).to eq('inactive')
      end
    end

    describe '#revoke!' do
      let(:revoker) { create(:user, account: account) }

      it 'sets status to revoked' do
        delegation.revoke!(revoker)
        expect(delegation.status).to eq('revoked')
      end

      it 'sets revoked_at timestamp' do
        delegation.revoke!(revoker)
        expect(delegation.revoked_at).to be_within(1.second).of(Time.current)
      end

      it 'sets revoked_by user' do
        delegation.revoke!(revoker)
        expect(delegation.revoked_by).to eq(revoker)
      end
    end
  end

  describe 'permission methods' do
    let(:delegation) { create(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user, role: admin_role) }

    # Permissions are code-defined and referenced by NAME (string). The
    # delegation's effective/assigned permissions are arrays of catalog names.
    let(:role_permission_name) { ROLE_PERMISSION_NAMES.first }

    describe '#effective_permissions' do
      it 'returns custom permission names when assigned' do
        delegation.delegation_permissions.create!(permission_name: role_permission_name)
        expect(delegation.effective_permissions).to eq([ role_permission_name ])
      end

      it 'returns role permission names when no custom permissions' do
        expect(delegation.effective_permissions).to match_array(admin_role.permission_names)
      end

      it 'returns empty array when inactive' do
        delegation.update!(status: 'inactive')
        expect(delegation.effective_permissions).to eq([])
      end

      it 'returns empty array when expired' do
        delegation.update!(expires_at: 1.day.ago)
        expect(delegation.effective_permissions).to eq([])
      end

      it 'returns empty array when no role and no permissions' do
        user = create(:user, account: account)
        no_role_delegation = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: nil)
        expect(no_role_delegation.effective_permissions).to eq([])
      end
    end

    describe '#has_permission?' do
      it 'returns true when delegation has the permission' do
        expect(delegation.has_permission?('users.create')).to be true
      end

      it 'returns false when delegation does not have the permission' do
        expect(delegation.has_permission?('page.delete')).to be false
      end

      it 'returns false when delegation is inactive' do
        delegation.update!(status: 'inactive')
        expect(delegation.has_permission?('users.create')).to be false
      end

      it 'returns false when delegation is expired' do
        delegation.update!(expires_at: 1.day.ago)
        expect(delegation.has_permission?('users.create')).to be false
      end
    end

    describe '#assign_permission' do
      it 'assigns permission by name when active and within role scope' do
        delegation.delegation_permissions.destroy_all

        result = delegation.assign_permission(role_permission_name)
        expect(result).to be true
        expect(delegation.reload.permission_names).to include(role_permission_name)
      end

      it 'returns false when inactive' do
        delegation.update!(status: 'inactive')
        result = delegation.assign_permission(role_permission_name)
        expect(result).to be false
      end

      it 'returns false when permission already assigned' do
        delegation.delegation_permissions.create!(permission_name: role_permission_name)

        result = delegation.assign_permission(role_permission_name)
        expect(result).to be false
      end

      it 'returns false when permission not in role scope' do
        # A real catalog permission the admin_role does NOT grant.
        result = delegation.assign_permission('page.delete')
        expect(result).to be false
      end

      it 'assigns permission when no role assigned' do
        user = create(:user, account: account)
        no_role_delegation = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: nil)

        result = no_role_delegation.assign_permission('report.read')
        expect(result).to be true
      end
    end

    # IMP-7964b5d261b4 — the explicit custom set must be LIVE-BOUNDED by the role.
    #
    # FIVE write sites enforce "each custom name is within the role's scope":
    # DelegationService create/update/add, #assign_permission, and
    # Account::DelegationPermission's own before_create. All five bind the
    # WRITE. Nothing re-checked at RESOLUTION, so when the role's grants changed
    # under an existing row — exactly what a catalog-remap migration does — the
    # delegation kept carrying a name its role no longer confers. The empty-set
    # case already reads role.permission_names live; these examples extend the
    # same live read to the explicit set.
    #
    # The assertions are on the RESOLVED set, never on delegation_permissions
    # ROWS: the rows are what stays stale, so a row-level assertion is blind to
    # this by construction. #configured_permissions is the status-independent
    # accessor — #effective_permissions answers [] for any non-active row and
    # would pass vacuously.
    describe 'explicit custom set bounded by the live role' do
      # A real catalog permission granted to the role when the row is written
      # and WITHDRAWN afterwards — the only way such a row comes to exist,
      # since every write site refuses an out-of-scope name.
      let(:withdrawn_name) { 'page.delete' }

      # Write the row in scope, then take the name off the role. This is the
      # migration's revoke, reproduced.
      def stale_row_on(target_delegation)
        role = target_delegation.role
        role&.role_permissions&.find_or_create_by!(permission_name: withdrawn_name)
        target_delegation.delegation_permissions.create!(permission_name: withdrawn_name)
        # role_permissions is a PK-less join table (id: false) — destroy_all
        # cannot build a delete-by-id and raises.
        role&.role_permissions&.where(permission_name: withdrawn_name)&.delete_all
        target_delegation.reload
      end

      it 'drops a custom name the role no longer grants from the resolved set' do
        stale_row_on(delegation)

        expect(delegation.permission_names).to include(withdrawn_name)
        expect(delegation.configured_permissions).not_to include(withdrawn_name)
        expect(delegation.effective_permissions).not_to include(withdrawn_name)
        expect(delegation.has_permission?(withdrawn_name)).to be false
      end

      it 'keeps custom names the role still grants' do
        stale_row_on(delegation)
        delegation.delegation_permissions.create!(permission_name: role_permission_name)

        expect(delegation.reload.configured_permissions).to eq([ role_permission_name ])
      end

      # THE WIDENING TRAP. The fallback to the role's full set must key on the
      # RAW custom set being empty, never on the FILTERED set — otherwise a
      # delegation whose every custom name went stale would be promoted to its
      # whole role, turning this guard into the escalation it exists to close.
      it 'resolves to nothing rather than the whole role when every custom name is stale' do
        stale_row_on(delegation)

        expect(delegation.permission_names).to eq([ withdrawn_name ])
        expect(delegation.configured_permissions).to eq([])
      end

      it 'leaves a role-LESS delegation untouched' do
        user = create(:user, account: account)
        no_role = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: nil)
        stale_row_on(no_role)

        expect(no_role.configured_permissions).to eq([ withdrawn_name ])
      end

      # A role holding system.admin confers every permission programmatically,
      # so nothing on such a delegation is out of scope and nothing may be
      # stripped — the lockout DelegationService#unconferrable_reason warns
      # about.
      it 'does not strip a delegation whose role holds system.admin' do
        stale_row_on(delegation)
        admin_role.role_permissions.find_or_create_by!(permission_name: 'system.admin')

        expect(delegation.reload.configured_permissions).to eq([ withdrawn_name ])
      end

      # THE PREDICATE DIVERGENCE. Role#has_permission? answers true for ANY
      # name on a system.admin role; Role#permission_names answers the running
      # process's catalog. Filtering against the latter would strip a name that
      # is absent from THIS process's catalog — an extension permission where
      # the engine did not initialize, or a name since retired — even though
      # every write site accepted it. Only a non-catalog name can tell the two
      # implementations apart.
      it 'keeps a name outside this process catalog when the role holds system.admin' do
        admin_role.role_permissions.find_or_create_by!(permission_name: 'system.admin')
        uncatalogued = 'zz.not.in.this.process.catalog'
        expect(Permissions.permission_exists?(uncatalogued)).to be false
        delegation.delegation_permissions.create!(permission_name: uncatalogued)

        expect(delegation.reload.configured_permissions).to include(uncatalogued)
      end
    end

    # The one consumer of #configured_permissions_for outside resolution.
    # Nothing pinned this interaction, and a later flip of the empty-set key
    # would change its verdict silently.
    describe 'interaction with the removal-widening guard' do
      let(:withdrawn_name) { 'page.delete' }
      let(:service) { Accounts::DelegationService.new(delegator, account) }

      before do
        admin_role.role_permissions.find_or_create_by!(permission_name: withdrawn_name)
        delegation.delegation_permissions.create!(permission_name: withdrawn_name)
        delegation.delegation_permissions.create!(permission_name: role_permission_name)
        admin_role.role_permissions.where(permission_name: withdrawn_name).delete_all
        delegation.reload
      end

      it 'allows removing a stale name while an in-scope name remains' do
        result = service.remove_permission_from_delegation(delegation: delegation, permission_name: withdrawn_name)

        expect(result[:success]).to be true
        expect(delegation.reload.configured_permissions).to eq([ role_permission_name ])
      end

      it 'allows removing an in-scope name while a stale name remains' do
        result = service.remove_permission_from_delegation(delegation: delegation, permission_name: role_permission_name)

        expect(result[:success]).to be true
        # The stale name is still a ROW but confers nothing, so the delegation
        # narrows to nothing rather than widening to the role.
        expect(delegation.reload.configured_permissions).to eq([])
      end

      it 'still refuses the removal that would empty the custom set' do
        delegation.delegation_permissions.where(permission_name: role_permission_name).destroy_all

        result = service.remove_permission_from_delegation(delegation: delegation.reload, permission_name: withdrawn_name)

        expect(result[:success]).to be false
        expect(result[:errors].join(' ')).to include('widen')
      end
    end

    describe '#remove_permission' do
      it 'removes the permission by name' do
        delegation.delegation_permissions.create!(permission_name: role_permission_name)

        delegation.remove_permission(role_permission_name)
        expect(delegation.reload.permission_names).not_to include(role_permission_name)
      end

      it 'returns an empty result when permission not assigned' do
        result = delegation.remove_permission('report.read')
        expect(result.to_a).to eq([])
      end
    end

    describe '#permission_source' do
      it 'returns "custom" when custom permissions assigned' do
        delegation.delegation_permissions.create!(permission_name: role_permission_name)
        expect(delegation.permission_source).to eq('custom')
      end

      it 'returns "role" when only role permissions' do
        expect(delegation.permission_source).to eq('role')
      end

      it 'returns "none" when no role and no permissions' do
        user = create(:user, account: account)
        no_role_delegation = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: nil)
        expect(no_role_delegation.permission_source).to eq('none')
      end
    end

    describe '#available_permissions' do
      it 'returns role permission names not yet assigned' do
        delegation.delegation_permissions.create!(permission_name: role_permission_name)

        available = delegation.available_permissions
        expect(available).not_to include(role_permission_name)
        expect(available.count).to eq(admin_role.permission_names.count - 1)
      end

      it 'returns empty array when no role' do
        user = create(:user, account: account)
        no_role_delegation = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: nil)
        expect(no_role_delegation.available_permissions).to eq([])
      end
    end

    describe '#permissions_summary' do
      it 'returns formatted summary of permissions' do
        summary = delegation.permissions_summary
        expect(summary).to include('users: create')
        expect(summary).to include('analytics: read')
        expect(summary).to include('accounts: manage')
      end

      it 'returns "No permissions" when no permissions' do
        user = create(:user, account: account)
        no_role_delegation = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: nil)
        expect(no_role_delegation.permissions_summary).to eq('No permissions')
      end
    end
  end

  describe 'display helpers' do
    let(:delegation) { create(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user, role: admin_role) }

    describe '#role_display_name' do
      it 'returns role name when role present' do
        expect(delegation.role_display_name).to eq('account.admin')
      end

      it 'returns "No Role" when role not present' do
        user = create(:user, account: account)
        no_role_delegation = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: nil)
        expect(no_role_delegation.role_display_name).to eq('No Role')
      end
    end

    describe '#status_display' do
      it 'returns "Active" when active and not expired' do
        delegation.update!(status: 'active', expires_at: 30.days.from_now)
        expect(delegation.status_display).to eq('Active')
      end

      it 'returns "Expired" when active but expired' do
        delegation.update!(status: 'active', expires_at: 1.day.ago)
        expect(delegation.status_display).to eq('Expired')
      end

      it 'returns "Inactive" when inactive' do
        delegation.update!(status: 'inactive')
        expect(delegation.status_display).to eq('Inactive')
      end

      it 'returns "Revoked" when revoked' do
        delegation.update!(status: 'revoked')
        expect(delegation.status_display).to eq('Revoked')
      end
    end

    describe '#expires_in_days' do
      it 'returns days until expiration' do
        delegation.update!(expires_at: 10.days.from_now)
        expect(delegation.expires_in_days).to eq(10)
      end

      it 'returns negative days when expired' do
        delegation.update!(expires_at: 5.days.ago)
        expect(delegation.expires_in_days).to eq(-5)
      end

      it 'returns nil when no expiration date' do
        delegation.update!(expires_at: nil)
        expect(delegation.expires_in_days).to be_nil
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create :set_defaults' do
      it 'sets status to active when not provided' do
        delegation = Account::Delegation.new(
          account: account,
          delegated_by: delegator,
          delegated_user: delegated_user
        )
        delegation.save!
        expect(delegation.status).to eq('active')
      end

      it 'preserves explicit status when provided' do
        user = create(:user, account: account)
        delegation = Account::Delegation.new(
          account: account,
          delegated_by: delegator,
          delegated_user: user,
          status: 'inactive'
        )
        delegation.save!
        expect(delegation.status).to eq('inactive')
      end
    end
  end
end
