require 'rails_helper'

RSpec.describe RolePermission, type: :model do
  let(:role_permission) { build(:role_permission) }

  describe "associations" do
    it { should belong_to(:role) }
  end

  describe "validations" do
    describe "catalog membership" do
      it "is valid for a permission that exists in the catalog" do
        rp = build(:role_permission, permission_name: "users.read")
        expect(rp).to be_valid
      end

      it "is invalid for a name that is not in the catalog" do
        rp = build(:role_permission, permission_name: "totally.bogus")
        expect(rp).not_to be_valid
        expect(rp.errors[:permission_name]).to include("is not a defined permission")
      end

      it "is invalid with a blank permission name" do
        rp = build(:role_permission, permission_name: "")
        expect(rp).not_to be_valid
        expect(rp.errors[:permission_name]).to include("can't be blank")
      end
    end

    describe "uniqueness validation" do
      it "validates uniqueness of role_id scoped to permission_name" do
        role = create(:role)
        create(:role_permission, role: role, permission_name: "users.read")
        duplicate = build(:role_permission, role: role, permission_name: "users.read")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:role_id]).to include("has already been taken")
      end

      it "allows the same role with different permissions" do
        role = create(:role)
        create(:role_permission, role: role, permission_name: "users.read")
        different_permission = build(:role_permission, role: role, permission_name: "users.create")

        expect(different_permission).to be_valid
      end

      it "allows the same permission with different roles" do
        role1 = create(:role, name: "unique_test_role_one")
        role2 = create(:role, name: "unique_test_role_two")
        create(:role_permission, role: role1, permission_name: "users.read")
        different_role = build(:role_permission, role: role2, permission_name: "users.read")

        expect(different_role).to be_valid
      end
    end

    describe "association validations" do
      it "requires role to be present" do
        rp = build(:role_permission, role: nil)

        expect(rp).not_to be_valid
        expect(rp.errors[:role]).to include("must exist")
      end
    end
  end

  describe "creation and persistence" do
    it "can be created with a valid role and a catalog permission name" do
      role = create(:role)

      rp = RolePermission.create!(role: role, permission_name: "users.read")

      expect(rp).to be_persisted
      expect(rp.role).to eq(role)
      expect(rp.permission_name).to eq("users.read")
    end

    it "is destroyed when the role is destroyed" do
      role = create(:role)
      create(:role_permission, role: role, permission_name: "users.read")

      expect { role.destroy! }.to change { RolePermission.count }.by(-1)
      expect(RolePermission.where(role_id: role.id)).to be_empty
    end
  end

  describe "integration scenarios" do
    it "connects a role to its granted permission names" do
      admin_role = create(:role, name: "admin_test")
      create(:role_permission, role: admin_role, permission_name: "users.create")
      create(:role_permission, role: admin_role, permission_name: "users.read")

      expect(admin_role.permission_names).to include("users.create", "users.read")
      expect(admin_role.role_permissions.count).to eq(2)
      expect(admin_role.role_permissions.pluck(:permission_name)).to match_array(%w[users.create users.read])
    end

    it "prevents duplicate role-permission assignments" do
      manager_role = create(:role, name: "manager_test")
      create(:role_permission, role: manager_role, permission_name: "page.update")

      initial_count = RolePermission.count
      duplicate = build(:role_permission, role: manager_role, permission_name: "page.update")

      expect(duplicate).not_to be_valid
      expect(RolePermission.count).to eq(initial_count)
    end

    it "handles complex many-to-many relationships across roles" do
      admin_role = create(:role, name: "admin_test")
      editor_role = create(:role, name: "editor_test")
      viewer_role = create(:role, name: "viewer_test")

      # admin has all three page permissions
      create(:role_permission, role: admin_role, permission_name: "page.create")
      create(:role_permission, role: admin_role, permission_name: "page.update")
      create(:role_permission, role: admin_role, permission_name: "page.read")

      # editor has update and read
      create(:role_permission, role: editor_role, permission_name: "page.update")
      create(:role_permission, role: editor_role, permission_name: "page.read")

      # viewer has only read
      create(:role_permission, role: viewer_role, permission_name: "page.read")

      expect(admin_role.role_permissions.count).to eq(3)
      expect(editor_role.role_permissions.count).to eq(2)
      expect(viewer_role.role_permissions.count).to eq(1)

      expect(admin_role.permission_names).to include("page.create", "page.update", "page.read")
      expect(editor_role.permission_names).to include("page.update", "page.read")
      expect(editor_role.permission_names).not_to include("page.create")
      expect(viewer_role.permission_names).to include("page.read")
      expect(viewer_role.permission_names).not_to include("page.create", "page.update")
    end
  end

  describe "database constraints and integrity" do
    it "handles edge cases with nil associations gracefully in validation" do
      rp = RolePermission.new

      expect(rp).not_to be_valid
      expect(rp.errors[:role]).to be_present
      expect(rp.errors[:permission_name]).to be_present
    end
  end

  describe "query and finding" do
    let!(:role1) { create(:role, name: "admin_query_test") }
    let!(:role2) { create(:role, name: "user_query_test") }
    let!(:rp1) { create(:role_permission, role: role1, permission_name: "users.create") }
    let!(:rp2) { create(:role_permission, role: role1, permission_name: "users.read") }
    let!(:rp3) { create(:role_permission, role: role2, permission_name: "users.read") }

    it "can find role_permissions by role" do
      admin_role_permissions = RolePermission.where(role: role1)

      expect(admin_role_permissions.count).to eq(2)
      expect(admin_role_permissions.pluck(:permission_name)).to match_array(%w[users.create users.read])
    end

    it "can find role_permissions by permission name" do
      # Scope to the test roles — global catalog roles seeded by sync_from_config!
      # may also grant users.read, so an absolute count would be brittle.
      read_permission_roles = RolePermission.where(permission_name: "users.read", role_id: [ role1.id, role2.id ])

      expect(read_permission_roles.count).to eq(2)
      expect(read_permission_roles.pluck(:role_id)).to include(role1.id, role2.id)
    end

    it "can find a specific role + permission combination" do
      specific = RolePermission.find_by(role: role1, permission_name: "users.create")

      expect(specific.role_id).to eq(role1.id)
      expect(specific.permission_name).to eq("users.create")
    end
  end
end
