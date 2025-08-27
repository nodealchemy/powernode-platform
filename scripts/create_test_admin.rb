#!/usr/bin/env ruby

# Use existing manager user and give it admin permissions
user = User.find_by(email: 'manager@powernode.org')

if user.nil?
  puts "Manager user not found"
  exit 1
end

# Create system admin role if it doesn't exist
admin_role = Role.find_or_create_by(name: 'system.admin') do |role|
  role.description = 'Full system administrator access'
end

# Create the permission if it doesn't exist
permission = Permission.find_or_create_by(resource: 'admin.billing', action: 'manage_gateways') do |perm|
  perm.name = 'admin.billing.manage_gateways'
  perm.description = 'Manage payment gateway configurations'
  perm.category = 'resource'
end

# Associate permission with admin role
unless admin_role.permissions.include?(permission)
  admin_role.permissions << permission
  puts "Added payment gateways permission to admin role"
end

# Assign admin role to user
unless user.roles.include?(admin_role)
  user.roles << admin_role
  puts "Assigned system admin role to test user"
end

puts "Manager user setup complete:"
puts "  Email: manager@powernode.org"
puts "  Roles: #{user.roles.pluck(:name).join(', ')}"
puts "  Has payment gateways permission: #{user.has_permission?('admin.billing.manage_gateways')}"