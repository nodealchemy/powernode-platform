#!/usr/bin/env ruby

# Add payment gateway permission to manager user
user = User.find_by(email: 'manager@powernode.org')
permission = Permission.find_by(resource: 'settings', action: 'payment')

if user && permission
  # Find one of the user's existing roles to add the permission to
  role = user.roles.first
  
  if role && !role.permissions.include?(permission)
    RolePermission.create!(role: role, permission: permission)
    puts "Added settings.payment permission to role: #{role.name}"
  else
    puts "Permission already exists or role not found"
  end
  
  # Verify the permission was added
  user.reload
  permissions = user.permissions.pluck(:resource, :action).map { |r, a| "#{r}.#{a}" }
  
  puts "User now has settings.payment: #{permissions.include?('settings.payment')}"
  puts "User payment-related permissions:"
  payment_perms = permissions.select { |p| p.include?('payment') || p.include?('billing') }
  payment_perms.each { |p| puts "  #{p}" }
else
  puts "User or permission not found"
end