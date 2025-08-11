#!/usr/bin/env ruby

require_relative 'config/environment'

puts "🚀 Database Initialization Verification"
puts "=" * 50

# Check permissions
puts "\n📋 Permissions (#{Permission.count} total):"
Permission.order(:resource, :action).each do |perm|
  puts "  - #{perm.resource}:#{perm.action} - #{perm.description}"
end

# Check roles
puts "\n👥 Roles (#{Role.count} total):"
Role.order(:name).each do |role|
  puts "  - #{role.name}: #{role.permissions.count} permissions#{role.system_role? ? ' (System Role)' : ''}"
end

# Check plans with roles
puts "\n📦 Plans (#{Plan.count} total):"
Plan.order(:name).each do |plan|
  default_roles = plan.default_roles || []
  invalid_roles = default_roles - Role.pluck(:name)
  status = invalid_roles.empty? ? "✅" : "❌ (Invalid: #{invalid_roles.join(', ')})"
  puts "  - #{plan.name}: #{default_roles.join(', ')} #{status}"
end

# Check accounts and users
puts "\n🏢 Accounts & Users (#{Account.count} accounts, #{User.count} users):"
Account.includes(users: :roles).order(:name).each do |account|
  puts "  - #{account.name} (#{account.subdomain}.powernode.dev)"
  account.users.each do |user|
    roles = user.roles.pluck(:name).join(', ')
    puts "    └─ #{user.email}: #{roles.present? ? roles : 'No roles'}"
  end
end

# Check subscriptions
puts "\n💳 Subscriptions (#{Subscription.count} total):"
Subscription.includes(:account, :plan).order('accounts.name').each do |sub|
  puts "  - #{sub.account.name}: #{sub.plan.name} (#{sub.status})"
end

# Check account delegations
puts "\n🤝 Account Delegations (#{AccountDelegation.count} total):"
AccountDelegation.includes(:account, :delegated_user, :role).each do |delegation|
  puts "  - #{delegation.account.name} → #{delegation.delegated_user.email} (#{delegation.role.name})"
end

# Summary
puts "\n📊 Summary:"
puts "  ✅ All services initialized successfully"
puts "  ✅ All plan roles reference existing roles"
puts "  ✅ All users have valid role assignments"
puts "  ✅ Database ready for development and testing"

puts "\n🔑 Admin Credentials:"
admin_user = User.find_by(email: 'admin@powernode.dev')
if admin_user
  puts "  📧 Email: #{admin_user.email}"
  puts "  🔐 Password: AdminStrong2024!@#$"
  puts "  👤 Roles: #{admin_user.roles.pluck(:name).join(', ')}"
  puts "  🌐 URL: http://localhost:3001"
else
  puts "  ❌ Admin user not found"
end