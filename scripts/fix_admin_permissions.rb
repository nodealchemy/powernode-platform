#!/usr/bin/env ruby

# Fix admin permissions for manager user
user = User.find_by(email: 'manager@powernode.org')

if user.nil?
  puts "Manager user not found"
  exit 1
end

# Create required permissions
required_permissions = [
  { resource: 'admin', action: 'settings.view', name: 'admin.settings.view', description: 'View admin settings' },
  { resource: 'admin.billing', action: 'manage_gateways', name: 'admin.billing.manage_gateways', description: 'Manage payment gateways' }
]

required_permissions.each do |perm_data|
  permission = Permission.find_or_create_by(resource: perm_data[:resource], action: perm_data[:action]) do |perm|
    perm.name = perm_data[:name]
    perm.description = perm_data[:description]
    perm.category = 'resource'
  end
  
  # Find or create admin role
  admin_role = Role.find_or_create_by(name: 'system.admin') do |role|
    role.description = 'Full system administrator access'
    role.display_name = 'System Administrator'
    role.role_type = 'system'
  end

  # Associate permission with admin role
  unless admin_role.permissions.include?(permission)
    RolePermission.find_or_create_by(role: admin_role, permission: permission)
    puts "Added #{perm_data[:name]} permission to admin role"
  end

  # Assign admin role to user
  unless user.roles.include?(admin_role)
    UserRole.find_or_create_by(user: user, role: admin_role)
    puts "Assigned system admin role to manager user"
  end
end

puts
puts "Manager user permissions updated:"
puts "  Email: manager@powernode.org"
puts "  Roles: #{user.reload.roles.pluck(:name).join(', ')}"
puts "  Has admin.settings.view: #{user.has_permission?('admin.settings.view')}"
puts "  Has admin.billing.manage_gateways: #{user.has_permission?('admin.billing.manage_gateways')}"