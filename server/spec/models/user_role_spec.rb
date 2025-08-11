require 'rails_helper'

RSpec.describe UserRole, type: :model do
  let(:user_role) { build(:user_role) }

  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:role) }
  end

  describe "validations" do
    let(:user) { create(:user) }
    let(:role) { create(:role) }

    describe "uniqueness validation" do
      it "validates uniqueness of user_id scoped to role_id" do
        create(:user_role, user: user, role: role)
        duplicate = build(:user_role, user: user, role: role)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:user_id]).to include("has already been taken")
      end

      it "allows same user with different roles" do
        role2 = create(:role)
        create(:user_role, user: user, role: role)
        different_role = build(:user_role, user: user, role: role2)

        expect(different_role).to be_valid
      end

      it "allows same role with different users" do
        user2 = create(:user)
        create(:user_role, user: user, role: role)
        different_user = build(:user_role, user: user2, role: role)

        expect(different_user).to be_valid
      end

      it "allows different combinations of user and role" do
        user2 = create(:user)
        role2 = create(:role)

        create(:user_role, user: user, role: role)
        different_combination = build(:user_role, user: user2, role: role2)

        expect(different_combination).to be_valid
      end
    end

    describe "association validations" do
      it "requires user to be present" do
        user_role = build(:user_role, user: nil)

        expect(user_role).not_to be_valid
        expect(user_role.errors[:user]).to include("must exist")
      end

      it "requires role to be present" do
        user_role = build(:user_role, role: nil)

        expect(user_role).not_to be_valid
        expect(user_role.errors[:role]).to include("must exist")
      end
    end
  end

  describe "creation and persistence" do
    it "can be created with valid user and role" do
      user = create(:user)
      role = create(:role)

      user_role = UserRole.create!(user: user, role: role)

      expect(user_role).to be_persisted
      expect(user_role.user).to eq(user)
      expect(user_role.role).to eq(role)
    end

    it "is destroyed when user is destroyed" do
      user = create(:user, :skip_owner_callback)
      role = create(:role)
      user_role = create(:user_role, user: user, role: role)

      # User gets Owner role automatically (first user in account) + the test role = 2 roles
      expect { user.destroy! }.to change { UserRole.count }.by(-2)
      expect(UserRole.find_by(id: user_role.id)).to be_nil
    end

    it "is destroyed when role is destroyed" do
      user = create(:user, :skip_owner_callback)
      role = create(:role)
      user_role = create(:user_role, user: user, role: role)

      expect { role.destroy! }.to change { UserRole.count }.by(-1)
      expect(UserRole.find_by(id: user_role.id)).to be_nil
    end
  end

  describe "integration scenarios" do
    it "properly connects users and roles" do
      admin_user = create(:user, email: "admin@example.com")
      manager_user = create(:user, email: "manager@example.com")
      admin_role = create(:role, name: "Admin")
      manager_role = create(:role, name: "Manager")

      # Create user-role relationships
      admin_user_role = create(:user_role, user: admin_user, role: admin_role)
      manager_user_role = create(:user_role, user: manager_user, role: manager_role)

      # Admin user can also have manager role
      admin_manager_role = create(:user_role, user: admin_user, role: manager_role)

      # Verify the relationships work through associations
      expect(admin_user.roles).to include(admin_role, manager_role)
      expect(manager_user.roles).to include(manager_role)
      expect(manager_user.roles).not_to include(admin_role)

      expect(admin_role.users).to include(admin_user)
      expect(manager_role.users).to include(admin_user, manager_user)

      # Verify the join records exist
      expect(admin_user.user_roles).to include(admin_user_role, admin_manager_role)
      expect(manager_user.user_roles).to include(manager_user_role)
      expect(admin_role.user_roles).to include(admin_user_role)
      expect(manager_role.user_roles).to include(admin_manager_role, manager_user_role)
    end

    it "prevents duplicate user-role assignments" do
      user = create(:user, :skip_owner_callback)
      role = create(:role, name: "Editor")

      # Create first assignment
      first_assignment = create(:user_role, user: user, role: role)

      # Attempt duplicate assignment
      duplicate_assignment = build(:user_role, user: user, role: role)

      expect(duplicate_assignment).not_to be_valid
      # User gets Owner role automatically + Editor role = 2 total UserRoles
      expect(UserRole.count).to eq(2)
    end

    it "handles complex many-to-many relationships" do
      # Create multiple users and roles
      user1 = create(:user, :skip_owner_callback, email: "user1@example.com")
      user2 = create(:user, :skip_owner_callback, email: "user2@example.com")
      user3 = create(:user, :skip_owner_callback, email: "user3@example.com")

      admin_role = create(:role, name: "Admin")
      editor_role = create(:role, name: "Editor")
      viewer_role = create(:role, name: "Viewer")

      # User1 has all roles
      create(:user_role, user: user1, role: admin_role)
      create(:user_role, user: user1, role: editor_role)
      create(:user_role, user: user1, role: viewer_role)

      # User2 has editor and viewer roles
      create(:user_role, user: user2, role: editor_role)
      create(:user_role, user: user2, role: viewer_role)

      # User3 has only viewer role
      create(:user_role, user: user3, role: viewer_role)

      # Verify user roles (each user gets Owner role automatically + test roles)
      expect(user1.roles.count).to eq(4) # Owner + Admin + Editor + Viewer
      expect(user2.roles.count).to eq(3) # Owner + Editor + Viewer
      expect(user3.roles.count).to eq(2) # Owner + Viewer

      # Verify role users
      expect(admin_role.users.count).to eq(1)
      expect(editor_role.users.count).to eq(2)
      expect(viewer_role.users.count).to eq(3)

      # Verify specific relationships
      expect(user1.roles).to include(admin_role, editor_role, viewer_role)
      expect(user2.roles).to include(editor_role, viewer_role)
      expect(user2.roles).not_to include(admin_role)
      expect(user3.roles).to include(viewer_role)
      expect(user3.roles).not_to include(admin_role, editor_role)
    end
  end

  describe "database constraints and integrity" do
    it "maintains referential integrity" do
      user = create(:user)
      role = create(:role)
      user_role = create(:user_role, user: user, role: role)

      # Should not be able to delete user or role when user_role exists
      # This depends on the database foreign key constraints
      expect(user_role.user_id).to eq(user.id)
      expect(user_role.role_id).to eq(role.id)
    end

    it "handles edge cases with nil associations gracefully in validation" do
      user_role = UserRole.new

      expect(user_role).not_to be_valid
      expect(user_role.errors[:user]).to be_present
      expect(user_role.errors[:role]).to be_present
    end
  end

  describe "mass assignment and security" do
    it "can be created with mass assignment" do
      user = create(:user)
      role = create(:role)

      user_role = UserRole.create!(user_id: user.id, role_id: role.id)

      expect(user_role).to be_persisted
      expect(user_role.user).to eq(user)
      expect(user_role.role).to eq(role)
    end
  end

  describe "query and finding" do
    let!(:user1) { create(:user, :skip_owner_callback, email: "user1@example.com") }
    let!(:user2) { create(:user, :skip_owner_callback, email: "user2@example.com") }
    let!(:role1) { create(:role, name: "Admin") }
    let!(:role2) { create(:role, name: "Editor") }
    let!(:user_role1) { create(:user_role, user: user1, role: role1) }
    let!(:user_role2) { create(:user_role, user: user1, role: role2) }
    let!(:user_role3) { create(:user_role, user: user2, role: role2) }

    it "can find user_roles by user" do
      user1_roles = UserRole.where(user: user1)

      # User1 gets Owner role automatically + Admin + Editor = 3 roles
      expect(user1_roles.count).to eq(3)
      expect(user1_roles).to include(user_role1, user_role2)
    end

    it "can find user_roles by role" do
      editor_role_users = UserRole.where(role: role2)

      expect(editor_role_users.count).to eq(2)
      expect(editor_role_users).to include(user_role2, user_role3)
    end

    it "can find specific user_role combination" do
      specific_user_role = UserRole.find_by(user: user1, role: role1)

      expect(specific_user_role).to eq(user_role1)
    end
  end

  describe "role assignment scenarios" do
    let(:account) { create(:account) }
    let(:user) { create(:user, :skip_owner_callback, account: account) }

    it "supports account owner role assignment" do
      # User automatically gets Owner role as the first user in the account
      expect(user.roles.pluck(:name)).to include("Owner")
      expect(account.owner).to eq(user) # This should work with the Account#owner method
    end

    it "supports multiple role assignments for account users" do
      admin_role = create(:role, name: "Admin")
      billing_role = create(:role, name: "Billing Manager")

      create(:user_role, user: user, role: admin_role)
      create(:user_role, user: user, role: billing_role)

      expect(user.roles).to include(admin_role, billing_role)
      # User gets Owner role automatically + Admin + Billing Manager = 3 total roles
      expect(user.roles.count).to eq(3)
    end

    it "handles system vs custom roles" do
      system_role = create(:role, name: "System Admin", system_role: true)
      custom_role = create(:role, name: "Custom Role", system_role: false)

      create(:user_role, user: user, role: system_role)
      create(:user_role, user: user, role: custom_role)

      system_roles = user.roles.merge(Role.system_roles)
      custom_roles = user.roles.merge(Role.custom_roles)

      expect(system_roles).to include(system_role)
      expect(custom_roles).to include(custom_role)
    end
  end

  describe "permission inheritance through roles" do
    it "allows users to inherit permissions through role assignments" do
      user = create(:user)
      role = create(:role, name: "Content Manager")
      permission1 = create(:permission, name: "posts.create")
      permission2 = create(:permission, name: "posts.edit")

      # Assign permissions to role
      create(:role_permission, role: role, permission: permission1)
      create(:role_permission, role: role, permission: permission2)

      # Assign role to user
      create(:user_role, user: user, role: role)

      # User should have access to permissions through the role
      user_permissions = Permission.joins(roles: :users).where(users: { id: user.id })

      expect(user_permissions).to include(permission1, permission2)
    end

    it "accumulates permissions from multiple roles" do
      user = create(:user)
      editor_role = create(:role, name: "Editor")
      admin_role = create(:role, name: "Admin")

      edit_permission = create(:permission, name: "content.edit")
      admin_permission = create(:permission, name: "users.manage")
      shared_permission = create(:permission, name: "dashboard.view")

      # Assign permissions to roles
      create(:role_permission, role: editor_role, permission: edit_permission)
      create(:role_permission, role: editor_role, permission: shared_permission)
      create(:role_permission, role: admin_role, permission: admin_permission)
      create(:role_permission, role: admin_role, permission: shared_permission)

      # Assign both roles to user
      create(:user_role, user: user, role: editor_role)
      create(:user_role, user: user, role: admin_role)

      # User should have all permissions from both roles (deduplicated)
      user_permissions = Permission.joins(roles: :users).where(users: { id: user.id }).distinct

      expect(user_permissions).to include(edit_permission, admin_permission, shared_permission)
      expect(user_permissions.count).to eq(3)
    end
  end
end
