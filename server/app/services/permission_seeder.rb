# frozen_string_literal: true

# Service to seed permissions and roles from configuration
class PermissionSeeder
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
        parts = name.split('.')
        
        if parts[0] == 'admin' || parts[0] == 'system'
          category = parts[0]
          resource = parts[1]
          action = parts[2..].join('_') if parts.length > 2
          action ||= parts[1]
        else
          category = 'resource'
          resource = parts[0]
          action = parts[1..].join('_')
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