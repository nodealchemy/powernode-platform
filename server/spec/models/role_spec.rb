require 'rails_helper'

RSpec.describe Role, type: :model do
  let(:role) { build(:role) }

  describe "associations" do
    it { should have_many(:role_permissions).dependent(:delete_all) }
    it { should have_many(:permissions).through(:role_permissions) }
  end

  describe "validations" do
    subject { build(:role) }

    it { should validate_presence_of(:name) }
    # Skip due to normalization callback interfering - tested separately below
    # it { should validate_uniqueness_of(:name).case_insensitive }
    # Name format is validated with regex, not length
    it { should validate_presence_of(:display_name) }
    it { should validate_presence_of(:role_type) }
    it { should validate_inclusion_of(:role_type).in_array(%w[user admin system]) }
    it { should allow_value("").for(:description) }
    it { should allow_value(nil).for(:description) }

    describe "name uniqueness" do
      it "validates uniqueness" do
        create(:role, name: "test_role")
        duplicate = build(:role, name: "test_role")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("has already been taken")
      end
    end
  end

  describe "scopes" do
    let!(:user_role) { create(:role, name: 'test_user_role', role_type: 'user') }
    let!(:admin_role) { create(:role, name: 'test_admin_role', role_type: 'admin') }
    let!(:system_role) { create(:role, name: 'test_system_role', role_type: 'system', is_system: true) }
    let!(:non_system_role) { create(:role, name: 'test_non_system_role', is_system: false) }

    describe ".user_roles" do
      it "returns only user roles" do
        expect(Role.user_roles).to include(user_role)
        expect(Role.user_roles).not_to include(admin_role, system_role)
      end
    end

    describe ".admin_roles" do
      it "returns only admin roles" do
        expect(Role.admin_roles).to include(admin_role)
        expect(Role.admin_roles).not_to include(user_role, system_role)
      end
    end

    describe ".system_roles" do
      it "returns only system roles" do
        expect(Role.system_roles).to include(system_role)
        expect(Role.system_roles).not_to include(user_role, admin_role)
      end
    end

    describe ".non_system" do
      it "returns only non-system roles" do
        expect(Role.non_system).to include(non_system_role, user_role, admin_role)
        expect(Role.non_system).not_to include(system_role)
      end
    end
  end

  describe "name format validation" do
    it "allows lowercase letters and underscores" do
      role.name = "admin_user"
      expect(role).to be_valid
    end

    it "rejects uppercase letters" do
      role.name = "Admin_User"
      expect(role).not_to be_valid
      expect(role.errors[:name]).to include("must be lowercase with underscores or dots only")
    end

    it "rejects spaces" do
      role.name = "admin user"
      expect(role).not_to be_valid
    end

    it "rejects special characters" do
      role.name = "admin-user"
      expect(role).not_to be_valid
    end
  end

  describe "role type methods" do
    it "#user_role? returns true for user roles" do
      role.role_type = 'user'
      expect(role.user_role?).to be true
      expect(role.admin_role?).to be false
      expect(role.system_role?).to be false
    end

    it "#admin_role? returns true for admin roles" do
      role.role_type = 'admin'
      expect(role.admin_role?).to be true
      expect(role.user_role?).to be false
      expect(role.system_role?).to be false
    end

    it "#system_role? returns true for system roles" do
      role.role_type = 'system'
      expect(role.system_role?).to be true
      expect(role.user_role?).to be false
      expect(role.admin_role?).to be false
    end
  end

  describe "#has_permission?" do
    let(:role) { create(:role) }
    let!(:permission1) { create(:permission, name: "users.create") }
    let!(:permission2) { create(:permission, name: "users.read") }
    let!(:permission3) { create(:permission, name: "roles.create") }

    before do
      role.permissions << permission1
      role.permissions << permission2
    end

    it "returns true when role has the permission" do
      expect(role.has_permission?("users.create")).to be true
      expect(role.has_permission?("users.read")).to be true
    end

    it "returns false when role does not have the permission" do
      expect(role.has_permission?("roles.create")).to be false
    end

    it "returns false for non-existent permissions" do
      expect(role.has_permission?("nonexistent.permission")).to be false
    end

    it "handles case sensitivity correctly" do
      expect(role.has_permission?("USERS.CREATE")).to be false
    end
  end

  describe "#add_permission" do
    let(:role) { create(:role) }
    let(:permission) { create(:permission, name: "test.permission") }

    it "adds permission to role when not already present" do
      expect {
        role.add_permission("test.permission")
      }.to change { role.permissions.count }.by(1)

      expect(role.has_permission?("test.permission")).to be true
    end

    it "does not add duplicate permission" do
      role.permissions << permission

      expect {
        role.add_permission("test.permission")
      }.not_to change { role.permissions.count }
    end

    it "creates permission if it doesn't exist" do
      expect {
        role.add_permission("new.permission")
      }.to change { Permission.count }.by(1)

      expect(role.has_permission?("new.permission")).to be true
    end
  end

  describe "#remove_permission" do
    let(:role) { create(:role) }
    let(:permission1) { create(:permission, name: "perm.one") }
    let(:permission2) { create(:permission, name: "perm.two") }

    before do
      role.permissions << permission1
      role.permissions << permission2
    end

    it "removes permission from role" do
      expect {
        role.remove_permission("perm.one")
      }.to change { role.permissions.count }.by(-1)

      expect(role.has_permission?("perm.one")).to be false
      expect(role.has_permission?("perm.two")).to be true
    end

    it "does nothing when permission is not present" do
      expect {
        role.remove_permission("nonexistent.permission")
      }.not_to change { role.permissions.count }
    end
  end

  describe "integration scenarios" do
    it "creates role with valid name format" do
      unique_suffix = Array.new(8) { ('a'..'z').to_a.sample }.join
      role = Role.create!(
        name: "test_content_manager_#{unique_suffix}",
        display_name: "Test Content Manager #{unique_suffix}",
        description: "Manages content",
        role_type: "user"
      )

      expect(role).to be_persisted
      expect(role.name).to eq("test_content_manager_#{unique_suffix}")
    end

    it "manages permissions correctly" do
      role = create(:role)
      permission1 = create(:permission, name: "posts.create")
      permission2 = create(:permission, name: "posts.edit")

      # Add permissions
      role.add_permission(permission1.name)
      role.add_permission(permission2.name)

      expect(role.has_permission?("posts.create")).to be true
      expect(role.has_permission?("posts.edit")).to be true

      # Remove permission
      role.remove_permission(permission1.name)

      expect(role.has_permission?("posts.create")).to be false
      expect(role.has_permission?("posts.edit")).to be true
    end

    it "prevents duplicate role names" do
      Role.create!(name: "admin_test", display_name: "Admin Test", role_type: "admin")
      duplicate = Role.new(name: "admin_test", display_name: "Admin Test", role_type: "admin")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "handles system vs custom roles" do
      system_role = create(:role, name: "system_admin_test", display_name: "System Admin", role_type: "system", is_system: true)
      custom_role = create(:role, name: "custom_manager_test", display_name: "Custom Manager", role_type: "user", is_system: false)

      expect(system_role.system_role?).to be true
      expect(custom_role.system_role?).to be false

      expect(Role.system_roles).to include(system_role)
      expect(Role.non_system).to include(custom_role)
    end
  end

  describe "edge cases" do
    it "handles valid role names with underscores" do
      role = build(:role, name: "super_long_role_name_with_underscores")
      expect(role).to be_valid
    end

    it "rejects names with uppercase letters" do
      role = build(:role, name: "Admin_Role")
      expect(role).not_to be_valid
      expect(role.errors[:name]).to include("must be lowercase with underscores or dots only")
    end

    it "rejects names with spaces" do
      role = build(:role, name: "admin role")
      expect(role).not_to be_valid
    end

    it "rejects names with dashes" do
      role = build(:role, name: "admin-role")
      expect(role).not_to be_valid
    end

    it "handles names with numbers" do
      role = build(:role, name: "admin2")
      expect(role).not_to be_valid # numbers not allowed in format
    end

    it "handles empty name" do
      role = build(:role, name: "")
      expect(role).not_to be_valid
      expect(role.errors[:name]).to include("can't be blank")
    end
  end

  describe "complex permission management" do
    let(:role) { create(:role) }
    let(:permissions) do
      [
        create(:permission, name: "users.create"),
        create(:permission, name: "users.read"),
        create(:permission, name: "users.update"),
        create(:permission, name: "users.delete")
      ]
    end

    it "can manage multiple permissions efficiently" do
      # Add multiple permissions
      permissions.each { |p| role.add_permission(p.name) }

      expect(role.permissions.count).to eq(4)
      permissions.each do |permission|
        expect(role.has_permission?(permission.name)).to be true
      end

      # Remove some permissions
      role.remove_permission(permissions[0].name)
      role.remove_permission(permissions[2].name)

      expect(role.permissions.count).to eq(2)
      expect(role.has_permission?(permissions[1].name)).to be true
      expect(role.has_permission?(permissions[3].name)).to be true
    end
  end
end
