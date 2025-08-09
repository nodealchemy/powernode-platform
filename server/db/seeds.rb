# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "Seeding Powernode platform..."

# Create basic permissions
permissions_data = [
  # Account management
  { resource: 'accounts', action: 'read', description: 'View account details' },
  { resource: 'accounts', action: 'update', description: 'Update account settings' },
  { resource: 'accounts', action: 'delete', description: 'Delete account' },

  # User management
  { resource: 'users', action: 'read', description: 'View users' },
  { resource: 'users', action: 'create', description: 'Create new users' },
  { resource: 'users', action: 'update', description: 'Update user information' },
  { resource: 'users', action: 'delete', description: 'Delete users' },

  # Role management
  { resource: 'roles', action: 'read', description: 'View roles' },
  { resource: 'roles', action: 'create', description: 'Create new roles' },
  { resource: 'roles', action: 'update', description: 'Update roles' },
  { resource: 'roles', action: 'delete', description: 'Delete roles' },

  # Subscription management
  { resource: 'subscriptions', action: 'read', description: 'View subscriptions' },
  { resource: 'subscriptions', action: 'create', description: 'Create subscriptions' },
  { resource: 'subscriptions', action: 'update', description: 'Update subscriptions' },
  { resource: 'subscriptions', action: 'delete', description: 'Cancel subscriptions' },

  # Billing management
  { resource: 'billing', action: 'read', description: 'View billing information' },
  { resource: 'billing', action: 'update', description: 'Update billing settings' },

  # Analytics access
  { resource: 'analytics', action: 'read', description: 'View analytics and reports' },
  { resource: 'analytics', action: 'export', description: 'Export analytics data' },
  { resource: 'analytics', action: 'global', description: 'View global analytics across all accounts' }
]

permissions_data.each do |perm_data|
  Permission.find_or_create_by!(
    resource: perm_data[:resource],
    action: perm_data[:action]
  ) do |permission|
    permission.description = perm_data[:description]
  end
end

puts "Created #{Permission.count} permissions"

# Create system roles
owner_role = Role.find_or_create_by!(name: 'Owner') do |role|
  role.description = 'Account owner with full access to all features'
  role.system_role = true
end

admin_role = Role.find_or_create_by!(name: 'Admin') do |role|
  role.description = 'Administrator with management access'
  role.system_role = true
end

member_role = Role.find_or_create_by!(name: 'Member') do |role|
  role.description = 'Basic member with limited access'
  role.system_role = true
end

# Assign all permissions to Owner
owner_role.permissions = Permission.all

# Assign most permissions to Admin (except account deletion)
admin_permissions = Permission.where.not(resource: 'accounts', action: 'delete')
admin_role.permissions = admin_permissions

# Assign basic permissions to Member
member_permissions = Permission.where(
  resource: [ 'accounts', 'users', 'subscriptions', 'billing' ],
  action: 'read'
)
member_role.permissions = member_permissions

puts "Created #{Role.count} roles:"
puts "- Owner: #{owner_role.permissions.count} permissions"
puts "- Admin: #{admin_role.permissions.count} permissions"
puts "- Member: #{member_role.permissions.count} permissions"

# Create default plans
administrator_plan = Plan.find_or_create_by!(name: 'Administrator') do |plan|
  plan.description = 'Special plan for system administrators with zero cost and unlimited access'
  plan.price_cents = 0  # Free
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 0  # No trial needed
  plan.features = {
    'dashboard_access' => true,
    'basic_analytics' => true,
    'advanced_analytics' => true,
    'email_support' => true,
    'priority_support' => true,
    'api_access' => true,
    'custom_integrations' => true,
    'dedicated_support' => true,
    'global_analytics' => true,
    'system_administration' => true,
    'user_management' => true,
    'account_management' => true,
    'billing_management' => true,
    'platform_monitoring' => true,
    'security_administration' => true
  }
  plan.limits = {
    'users' => -1,  # unlimited
    'projects' => -1,  # unlimited
    'storage_gb' => -1,  # unlimited
    'api_requests_per_month' => -1,  # unlimited
    'accounts_managed' => -1,  # unlimited
    'global_access' => true
  }
  plan.default_roles = [ 'Admin', 'Owner' ]
  plan.status = 'active'
  plan.is_public = false  # Not publicly available, assigned by system admins only
end

starter_plan = Plan.find_or_create_by!(name: 'Starter') do |plan|
  plan.description = 'Perfect for individuals and small teams getting started'
  plan.price_cents = 999  # $9.99
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 14
  plan.features = {
    'dashboard_access' => true,
    'basic_analytics' => true,
    'email_support' => true,
    'api_access' => false,
    'advanced_analytics' => false,
    'priority_support' => false
  }
  plan.limits = {
    'users' => 5,
    'projects' => 10,
    'storage_gb' => 5,
    'api_requests_per_month' => 0
  }
  plan.default_roles = [ 'Member' ]
  plan.status = 'active'
  plan.is_public = true
end

professional_plan = Plan.find_or_create_by!(name: 'Professional') do |plan|
  plan.description = 'For growing teams with advanced needs'
  plan.price_cents = 2999  # $29.99
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 14
  plan.features = {
    'dashboard_access' => true,
    'basic_analytics' => true,
    'email_support' => true,
    'api_access' => true,
    'advanced_analytics' => true,
    'priority_support' => false
  }
  plan.limits = {
    'users' => 25,
    'projects' => 100,
    'storage_gb' => 50,
    'api_requests_per_month' => 10000
  }
  plan.default_roles = [ 'Member' ]
  plan.status = 'active'
  plan.is_public = true
end

enterprise_plan = Plan.find_or_create_by!(name: 'Enterprise') do |plan|
  plan.description = 'For large organizations requiring maximum capabilities'
  plan.price_cents = 9999  # $99.99
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 30
  plan.features = {
    'dashboard_access' => true,
    'basic_analytics' => true,
    'email_support' => true,
    'api_access' => true,
    'advanced_analytics' => true,
    'priority_support' => true,
    'custom_integrations' => true,
    'dedicated_support' => true
  }
  plan.limits = {
    'users' => -1,  # unlimited
    'projects' => -1,  # unlimited
    'storage_gb' => 500,
    'api_requests_per_month' => 100000
  }
  plan.default_roles = [ 'Member' ]
  plan.status = 'active'
  plan.is_public = true
end

puts "Created #{Plan.count} plans:"
puts "- Administrator: $#{administrator_plan.price_cents / 100.0}/month (#{administrator_plan.trial_days} day trial) - Admin Only"
puts "- Starter: $#{starter_plan.price_cents / 100.0}/month (#{starter_plan.trial_days} day trial)"
puts "- Professional: $#{professional_plan.price_cents / 100.0}/month (#{professional_plan.trial_days} day trial)"
puts "- Enterprise: $#{enterprise_plan.price_cents / 100.0}/month (#{enterprise_plan.trial_days} day trial)"

puts "Seeding completed!"
