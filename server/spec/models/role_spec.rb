require 'rails_helper'

RSpec.describe Role, type: :model do
  let(:role) { build(:role) }

  describe "associations" do
    it { should have_many(:role_permissions).dependent(:delete_all) }
    it { should belong_to(:account).optional }
    it { should have_many(:user_roles).dependent(:destroy) }
    it { should have_many(:users).through(:user_roles) }
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

    before do
      role.role_permissions.create!(permission_name: "users.create")
      role.role_permissions.create!(permission_name: "users.read")
    end

    it "returns true when role has the permission" do
      expect(role.has_permission?("users.create")).to be true
      expect(role.has_permission?("users.read")).to be true
    end

    it "returns false when role does not have the permission" do
      expect(role.has_permission?("users.delete")).to be false
    end

    it "returns false for non-existent permissions" do
      expect(role.has_permission?("nonexistent.permission")).to be false
    end

    it "handles case sensitivity correctly" do
      expect(role.has_permission?("USERS.CREATE")).to be false
    end

    it "grants any permission when the role holds system.admin (wildcard)" do
      admin_role = create(:role, name: "wildcard_role", role_type: "admin")
      admin_role.role_permissions.create!(permission_name: "system.admin")

      expect(admin_role.has_permission?("users.delete")).to be true
      expect(admin_role.has_permission?("admin.access")).to be true
    end
  end

  describe "#add_permission" do
    let(:role) { create(:role) }

    it "adds permission to role when not already present" do
      expect {
        role.add_permission("page.read")
      }.to change { role.role_permissions.count }.by(1)

      expect(role.has_permission?("page.read")).to be true
    end

    it "does not add duplicate permission" do
      role.role_permissions.create!(permission_name: "page.read")

      expect {
        role.add_permission("page.read")
      }.not_to change { role.role_permissions.count }
    end

    it "rejects a permission name that is not in the catalog" do
      expect {
        role.add_permission("new.permission")
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(role.has_permission?("new.permission")).to be false
    end
  end

  describe "#remove_permission" do
    let(:role) { create(:role) }

    before do
      role.role_permissions.create!(permission_name: "page.read")
      role.role_permissions.create!(permission_name: "page.update")
    end

    it "removes permission from role" do
      expect {
        role.remove_permission("page.read")
      }.to change { role.role_permissions.count }.by(-1)

      expect(role.has_permission?("page.read")).to be false
      expect(role.has_permission?("page.update")).to be true
    end

    it "does nothing when permission is not present" do
      expect {
        role.remove_permission("nonexistent.permission")
      }.not_to change { role.role_permissions.count }
    end
  end

  describe "#permission_names" do
    let(:role) { create(:role) }

    it "returns the sorted, granted permission names" do
      role.role_permissions.create!(permission_name: "users.read")
      role.role_permissions.create!(permission_name: "users.create")

      expect(role.permission_names).to eq(%w[users.create users.read])
    end

    it "expands to the entire catalog for a system.admin role" do
      admin_role = create(:role, name: "catalog_admin_role", role_type: "admin")
      admin_role.role_permissions.create!(permission_name: "system.admin")

      expect(admin_role.permission_names).to match_array(Permissions.all_permissions.keys)
    end
  end

  describe "#sync_permissions!" do
    let(:role) { create(:role) }

    it "reconciles grants to exactly the desired catalog names" do
      role.role_permissions.create!(permission_name: "users.read")

      role.sync_permissions!(%w[users.create users.update])

      expect(role.reload.permission_names).to match_array(%w[users.create users.update])
      expect(role.has_permission?("users.read")).to be false
    end

    it "drops names that are not in the catalog" do
      role.sync_permissions!(%w[users.read totally.bogus])

      expect(role.reload.permission_names).to eq(%w[users.read])
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

      # Add permissions (by catalog name)
      role.add_permission("page.create")
      role.add_permission("page.update")

      expect(role.has_permission?("page.create")).to be true
      expect(role.has_permission?("page.update")).to be true

      # Remove permission
      role.remove_permission("page.create")

      expect(role.has_permission?("page.create")).to be false
      expect(role.has_permission?("page.update")).to be true
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
    let(:permission_names) { %w[users.create users.read users.update users.delete] }

    it "can manage multiple permissions efficiently" do
      # Add multiple permissions (all real catalog names)
      permission_names.each { |name| role.add_permission(name) }

      expect(role.role_permissions.count).to eq(4)
      permission_names.each do |name|
        expect(role.has_permission?(name)).to be true
      end

      # Remove some permissions
      role.remove_permission(permission_names[0])
      role.remove_permission(permission_names[2])

      expect(role.role_permissions.count).to eq(2)
      expect(role.has_permission?(permission_names[1])).to be true
      expect(role.has_permission?(permission_names[3])).to be true
    end
  end

  describe "#grant_to_user" do
    let(:role) { create(:role) }
    let(:target_user) { create(:user) }
    let(:granting_user) { create(:user) }

    it "records the granting user on a new attributed grant" do
      # IMP-88c729391339: UserRole has no `granted_by` writer — the association
      # is `granted_by_user` (FK `granted_by_id`) — so the block inside
      # find_or_create_by! used to raise NoMethodError on every new attributed
      # grant.
      role.grant_to_user(target_user, granting_user)

      user_role = UserRole.find_by(user: target_user, role: role)
      expect(user_role.granted_by_user).to eq(granting_user)
      expect(user_role.granted_by_id).to eq(granting_user.id)
    end

    it "leaves granted_by_user nil when no grantor is given" do
      role.grant_to_user(target_user)

      user_role = UserRole.find_by(user: target_user, role: role)
      expect(user_role.granted_by_user).to be_nil
    end

    it "is a no-op on an existing grant (does not re-run the create block)" do
      role.grant_to_user(target_user)

      expect { role.grant_to_user(target_user, granting_user) }.not_to raise_error
      user_role = UserRole.find_by(user: target_user, role: role)
      expect(user_role.granted_by_user).to be_nil
    end
  end
end
