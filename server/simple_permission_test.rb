#!/usr/bin/env ruby

require_relative 'config/environment'

puts '🔐 Simple Permission System Test'
puts '=' * 40

# Get test data
admin_account = Account.find_by(name: 'Powernode Administration')
enterprise_account = Account.find_by(name: 'Enterprise Solutions LLC')
enterprise_owner = enterprise_account.users.first

# Create test user
test_user = User.create!(
  account: admin_account,
  email: 'custom_perm_test@example.com',
  first_name: 'Custom',
  last_name: 'Permissions',
  password: 'TestPassword2024!@#$',
  password_confirmation: 'TestPassword2024!@#$',
  status: 'active',
  email_verified: true,
  email_verified_at: Time.current
)

puts "Created test user: #{test_user.email}"

# Create delegation service
service = DelegationService.new(enterprise_owner, enterprise_account)

# Test: Create delegation with only specific permissions
specific_permissions = Permission.where(
  resource: ['users', 'accounts'], 
  action: 'read'
)

puts "\nCreating permission-specific delegation..."
puts "Permissions to assign: #{specific_permissions.map { |p| "#{p.resource}.#{p.action}" }.join(', ')}"

result = service.create_delegation(
  delegated_user_email: test_user.email,
  permission_ids: specific_permissions.pluck(:id),
  expires_at: 3.months.from_now,
  notes: 'Custom permissions only - no role'
)

if result[:success]
  delegation = result[:delegation]
  puts '✅ SUCCESS: Created permission-specific delegation'
  puts "   Permission source: #{delegation.permission_source}"
  puts "   Custom permissions: #{delegation.permissions.count}"
  puts "   Effective permissions: #{delegation.effective_permissions.count}"
  puts "   Permission list: #{delegation.permissions.map { |p| "#{p.resource}.#{p.action}" }.join(', ')}"
  puts "   Can manage account: #{delegation.can_manage_account?}"
  puts "   Has users.read: #{delegation.has_permission?('users.read')}"
  puts "   Has accounts.update: #{delegation.has_permission?('accounts.update')}"
  
  # Test dynamic permission management
  puts "\nTesting dynamic permission management..."
  billing_permission = Permission.find_by(resource: 'billing', action: 'read')
  
  add_result = service.add_permission_to_delegation(
    delegation: delegation,
    permission_id: billing_permission.id
  )
  
  if add_result[:success]
    delegation.reload
    puts "✅ Added billing.read permission"
    puts "   New permission count: #{delegation.permissions.count}"
    puts "   Has billing.read: #{delegation.has_permission?('billing.read')}"
  else
    puts "❌ Failed to add permission: #{add_result[:errors].join(', ')}"
  end
  
else
  puts '❌ FAILED: ' + result[:errors].join(', ')
end

# Show current delegation state
puts "\nCurrent delegations with permissions:"
AccountDelegation.includes(:permissions, :role, :delegated_user).each do |d|
  puts "#{d.delegated_user.email}: #{d.permission_source} (#{d.effective_permissions.count} permissions)"
  if d.permissions.any?
    puts "  Custom: #{d.permissions.map { |p| "#{p.resource}.#{p.action}" }.join(', ')}"
  end
end

# Test routes
puts "\nTesting routes:"
puts `rails routes | grep delegation`

# Cleanup
puts "\nCleaning up..."
AccountDelegation.where(delegated_user: test_user).destroy_all
test_user.destroy
puts '✅ Cleanup completed'
puts "\n🚀 Permission System Working!"