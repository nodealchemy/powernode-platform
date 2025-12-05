# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountDelegation, type: :model do
  let(:account) { create(:account) }
  let(:delegator) { create(:user, account: account) }
  let(:delegated_user) { create(:user, account: account) }
  let(:admin_role) do
    role = create(:role, name: 'account.admin', display_name: 'Account Admin', role_type: 'user')
    permission1 = Permission.find_or_create_by!(resource: 'users', action: 'create') do |p|
      p.description = 'Create users'
      p.category = 'user_management'
    end
    permission2 = Permission.find_or_create_by!(resource: 'analytics', action: 'read') do |p|
      p.description = 'Read analytics'
      p.category = 'analytics'
    end
    permission3 = Permission.find_or_create_by!(resource: 'account', action: 'manage') do |p|
      p.description = 'Manage account'
      p.category = 'account'
    end
    role.permissions << [permission1, permission2, permission3] unless role.permissions.include?(permission1)
    role
  end

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:delegated_user).class_name('User') }
    it { should belong_to(:delegated_by).class_name('User') }
    it { should belong_to(:revoked_by).class_name('User').optional }
    it { should belong_to(:role).optional }
    it { should have_many(:delegation_permissions).dependent(:destroy) }
    it { should have_many(:permissions).through(:delegation_permissions) }
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
      }.to change(AccountDelegation, :count).by(1)
    end

    it 'allows multiple delegations for different users in same account' do
      create(:account_delegation, account: account, delegated_by: delegator, delegated_user: delegated_user)
      another_user = create(:user, account: account)

      expect {
        create(:account_delegation, account: account, delegated_by: delegator, delegated_user: another_user)
      }.to change(AccountDelegation, :count).by(1)
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
        results = AccountDelegation.active
        expect(results).to include(active_delegation, expired_delegation)
        expect(results).not_to include(inactive_delegation, revoked_delegation)
      end
    end

    describe '.inactive' do
      it 'returns only inactive delegations' do
        expect(AccountDelegation.inactive).to contain_exactly(inactive_delegation)
      end
    end

    describe '.revoked' do
      it 'returns only revoked delegations' do
        expect(AccountDelegation.revoked).to contain_exactly(revoked_delegation)
      end
    end

    describe '.for_account' do
      it 'returns delegations for specific account' do
        expect(AccountDelegation.for_account(account)).to contain_exactly(
          active_delegation, inactive_delegation, revoked_delegation, expired_delegation
        )
      end
    end

    describe '.for_user' do
      it 'returns delegations for specific user' do
        expect(AccountDelegation.for_user(active_delegation.delegated_user)).to contain_exactly(active_delegation)
      end
    end

    describe '.not_expired' do
      it 'returns delegations that have not expired' do
        results = AccountDelegation.not_expired
        expect(results).to include(active_delegation, inactive_delegation, revoked_delegation)
        expect(results).not_to include(expired_delegation)
      end

      it 'includes delegations with nil expires_at' do
        user = create(:user, account: account)
        no_expiry = create(:account_delegation, :no_expiration, account: account, delegated_by: delegator, delegated_user: user)
        expect(AccountDelegation.not_expired).to include(no_expiry)
      end
    end

    describe '.expired' do
      it 'returns only expired delegations' do
        expect(AccountDelegation.expired).to contain_exactly(expired_delegation)
      end

      it 'excludes delegations with nil expires_at' do
        user = create(:user, account: account)
        no_expiry = create(:account_delegation, :no_expiration, account: account, delegated_by: delegator, delegated_user: user)
        expect(AccountDelegation.expired).not_to include(no_expiry)
      end
    end

    describe '.with_role' do
      it 'returns delegations with specific role' do
        role = create(:role, name: 'test.role', display_name: 'Test Role')
        user = create(:user, account: account)
        with_role = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: role)

        expect(AccountDelegation.with_role(role)).to contain_exactly(with_role)
      end
    end

    describe '.by_role_name' do
      it 'returns delegations with specific role name' do
        role = create(:role, name: 'account.manager', display_name: 'Account Manager')
        user = create(:user, account: account)
        with_role = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: role)

        expect(AccountDelegation.by_role_name('account.manager')).to contain_exactly(with_role)
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

    describe '#effective_permissions' do
      it 'returns custom permissions when assigned' do
        delegation.delegation_permissions.create!(permission: admin_role.permissions.first)
        expect(delegation.effective_permissions).to eq([admin_role.permissions.first])
      end

      it 'returns role permissions when no custom permissions' do
        expect(delegation.effective_permissions).to match_array(admin_role.permissions)
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
        expect(delegation.has_permission?('billing.manage')).to be false
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
      it 'assigns permission when active and within role scope' do
        perm = admin_role.permissions.first
        delegation.permissions.clear

        result = delegation.assign_permission(perm)
        expect(result).to be true
        expect(delegation.reload.permissions).to include(perm)
      end

      it 'returns false when inactive' do
        delegation.update!(status: 'inactive')
        result = delegation.assign_permission(admin_role.permissions.first)
        expect(result).to be false
      end

      it 'returns false when permission already assigned' do
        perm = admin_role.permissions.first
        delegation.delegation_permissions.create!(permission: perm)

        result = delegation.assign_permission(perm)
        expect(result).to be false
      end

      it 'returns false when permission not in role scope' do
        other_permission = create(:permission, resource: 'external', action: 'access')
        result = delegation.assign_permission(other_permission)
        expect(result).to be false
      end

      it 'assigns permission when no role assigned' do
        user = create(:user, account: account)
        no_role_delegation = create(:account_delegation, account: account, delegated_by: delegator, delegated_user: user, role: nil)
        perm = create(:permission, resource: 'test', action: 'read')

        result = no_role_delegation.assign_permission(perm)
        expect(result).to be true
      end
    end

    describe '#remove_permission' do
      it 'removes the permission' do
        perm = admin_role.permissions.first
        delegation.delegation_permissions.create!(permission: perm)

        delegation.remove_permission(perm)
        expect(delegation.reload.permissions).not_to include(perm)
      end

      it 'returns nil when permission not assigned' do
        perm = create(:permission, resource: 'test', action: 'read')
        result = delegation.remove_permission(perm)
        expect(result).to be_nil
      end
    end

    describe '#permission_source' do
      it 'returns "custom" when custom permissions assigned' do
        delegation.delegation_permissions.create!(permission: admin_role.permissions.first)
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
      it 'returns role permissions not yet assigned' do
        # Assign one permission specifically
        assigned_perm = admin_role.permissions.first
        delegation.delegation_permissions.create!(permission: assigned_perm)

        available = delegation.available_permissions
        expect(available).not_to include(assigned_perm)
        expect(available.count).to eq(admin_role.permissions.count - 1)
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
        expect(summary).to include('account: manage')
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
        delegation = AccountDelegation.new(
          account: account,
          delegated_by: delegator,
          delegated_user: delegated_user
        )
        delegation.save!
        expect(delegation.status).to eq('active')
      end

      it 'preserves explicit status when provided' do
        user = create(:user, account: account)
        delegation = AccountDelegation.new(
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
