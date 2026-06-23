# frozen_string_literal: true

require 'rails_helper'

# Security spec for the CODE-defined permission system.
#
# Permissions are no longer ActiveRecord rows — the `Permissions` catalog
# module (config/permissions.rb) is the single source of truth. Grants are
# stored BY NAME (string columns validated against the catalog, no FK). Roles
# are GLOBAL when account_id is nil (code-defined) and ACCOUNT-scoped when
# account_id is set (custom). This spec proves the model end to end:
#   * catalog-membership validation on grants
#   * by-name resolution + the system.admin wildcard
#   * global vs account scoping and the no-shadowing invariant
#   * cross-account isolation of role assignment
#   * the no-privilege-escalation rules around granting permissions
RSpec.describe 'Code-defined permission system', type: :model do
  let(:account) { create(:account) }

  # A bare role with no default-role noise. account_id nil => GLOBAL.
  def global_role(name)
    create(:role, name: name, account_id: nil)
  end

  describe 'RolePermission catalog validation' do
    let(:role) { create(:role) }

    it 'accepts a grant for a permission that exists in the catalog' do
      expect(Permissions.permission_exists?('users.read')).to be true

      grant = role.role_permissions.build(permission_name: 'users.read')
      expect(grant).to be_valid
      expect { grant.save! }.to change { role.role_permissions.count }.by(1)
    end

    it 'rejects a grant for a name that is not in the catalog' do
      expect(Permissions.permission_exists?('totally.bogus')).to be false

      grant = role.role_permissions.build(permission_name: 'totally.bogus')
      expect(grant).not_to be_valid
      expect(grant.errors[:permission_name]).to include('is not a defined permission')
    end

    it 'rejects a blank permission name' do
      grant = role.role_permissions.build(permission_name: '')
      expect(grant).not_to be_valid
      expect(grant.errors[:permission_name]).to include("can't be blank")
    end

    it 'rejects a duplicate grant of the same permission on the same role' do
      role.role_permissions.create!(permission_name: 'users.read')
      duplicate = role.role_permissions.build(permission_name: 'users.read')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:role_id]).to include('has already been taken')
    end
  end

  describe 'Role#has_permission? and #permission_names (by name)' do
    let(:role) { create(:role) }

    before do
      role.role_permissions.create!(permission_name: 'users.read')
      role.role_permissions.create!(permission_name: 'users.manage')
    end

    it 'resolves granted permissions by name' do
      expect(role.has_permission?('users.read')).to be true
      expect(role.has_permission?('users.manage')).to be true
    end

    it 'returns false for a permission the role was not granted' do
      expect(role.has_permission?('admin.access')).to be false
    end

    it 'exposes only the granted names via permission_names' do
      expect(role.permission_names).to match_array(%w[users.read users.manage])
    end

    context 'with the system.admin wildcard' do
      let(:admin_role) { create(:role, name: 'role_wildcard_sysadmin', role_type: 'admin') }

      before { admin_role.role_permissions.create!(permission_name: 'system.admin') }

      it 'grants ANY catalog permission' do
        expect(admin_role.has_permission?('users.manage')).to be true
        expect(admin_role.has_permission?('admin.access')).to be true
        expect(admin_role.has_permission?('git.providers.delete')).to be true
      end

      it 'expands permission_names to the entire catalog' do
        expect(admin_role.permission_names).to match_array(Permissions.all_permissions.keys)
      end
    end
  end

  describe 'add_permission / remove_permission (by name)' do
    let(:role) { create(:role) }

    it 'adds a catalog permission by name and is idempotent' do
      expect { role.add_permission('users.read') }.to change { role.role_permissions.count }.by(1)
      expect { role.add_permission('users.read') }.not_to change { role.role_permissions.count }
      expect(role.has_permission?('users.read')).to be true
    end

    it 'removes a granted permission by name' do
      role.add_permission('users.read')
      expect { role.remove_permission('users.read') }.to change { role.role_permissions.count }.by(-1)
      expect(role.has_permission?('users.read')).to be false
    end
  end

  describe 'global vs account scoping' do
    it 'classifies account_id nil as global and a set account_id as account-scoped' do
      g = global_role('a_global_role')
      a = create(:role, name: 'an_account_role', account_id: account.id)

      expect(Role.global).to include(g)
      expect(Role.global).not_to include(a)
      expect(Role.owned_by_account(account.id)).to include(a)
      expect(Role.owned_by_account(account.id)).not_to include(g)
    end

    it 'for_account returns both global roles and the account-owned roles' do
      g = global_role('shared_global_role')
      a = create(:role, name: 'private_account_role', account_id: account.id)
      other = create(:role, name: 'other_acct_role', account_id: create(:account).id)

      visible = Role.for_account(account.id)
      expect(visible).to include(g, a)
      expect(visible).not_to include(other)
    end

    it 'forbids an account role from shadowing a global role name' do
      global_role('reserved_name')
      shadow = build(:role, name: 'reserved_name', account_id: account.id)

      expect(shadow).not_to be_valid
      expect(shadow.errors[:name]).to include('is reserved by a global role')
    end

    it 'lets two different accounts each own a role with the same name' do
      account_b = create(:account)
      role_a = create(:role, name: 'team_lead', account_id: account.id)
      role_b = build(:role, name: 'team_lead', account_id: account_b.id)

      expect(role_a).to be_persisted
      expect(role_b).to be_valid
      expect { role_b.save! }.not_to raise_error
    end
  end

  describe 'User#has_permission? through roles (by name)' do
    let(:user) { create(:user, account: account, permissions: []) }
    let(:role) { create(:role, name: 'reader_role', account_id: account.id) }

    before do
      role.role_permissions.create!(permission_name: 'users.read')
      user.roles << role
      user.reload
    end

    it 'is true for a permission granted via one of the user roles' do
      expect(user.has_permission?('users.read')).to be true
    end

    it 'is false for a permission none of the user roles grant' do
      expect(user.has_permission?('users.manage')).to be false
    end

    it 'is true for ANY permission when a role grants system.admin' do
      admin_role = global_role('wildcard_admin_role')
      admin_role.role_permissions.create!(permission_name: 'system.admin')
      user.roles << admin_role
      user.reload

      expect(user.has_permission?('users.manage')).to be true
      expect(user.has_permission?('admin.access')).to be true
      expect(user.permission_names).to match_array(Permissions.all_permissions.keys)
    end
  end

  describe 'cross-account role-assignment isolation' do
    let(:account_b) { create(:account) }
    let(:user_a) { create(:user, account: account, permissions: []) }

    it 'rejects assigning another account-owned role to a user' do
      foreign_role = create(:role, name: 'foreign_role', account_id: account_b.id)

      assignment = UserRole.new(user: user_a, role: foreign_role)
      expect(assignment).not_to be_valid
      expect(assignment.errors[:role]).to include("is not available to this user's account")
    end

    it 'allows assigning a role owned by the user own account' do
      own_role = create(:role, name: 'own_role', account_id: account.id)

      assignment = UserRole.new(user: user_a, role: own_role)
      expect(assignment).to be_valid
    end

    it 'allows assigning a GLOBAL (code) role to any account user' do
      shared = global_role('shared_assignable_role')

      assignment = UserRole.new(user: user_a, role: shared)
      expect(assignment).to be_valid
      expect { assignment.save! }.to change { user_a.user_roles.count }.by(1)
    end
  end

  describe 'no privilege escalation when granting' do
    # Build the user's roles explicitly so the factory default role doesn't add
    # permissions we aren't reasoning about.
    let(:user) { create(:user, account: account, permissions: []) }

    context 'a user holding system.admin' do
      before do
        admin_role = global_role('grant_admin_role')
        admin_role.role_permissions.create!(permission_name: 'system.admin')
        user.roles << admin_role
        user.reload
      end

      it 'may grant a non-system permission it effectively holds' do
        expect(user.has_permission?('users.manage')).to be true
        expect(user.can_grant_permission?('users.manage')).to be true
      end

      it 'may NOT grant the system.admin permission itself' do
        expect(user.has_permission?('system.admin')).to be true
        expect(user.can_grant_permission?('system.admin')).to be false
      end

      it 'excludes every system.* permission from the grantable set' do
        grantable = user.grantable_permission_names
        expect(grantable).not_to be_empty
        expect(grantable.any? { |name| name.start_with?('system.') }).to be false
        expect(grantable).to include('users.manage')
      end
    end

    context 'a user holding only users.read' do
      before do
        role = create(:role, name: 'reader_only_role', account_id: account.id)
        role.role_permissions.create!(permission_name: 'users.read')
        user.roles << role
        user.reload
      end

      it 'cannot grant a permission it does not hold' do
        expect(user.has_permission?('users.manage')).to be false
        expect(user.can_grant_permission?('users.manage')).to be false
      end

      it 'can grant the permission it does hold' do
        expect(user.can_grant_permission?('users.read')).to be true
      end
    end
  end
end
