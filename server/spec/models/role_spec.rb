require 'rails_helper'

RSpec.describe Role, type: :model do
  let(:role) { build(:role) }

  describe "associations" do
    it { should have_many(:role_permissions).dependent(:destroy) }
    it { should have_many(:permissions).through(:role_permissions) }
  end

  describe "validations" do
    subject { build(:role) }

    it { should validate_presence_of(:name) }
    # Skip due to normalization callback interfering - tested separately below
    # it { should validate_uniqueness_of(:name).case_insensitive }
    it { should validate_length_of(:name).is_at_least(2).is_at_most(50) }
    it { should validate_length_of(:description).is_at_most(255) }
    it { should allow_value("").for(:description) }
    it { should allow_value(nil).for(:description) }

    describe "name uniqueness with normalization" do
      it "validates uniqueness after normalization" do
        create(:role, name: "Test Role")
        duplicate = build(:role, name: "test role") # Different case but will normalize to same

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("has already been taken")
      end
    end
  end

  describe "scopes" do
    let!(:system_role) { create(:role, system_role: true) }
    let!(:custom_role1) { create(:role, system_role: false) }
    let!(:custom_role2) { create(:role, system_role: false) }

    describe ".system_roles" do
      it "returns only system roles" do
        expect(Role.system_roles).to include(system_role)
        expect(Role.system_roles).not_to include(custom_role1, custom_role2)
      end
    end

    describe ".custom_roles" do
      it "returns only custom roles" do
        expect(Role.custom_roles).to include(custom_role1, custom_role2)
        expect(Role.custom_roles).not_to include(system_role)
      end
    end
  end

  describe "callbacks" do
    describe "#normalize_name" do
      it "normalizes name by stripping whitespace and titleizing" do
        role.name = "  admin role  "
        role.valid?

        expect(role.name).to eq("Admin Role")
      end

      it "titleizes lowercase names" do
        role.name = "manager"
        role.valid?

        expect(role.name).to eq("Manager")
      end

      it "titleizes uppercase names" do
        role.name = "SUPER_ADMIN"
        role.valid?

        expect(role.name).to eq("Super Admin")
      end

      it "handles mixed case names" do
        role.name = "cusTom_UsEr"
        role.valid?

        expect(role.name).to eq("Cus Tom Us Er")
      end

      it "handles names with special characters" do
        role.name = "role-name_with-special"
        role.valid?

        expect(role.name).to eq("Role Name With Special")
      end

      it "handles nil name gracefully" do
        role.name = nil

        expect { role.valid? }.not_to raise_error
      end
    end
  end

  describe "#system_role?" do
    it "returns true when system_role is true" do
      role.system_role = true
      expect(role.system_role?).to be true
    end

    it "returns false when system_role is false" do
      role.system_role = false
      expect(role.system_role?).to be false
    end

    it "returns false when system_role is nil" do
      role.system_role = nil
      expect(role.system_role?).to be_falsy
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
    let(:permission) { create(:permission) }

    it "adds permission to role when not already present" do
      expect {
        role.add_permission(permission)
      }.to change { role.permissions.count }.by(1)

      expect(role.permissions).to include(permission)
    end

    it "does not add duplicate permission" do
      role.permissions << permission

      expect {
        role.add_permission(permission)
      }.not_to change { role.permissions.count }
    end

    it "uses has_permission? to check for duplicates" do
      role.permissions << permission
      allow(role).to receive(:has_permission?).with(permission.name).and_return(true)

      expect {
        role.add_permission(permission)
      }.not_to change { role.permissions.count }
    end
  end

  describe "#remove_permission" do
    let(:role) { create(:role) }
    let(:permission1) { create(:permission) }
    let(:permission2) { create(:permission) }

    before do
      role.permissions << permission1
      role.permissions << permission2
    end

    it "removes permission from role" do
      expect {
        role.remove_permission(permission1)
      }.to change { role.permissions.count }.by(-1)

      expect(role.permissions).not_to include(permission1)
      expect(role.permissions).to include(permission2)
    end

    it "does nothing when permission is not present" do
      new_permission = create(:permission)

      expect {
        role.remove_permission(new_permission)
      }.not_to change { role.permissions.count }
    end
  end

  describe "integration scenarios" do
    it "creates role with normalized name" do
      role = Role.create!(name: "  content_manager  ", description: "Manages content")

      expect(role).to be_persisted
      expect(role.name).to eq("Content Manager")
    end

    it "manages permissions correctly" do
      role = create(:role)
      permission1 = create(:permission, name: "posts.create")
      permission2 = create(:permission, name: "posts.edit")

      # Add permissions
      role.add_permission(permission1)
      role.add_permission(permission2)

      expect(role.has_permission?("posts.create")).to be true
      expect(role.has_permission?("posts.edit")).to be true

      # Remove permission
      role.remove_permission(permission1)

      expect(role.has_permission?("posts.create")).to be false
      expect(role.has_permission?("posts.edit")).to be true
    end

    it "prevents duplicate role names" do
      Role.create!(name: "Admin")
      duplicate = Role.new(name: "admin") # Different case

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "handles system vs custom roles" do
      system_role = create(:role, name: "System Admin", system_role: true)
      custom_role = create(:role, name: "Custom Manager", system_role: false)

      expect(system_role.system_role?).to be true
      expect(custom_role.system_role?).to be false

      expect(Role.system_roles).to include(system_role)
      expect(Role.custom_roles).to include(custom_role)
    end
  end

  describe "edge cases" do
    it "handles extremely long valid names" do
      long_name = "a" * 50
      role = build(:role, name: long_name)

      expect(role).to be_valid
    end

    it "handles extremely long valid descriptions" do
      long_description = "a" * 255
      role = build(:role, description: long_description)

      expect(role).to be_valid
    end

    it "handles minimum length valid names" do
      role = build(:role, name: "ab")

      expect(role).to be_valid
      # Will be titleized after validation
    end

    it "titleizes minimum length names correctly" do
      role = build(:role, name: "ab")
      role.valid?

      expect(role.name).to eq("Ab")
    end

    it "handles names with numbers" do
      role = build(:role, name: "admin_level_2")
      role.valid?

      expect(role.name).to eq("Admin Level 2")
    end

    it "handles single character after normalization" do
      role = build(:role, name: "a")

      expect(role).not_to be_valid
      expect(role.errors[:name]).to include("is too short (minimum is 2 characters)")
    end

    it "handles empty name after normalization" do
      role = build(:role, name: "  ")

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
      permissions.each { |p| role.add_permission(p) }

      expect(role.permissions.count).to eq(4)
      permissions.each do |permission|
        expect(role.has_permission?(permission.name)).to be true
      end

      # Remove some permissions
      role.remove_permission(permissions[0])
      role.remove_permission(permissions[2])

      expect(role.permissions.count).to eq(2)
      expect(role.has_permission?(permissions[1].name)).to be true
      expect(role.has_permission?(permissions[3].name)).to be true
    end
  end
end
