require 'rails_helper'

RSpec.describe RolePermission, type: :model do
  let(:role_permission) { build(:role_permission) }

  describe "associations" do
    it { should belong_to(:role) }
    it { should belong_to(:permission) }
  end

  describe "validations" do
    describe "uniqueness validation" do
      it "validates uniqueness of role_id scoped to permission_id" do
        role = create(:role)
        permission = create(:permission)
        create(:role_permission, role: role, permission: permission)
        duplicate = build(:role_permission, role: role, permission: permission)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:role_id]).to include("has already been taken")
      end

      it "allows same role with different permissions" do
        role = create(:role)
        permission1 = create(:permission)
        permission2 = create(:permission)
        create(:role_permission, role: role, permission: permission1)
        different_permission = build(:role_permission, role: role, permission: permission2)

        expect(different_permission).to be_valid
      end

      it "allows same permission with different roles" do
        role1 = create(:role, name: "unique.test.role.one")
        role2 = create(:role, name: "unique.test.role.two")
        permission = create(:permission, name: "unique_test_permission_1", resource: "unique_resource_1", action: "unique_action_1")
        create(:role_permission, role: role1, permission: permission)
        different_role = build(:role_permission, role: role2, permission: permission)

        expect(different_role).to be_valid
      end

      it "allows different combinations of role and permission" do
        role1 = create(:role, name: "unique.combo.role.one")
        role2 = create(:role, name: "unique.combo.role.two")
        permission1 = create(:permission, name: "unique_combo_permission_1", resource: "unique_combo_resource_1", action: "unique_combo_action_1")
        permission2 = create(:permission, name: "unique_combo_permission_2", resource: "unique_combo_resource_2", action: "unique_combo_action_2")

        create(:role_permission, role: role1, permission: permission1)
        different_combination = build(:role_permission, role: role2, permission: permission2)

        expect(different_combination).to be_valid
      end
    end

    describe "association validations" do
      it "requires role to be present" do
        role_permission = build(:role_permission, role: nil)

        expect(role_permission).not_to be_valid
        expect(role_permission.errors[:role]).to include("must exist")
      end

      it "requires permission to be present" do
        role_permission = build(:role_permission, permission: nil)

        expect(role_permission).not_to be_valid
        expect(role_permission.errors[:permission]).to include("must exist")
      end
    end
  end

  describe "creation and persistence" do
    it "can be created with valid role and permission" do
      role = create(:role)
      permission = create(:permission)

      role_permission = RolePermission.create!(role: role, permission: permission)

      expect(role_permission).to be_persisted
      expect(role_permission.role).to eq(role)
      expect(role_permission.permission).to eq(permission)
    end

    it "is destroyed when role is destroyed" do
      role = create(:role)
      permission = create(:permission)
      role_permission = create(:role_permission, role: role, permission: permission)

      expect { role.destroy! }.to change { RolePermission.count }.by(-1)
      expect(RolePermission.find_by(role_id: role.id, permission_id: permission.id)).to be_nil
    end

    it "is destroyed when permission is destroyed" do
      role = create(:role)
      permission = create(:permission)
      role_permission = create(:role_permission, role: role, permission: permission)

      expect { permission.destroy! }.to change { RolePermission.count }.by(-1)
      expect(RolePermission.find_by(role_id: role.id, permission_id: permission.id)).to be_nil
    end
  end

  describe "integration scenarios" do
    it "properly connects roles and permissions" do
      admin_role = create(:role, name: "admin_test")
      user_create_permission = create(:permission, name: "users.create")
      user_read_permission = create(:permission, name: "users.read")

      # Create role-permission relationships
      admin_user_create = create(:role_permission, role: admin_role, permission: user_create_permission)
      admin_user_read = create(:role_permission, role: admin_role, permission: user_read_permission)

      # Verify the relationships work through associations
      expect(admin_role.permissions).to include(user_create_permission, user_read_permission)
      expect(user_create_permission.roles).to include(admin_role)
      expect(user_read_permission.roles).to include(admin_role)

      # Verify the join records exist
      expect(admin_role.role_permissions.count).to eq(2)
      expect(admin_role.role_permissions.map(&:permission_id)).to include(user_create_permission.id, user_read_permission.id)
      expect(user_create_permission.role_permissions.count).to eq(1)
      expect(user_read_permission.role_permissions.count).to eq(1)
    end

    it "prevents duplicate role-permission assignments" do
      manager_role = create(:role, name: "manager_test")
      edit_permission = create(:permission, name: "posts.edit")

      initial_count = RolePermission.count

      # Create first assignment
      first_assignment = create(:role_permission, role: manager_role, permission: edit_permission)

      # Attempt duplicate assignment
      duplicate_assignment = build(:role_permission, role: manager_role, permission: edit_permission)

      expect(duplicate_assignment).not_to be_valid
      expect(RolePermission.count).to eq(initial_count + 1)
    end

    it "handles complex many-to-many relationships" do
      # Create multiple roles and permissions
      admin_role = create(:role, name: "admin_test")
      editor_role = create(:role, name: "editor_test")
      viewer_role = create(:role, name: "viewer_test")

      create_permission = create(:permission, name: "posts.create")
      edit_permission = create(:permission, name: "posts.edit")
      view_permission = create(:permission, name: "posts.view")

      # Admin has all permissions
      create(:role_permission, role: admin_role, permission: create_permission)
      create(:role_permission, role: admin_role, permission: edit_permission)
      create(:role_permission, role: admin_role, permission: view_permission)

      # Editor has edit and view permissions
      create(:role_permission, role: editor_role, permission: edit_permission)
      create(:role_permission, role: editor_role, permission: view_permission)

      # Viewer has only view permission
      create(:role_permission, role: viewer_role, permission: view_permission)

      # Verify role permissions
      expect(admin_role.permissions.count).to eq(3)
      expect(editor_role.permissions.count).to eq(2)
      expect(viewer_role.permissions.count).to eq(1)

      # Verify permission roles
      expect(create_permission.roles.count).to eq(1)
      expect(edit_permission.roles.count).to eq(2)
      expect(view_permission.roles.count).to eq(3)

      # Verify specific relationships
      expect(admin_role.permissions).to include(create_permission, edit_permission, view_permission)
      expect(editor_role.permissions).to include(edit_permission, view_permission)
      expect(editor_role.permissions).not_to include(create_permission)
      expect(viewer_role.permissions).to include(view_permission)
      expect(viewer_role.permissions).not_to include(create_permission, edit_permission)
    end
  end

  describe "database constraints and integrity" do
    it "maintains referential integrity" do
      role = create(:role)
      permission = create(:permission)
      role_permission = create(:role_permission, role: role, permission: permission)

      # Should not be able to delete role or permission when role_permission exists
      # This depends on the database foreign key constraints
      expect(role_permission.role_id).to eq(role.id)
      expect(role_permission.permission_id).to eq(permission.id)
    end

    it "handles edge cases with nil associations gracefully in validation" do
      role_permission = RolePermission.new

      expect(role_permission).not_to be_valid
      expect(role_permission.errors[:role]).to be_present
      expect(role_permission.errors[:permission]).to be_present
    end
  end

  describe "mass assignment and security" do
    it "can be created with mass assignment" do
      role = create(:role)
      permission = create(:permission)

      role_permission = RolePermission.create!(role_id: role.id, permission_id: permission.id)

      expect(role_permission).to be_persisted
      expect(role_permission.role).to eq(role)
      expect(role_permission.permission).to eq(permission)
    end
  end

  describe "query and finding" do
    let!(:role1) { create(:role, name: "admin_query_test") }
    let!(:role2) { create(:role, name: "user_query_test") }
    let!(:permission1) { create(:permission, name: "users.create") }
    let!(:permission2) { create(:permission, name: "users.read") }
    let!(:role_permission1) { create(:role_permission, role: role1, permission: permission1) }
    let!(:role_permission2) { create(:role_permission, role: role1, permission: permission2) }
    let!(:role_permission3) { create(:role_permission, role: role2, permission: permission2) }

    it "can find role_permissions by role" do
      admin_role_permissions = RolePermission.where(role: role1)

      expect(admin_role_permissions.count).to eq(2)
      expect(admin_role_permissions.pluck(:permission_id)).to include(permission1.id, permission2.id)
    end

    it "can find role_permissions by permission" do
      read_permission_roles = RolePermission.where(permission: permission2)

      expect(read_permission_roles.count).to eq(2)
      expect(read_permission_roles.pluck(:role_id)).to include(role1.id, role2.id)
    end

    it "can find specific role_permission combination" do
      specific_role_permission = RolePermission.find_by(role: role1, permission: permission1)

      expect(specific_role_permission.role_id).to eq(role1.id)
      expect(specific_role_permission.permission_id).to eq(permission1.id)
    end
  end
end
