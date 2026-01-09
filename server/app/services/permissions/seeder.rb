# frozen_string_literal: true

module Permissions
  # Service to seed permissions and roles from configuration
  class Seeder
  class << self
    def seed!
      ActiveRecord::Base.transaction do
        seed_permissions
        seed_roles
        assign_permissions_to_roles
      end
    end

    private

    def seed_permissions
      Permissions::ALL_PERMISSIONS.each do |name, description|
        # Extract resource and action from permission name
        parts = name.split(".")

        if parts[0] == "admin" || parts[0] == "system"
          category = parts[0]
          # For admin/system permissions, handle nested resources properly
          if parts.length >= 3
            # admin.ai.agents.delete -> resource: agents, action: delete
            # admin.ai.providers.create -> resource: providers, action: create
            resource = parts[1..-2].join(".")  # Everything except first and last part
            action = parts[-1]  # Last part
          else
            # admin.access -> resource: admin, action: access
            resource = parts[0]
            action = parts[1]
          end
        else
          category = "resource"
          # Handle AI permissions specially
          if parts.length >= 3 && parts[0] == "ai"
            # ai.agents.create -> resource: agents, action: create
            resource = parts[1]
            action = parts[2]
          else
            # user.read -> resource: user, action: read
            # api.manage_keys -> resource: api, action: manage_keys
            resource = parts[0]
            action = parts[1..].join("_")
          end
        end

        # Find by resource and action combination, or create new
        permission = Permission.find_or_initialize_by(resource: resource, action: action)

        if permission.new_record?
          permission.name = name
          permission.description = description
          permission.category = category
          permission.save!
        end
      end
    end

    def seed_roles
      Permissions::ROLES.each do |name, config|
        role = Role.find_or_initialize_by(name: name)

        if role.new_record?
          role.display_name = config[:display_name]
          role.description = config[:description]
          role.role_type = config[:role_type]
          role.save!
        end
      end
    end

    def assign_permissions_to_roles
      Permissions::ROLES.each do |role_name, config|
        role = Role.find_by!(name: role_name)
        permission_names = config[:permissions]

        permissions = Permission.where(name: permission_names)
        role.permissions = permissions
      end
    end
  end
  end
end
