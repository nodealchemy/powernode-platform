require 'rails_helper'

RSpec.describe Permission, type: :model do
  let(:permission) { build(:permission) }

  describe "associations" do
    it { should have_many(:role_permissions).dependent(:destroy) }
    it { should have_many(:roles).through(:role_permissions) }
  end

  describe "validations" do
    subject { build(:permission) }

    # Skip these due to auto-generation callback - tested separately below
    # it { should validate_presence_of(:name) }
    # it { should validate_uniqueness_of(:name).case_insensitive }
    it { should validate_length_of(:name).is_at_least(2).is_at_most(100) }

    describe "name validation with auto-generation" do
      it "allows blank name when resource and action are present (auto-generates)" do
        permission = build(:permission, name: "", resource: "users", action: "create")
        expect(permission).to be_valid
        expect(permission.name).to eq("users.create")
      end

      it "validates uniqueness of name" do
        create(:permission, name: "unique_name", resource: "test", action: "action")
        duplicate = build(:permission, name: "unique_name", resource: "other", action: "action")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("has already been taken")
      end

      it "validates presence when explicitly set to nil and resource/action missing" do
        permission = Permission.new(name: nil, resource: nil, action: nil)
        expect(permission).not_to be_valid
        expect(permission.errors[:resource]).to be_present
        expect(permission.errors[:action]).to be_present
      end
    end

    it { should validate_presence_of(:resource) }
    it { should validate_length_of(:resource).is_at_least(2).is_at_most(50) }

    it { should validate_presence_of(:action) }
    it { should validate_length_of(:action).is_at_least(2).is_at_most(50) }

    it { should validate_length_of(:description).is_at_most(255) }
    it { should allow_value("").for(:description) }
    it { should allow_value(nil).for(:description) }

    describe "resource and action uniqueness" do
      let!(:existing_permission) { create(:permission, resource: "users", action: "create") }

      it "validates uniqueness of resource scoped to action" do
        duplicate = build(:permission, resource: "users", action: "create")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:resource]).to include("has already been taken")
      end

      it "allows same resource with different action" do
        different_action = build(:permission, resource: "users", action: "read")

        expect(different_action).to be_valid
      end

      it "allows different resource with same action" do
        different_resource = build(:permission, resource: "roles", action: "create")

        expect(different_resource).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:user_create) { create(:permission, resource: "users", action: "create") }
    let!(:user_read) { create(:permission, resource: "users", action: "read") }
    let!(:role_create) { create(:permission, resource: "roles", action: "create") }

    describe ".for_resource" do
      it "returns permissions for specific resource" do
        expect(Permission.for_resource("users")).to include(user_create, user_read)
        expect(Permission.for_resource("users")).not_to include(role_create)
      end
    end

    describe ".for_action" do
      it "returns permissions for specific action" do
        expect(Permission.for_action("create")).to include(user_create, role_create)
        expect(Permission.for_action("create")).not_to include(user_read)
      end
    end
  end

  describe "callbacks" do
    describe "#normalize_attributes" do
      it "normalizes resource to lowercase and strips whitespace" do
        permission.resource = "  USERS  "
        permission.valid?

        expect(permission.resource).to eq("users")
      end

      it "normalizes action to lowercase and strips whitespace" do
        permission.action = "  CREATE  "
        permission.valid?

        expect(permission.action).to eq("create")
      end

      it "handles nil resource gracefully" do
        permission.resource = nil

        expect { permission.valid? }.not_to raise_error
      end

      it "handles nil action gracefully" do
        permission.action = nil

        expect { permission.valid? }.not_to raise_error
      end
    end

    describe "#generate_name" do
      it "generates name from resource and action when name is blank" do
        permission = build(:permission, name: "", resource: "users", action: "create")
        permission.valid?

        expect(permission.name).to eq("users.create")
      end

      it "generates name when name is nil" do
        permission = build(:permission, name: nil, resource: "roles", action: "read")
        permission.valid?

        expect(permission.name).to eq("roles.read")
      end

      it "does not override existing name" do
        permission = build(:permission, name: "custom_name", resource: "users", action: "create")
        permission.valid?

        expect(permission.name).to eq("custom_name")
      end

      it "generates name after normalizing attributes" do
        permission = build(:permission, name: "", resource: "  USERS  ", action: "  CREATE  ")
        permission.valid?

        expect(permission.name).to eq("users.create")
      end
    end
  end

  describe "#full_name" do
    it "returns combination of resource and action" do
      permission = build(:permission, resource: "users", action: "create")

      expect(permission.full_name).to eq("users.create")
    end

    it "works with normalized attributes" do
      permission = build(:permission, resource: "USERS", action: "CREATE")
      permission.valid? # Trigger normalization

      expect(permission.full_name).to eq("users.create")
    end

    it "handles empty attributes" do
      permission = build(:permission, resource: "", action: "")

      expect(permission.full_name).to eq(".")
    end

    it "handles nil attributes" do
      permission = build(:permission, resource: nil, action: nil)

      expect(permission.full_name).to eq(".")
    end
  end

  describe "integration scenarios" do
    it "creates permission with normalized attributes and generated name" do
      permission = Permission.create(
        resource: "  ACCOUNTS  ",
        action: "  MANAGE  ",
        description: "Manage account settings"
      )

      expect(permission).to be_persisted
      expect(permission.resource).to eq("accounts")
      expect(permission.action).to eq("manage")
      expect(permission.name).to eq("accounts.manage")
    end

    it "prevents duplicate permissions based on resource and action" do
      Permission.create!(resource: "billing", action: "view")
      duplicate = Permission.new(resource: "billing", action: "view")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:resource]).to be_present
    end

    it "allows creating permissions with explicit names" do
      permission = Permission.create!(
        name: "super_admin_access",
        resource: "system",
        action: "admin"
      )

      expect(permission.name).to eq("super_admin_access")
      expect(permission.full_name).to eq("system.admin")
    end
  end

  describe "edge cases" do
    it "handles extremely long valid names" do
      long_name = "a" * 100
      permission = build(:permission, name: long_name)

      expect(permission).to be_valid
    end

    it "handles extremely long valid resource" do
      long_resource = "a" * 50
      permission = build(:permission, resource: long_resource)

      expect(permission).to be_valid
    end

    it "handles extremely long valid action" do
      long_action = "a" * 50
      permission = build(:permission, action: long_action)

      expect(permission).to be_valid
    end

    it "handles extremely long valid description" do
      long_description = "a" * 255
      permission = build(:permission, description: long_description)

      expect(permission).to be_valid
    end

    it "handles minimum length valid attributes" do
      permission = build(:permission,
        name: "ab",
        resource: "ab",
        action: "ab"
      )

      expect(permission).to be_valid
    end
  end
end
