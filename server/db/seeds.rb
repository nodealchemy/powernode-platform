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

# Create Admin account and user with Administrator plan
admin_account = Account.find_or_create_by!(name: 'Powernode Administration') do |account|
  account.subdomain = 'admin'
  account.status = 'active'
end

# Create subscription for admin account with Administrator plan
admin_subscription = Subscription.find_or_create_by!(account: admin_account) do |subscription|
  subscription.plan = administrator_plan
  subscription.status = 'active'
  subscription.current_period_start = Time.current
  subscription.current_period_end = 1.year.from_now
  subscription.trial_end = nil
end

# Create admin user
admin_user = User.find_or_create_by!(email: 'admin@powernode.dev') do |user|
  user.account = admin_account
  user.first_name = 'System'
  user.last_name = 'Administrator'
  user.password = 'AdminStrong2024!@#$'
  user.password_confirmation = 'AdminStrong2024!@#$'
  user.status = 'active'
  user.email_verified = true
  user.email_verified_at = Time.current
  user.last_login_at = Time.current
end

# Assign Owner role to admin user
admin_user.assign_role(owner_role) unless admin_user.roles.include?(owner_role)

puts ""
puts 'Created Admin Account and User:'
puts "- Account: #{admin_account.name}"
puts "- Subdomain: #{admin_account.subdomain}"
puts "- Subscription: #{admin_subscription.plan.name} plan"
puts "- Admin User: #{admin_user.email}"
puts '- Admin Password: AdminStrong2024!@#$'
puts '- Admin Role: Owner'
puts '- Status: Active'

# Create admin service for system administration
admin_service = Service.find_or_create_by!(name: 'Admin Service') do |service|
  service.description = 'Administrative service with super admin privileges for system management'
  service.permissions = 'super_admin'
  service.status = 'active'
  service.account = admin_account
  service.token = Service.generate_secure_token
end

puts ""
puts 'Created Admin Service:'
puts "- Name: #{admin_service.name}"
puts "- Permissions: #{admin_service.permissions}"
puts "- Status: #{admin_service.status}"
puts "- Account: #{admin_service.account.name}"
puts "- Token: #{admin_service.masked_token}"
puts "- Full Token: #{admin_service.token}"

# Create sample customer accounts for demonstration
puts "\nCreating sample customer accounts..."

sample_customers = [
  {
    account: { name: 'Acme Corporation', subdomain: 'acme', status: 'active' },
    user: { first_name: 'John', last_name: 'Smith', email: 'john@acme.com' },
    plan: professional_plan,
    created_at: 3.months.ago
  },
  {
    account: { name: 'TechStart Inc', subdomain: 'techstart', status: 'active' },
    user: { first_name: 'Sarah', last_name: 'Johnson', email: 'sarah@techstart.io' },
    plan: starter_plan,
    created_at: 2.months.ago
  },
  {
    account: { name: 'Enterprise Solutions LLC', subdomain: 'enterprise-sol', status: 'active' },
    user: { first_name: 'Michael', last_name: 'Chen', email: 'michael@enterprisesol.com' },
    plan: enterprise_plan,
    created_at: 4.months.ago
  },
  {
    account: { name: 'StartupHub', subdomain: 'startuphub', status: 'active' },
    user: { first_name: 'Emily', last_name: 'Rodriguez', email: 'emily@startuphub.co' },
    plan: professional_plan,
    created_at: 1.month.ago
  },
  {
    account: { name: 'Digital Innovations', subdomain: 'digital-inn', status: 'active' },
    user: { first_name: 'David', last_name: 'Wilson', email: 'david@digitalinn.net' },
    plan: starter_plan,
    created_at: 6.weeks.ago
  },
  {
    account: { name: 'Global Tech Partners', subdomain: 'globaltech', status: 'active' },
    user: { first_name: 'Lisa', last_name: 'Anderson', email: 'lisa@globaltech.com' },
    plan: enterprise_plan,
    created_at: 5.months.ago
  },
  {
    account: { name: 'InnovateLab', subdomain: 'innovatelab', status: 'suspended' },
    user: { first_name: 'Robert', last_name: 'Taylor', email: 'robert@innovatelab.org' },
    plan: professional_plan,
    created_at: 2.months.ago
  },
  {
    account: { name: 'CloudFirst Systems', subdomain: 'cloudfirst', status: 'active' },
    user: { first_name: 'Jennifer', last_name: 'Brown', email: 'jennifer@cloudfirst.io' },
    plan: starter_plan,
    created_at: 3.weeks.ago
  }
]

sample_customers.each_with_index do |customer_data, index|
  account_attrs = customer_data[:account].merge(created_at: customer_data[:created_at])
  user_attrs = customer_data[:user]
  plan = customer_data[:plan]
  
  # Create account
  account = Account.find_or_create_by!(subdomain: account_attrs[:subdomain]) do |acc|
    acc.name = account_attrs[:name]
    acc.status = account_attrs[:status]
    acc.created_at = account_attrs[:created_at]
    acc.updated_at = account_attrs[:created_at]
  end
  
  # Create subscription
  subscription = Subscription.find_or_create_by!(account: account) do |sub|
    sub.plan = plan
    sub.status = account_attrs[:status] == 'suspended' ? 'canceled' : 'active'
    sub.current_period_start = account_attrs[:created_at]
    sub.current_period_end = account_attrs[:created_at] + 1.month
    sub.trial_end = account_attrs[:created_at] + plan.trial_days.days if plan.trial_days > 0
    sub.created_at = account_attrs[:created_at]
    sub.updated_at = account_attrs[:created_at]
  end
  
  # Create primary user
  email = user_attrs[:email]
  user = User.find_or_create_by!(email: email) do |u|
    u.account = account
    u.first_name = user_attrs[:first_name]
    u.last_name = user_attrs[:last_name]
    u.password = 'CustomerPass2024!@#$'
    u.password_confirmation = 'CustomerPass2024!@#$'
    u.status = 'active'
    u.email_verified = true
    u.email_verified_at = account_attrs[:created_at] + 1.day
    u.last_login_at = account_attrs[:created_at] + rand(1..30).days
    u.created_at = account_attrs[:created_at]
    u.updated_at = account_attrs[:created_at] + rand(1..10).days
  end
  
  # Assign default role based on plan
  default_role_names = plan.default_roles || ['Member']
  default_role_names.each do |role_name|
    role = Role.find_by(name: role_name)
    user.assign_role(role) if role && !user.roles.include?(role)
  end
  
  # Make first user the owner
  if account.users.owners.empty?
    user.assign_role(owner_role) unless user.roles.include?(owner_role)
  end
  
  puts "  Created: #{account.name} - #{user.full_name} (#{user.email}) - #{plan.name}"
end

puts "\nCreated #{sample_customers.count} sample customer accounts"

# Create some sample invoices and payments for demonstration
puts "\nCreating sample billing data..."

Account.joins(:subscription)
       .joins(subscription: :plan)
       .where.not(subscriptions: { plan: administrator_plan })
       .where('plans.price_cents > 0').each do |account|
  subscription = account.subscription
  plan = subscription.plan
  
  # Create 2-3 historical invoices
  (2..3).to_a.sample.times do |i|
    invoice_date = account.created_at + i.months
    next if invoice_date > Time.current
    
    invoice = Invoice.find_or_create_by!(
      subscription: subscription,
      invoice_number: "INV-#{account.id.to_s.last(4)}-#{invoice_date.strftime('%Y%m')}-#{i + 1}"
    ) do |inv|
      inv.due_date = invoice_date + 7.days
      inv.status = ['draft', 'open', 'paid'].sample
      inv.subtotal_cents = plan.price_cents
      inv.tax_rate = 0.08
      inv.tax_cents = (plan.price_cents * inv.tax_rate).round
      inv.total_cents = inv.subtotal_cents + inv.tax_cents
      inv.currency = plan.currency
      inv.created_at = invoice_date
      inv.updated_at = invoice_date
    end
    
    # Create line item
    InvoiceLineItem.find_or_create_by!(
      invoice: invoice,
      description: "#{plan.name} Plan Subscription"
    ) do |item|
      item.quantity = 1
      item.unit_price_cents = plan.price_cents
      item.total_cents = plan.price_cents
      item.period_start = invoice_date
      item.period_end = invoice_date + 1.month
    end
    
    # Create payment if invoice is paid and has positive amount
    if invoice.status == 'paid' && invoice.total_cents > 0
      Payment.find_or_create_by!(
        invoice: invoice
      ) do |payment|
        payment.amount_cents = invoice.total_cents
        payment.currency = invoice.currency
        payment.status = 'succeeded'
        payment.payment_method = 'stripe_card'
        payment.metadata = {
          'gateway_transaction_id' => "ch_#{SecureRandom.hex(12)}",
          'payment_method' => 'card',
          'last_four' => '4242'
        }
        payment.processed_at = invoice_date + rand(1..5).days
        payment.created_at = payment.processed_at
        payment.updated_at = payment.processed_at
      end
    end
  end
end

invoice_count = Invoice.count
payment_count = Payment.count
puts "  Created #{invoice_count} invoices and #{payment_count} payments"

puts "\nSeeding completed!"
puts "\nSample Data Summary:"
puts "- Total Accounts: #{Account.count}"
puts "- Total Users: #{User.count}"
puts "- Total Subscriptions: #{Subscription.count}"
puts "- Total Invoices: #{Invoice.count}"
puts "- Total Payments: #{Payment.count}"
