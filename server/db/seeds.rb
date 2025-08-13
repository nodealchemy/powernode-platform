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

# Assign basic permissions to Member (including analytics)
member_permissions = Permission.where(
  resource: [ 'accounts', 'users', 'subscriptions', 'billing', 'analytics' ],
  action: 'read'
)
member_role.permissions = member_permissions

# Validate roles were created successfully
unless owner_role&.persisted? && admin_role&.persisted? && member_role&.persisted?
  puts "ERROR: Failed to create required system roles. Exiting..."
  exit(1)
end

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
  plan.default_roles = [ 'Admin' ]  # Only Admin role - Owner is assigned automatically to account creators
  plan.status = 'active'
  plan.is_public = false  # Not publicly available, assigned by system admins only
end

# Update existing Administrator plan if it has invalid roles
if administrator_plan.default_roles.include?('Owner')
  puts "Updating Administrator plan default_roles to remove Owner role..."
  administrator_plan.update!(default_roles: ['Admin'])
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

# Validate that all plan default_roles reference existing roles
puts "\nValidating plan default roles..."
[administrator_plan, starter_plan, professional_plan, enterprise_plan].each do |plan|
  invalid_roles = plan.default_roles.reject { |role_name| Role.exists?(name: role_name) }
  if invalid_roles.any?
    puts "ERROR: Plan '#{plan.name}' references non-existent roles: #{invalid_roles.join(', ')}"
    exit(1)
  else
    puts "- #{plan.name}: #{plan.default_roles.join(', ')} ✓"
  end
end

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

# Create admin user - ONLY System Administrator gets admin role
admin_user = User.find_or_create_by!(email: 'admin@powernode.dev') do |user|
  user.account = admin_account
  user.first_name = 'System'
  user.last_name = 'Administrator'
  user.password = 'AdminStrong2024!@#$'
  user.password_confirmation = 'AdminStrong2024!@#$'
  user.status = 'active'
  user.role = 'admin'  # Only the System Administrator gets admin role
  user.email_verified = true
  user.email_verified_at = Time.current
  user.last_login_at = Time.current
end

# Ensure admin user has admin role (single role system)
admin_user.update!(role: 'admin') unless admin_user.role == 'admin'

puts ""
puts 'Created Admin Account and User:'
puts "- Account: #{admin_account.name}"
puts "- Subdomain: #{admin_account.subdomain}"
puts "- Subscription: #{admin_subscription.plan.name} plan"
puts "- Admin User: #{admin_user.email}"
puts '- Admin Password: AdminStrong2024!@#$'
puts "- Admin Role: #{admin_user.role}"
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
  },
  {
    account: { name: 'DevTeam Solutions', subdomain: 'devteam', status: 'active' },
    user: { first_name: 'Alex', last_name: 'Thompson', email: 'alex@devteam.co' },
    plan: professional_plan,
    created_at: 5.weeks.ago,
    additional_users: [
      { first_name: 'Sam', last_name: 'Miller', email: 'sam@devteam.co', role: 'member' }
    ]
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
  
  # Create primary user (owner)
  email = user_attrs[:email]
  user = User.find_or_create_by!(email: email) do |u|
    u.account = account
    u.first_name = user_attrs[:first_name]
    u.last_name = user_attrs[:last_name]
    u.password = 'CustomerPass2024!@#$'
    u.password_confirmation = 'CustomerPass2024!@#$'
    u.status = 'active'
    # Set role - first user becomes owner, others become member
    u.role = account.users.count == 0 ? 'owner' : 'member'
    u.email_verified = true
    u.email_verified_at = account_attrs[:created_at] + 1.day
    u.last_login_at = account_attrs[:created_at] + rand(1..30).days
    u.created_at = account_attrs[:created_at]
    u.updated_at = account_attrs[:created_at] + rand(1..10).days
  end
  
  puts "  Created: #{account.name} - #{user.full_name} (#{user.email}) - #{plan.name} (owner)"
  
  # Create additional users if specified
  if customer_data[:additional_users]
    customer_data[:additional_users].each do |additional_user_attrs|
      additional_email = additional_user_attrs[:email]
      additional_user = User.find_or_create_by!(email: additional_email) do |u|
        u.account = account
        u.first_name = additional_user_attrs[:first_name]
        u.last_name = additional_user_attrs[:last_name]
        u.password = 'CustomerPass2024!@#$'
        u.password_confirmation = 'CustomerPass2024!@#$'
        u.status = 'active'
        u.role = additional_user_attrs[:role] || 'member'
        u.email_verified = true
        u.email_verified_at = account_attrs[:created_at] + 2.days
        u.last_login_at = account_attrs[:created_at] + rand(1..25).days
        u.created_at = account_attrs[:created_at] + 1.day
        u.updated_at = account_attrs[:created_at] + rand(2..12).days
      end
      
      puts "    Added user: #{additional_user.full_name} (#{additional_user.email}) - #{additional_user.role}"
    end
  end
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

# Create sample webhook events
puts "\nCreating sample webhook events..."

WebhookEvent.find_or_create_by!(external_id: 'evt_test_stripe_001') do |webhook|
  webhook.provider = 'stripe'
  webhook.event_type = 'payment_intent.succeeded'
  webhook.account = Account.joins(:subscription).where.not(subscriptions: { plan: administrator_plan }).first
  webhook.payload = {
    id: 'evt_test_stripe_001',
    object: 'event',
    api_version: '2023-10-16',
    created: 1.week.ago.to_i,
    type: 'payment_intent.succeeded',
    data: {
      object: {
        id: 'pi_test_001',
        amount: 2999,
        currency: 'usd',
        status: 'succeeded'
      }
    }
  }.to_json
  webhook.status = 'processed'
  webhook.processed_at = 1.week.ago
  webhook.retry_count = 0
end

WebhookEvent.find_or_create_by!(external_id: 'evt_test_paypal_001') do |webhook|
  webhook.provider = 'paypal'
  webhook.event_type = 'PAYMENT.SALE.COMPLETED'
  webhook.account = Account.joins(:subscription).where.not(subscriptions: { plan: administrator_plan }).second
  webhook.payload = {
    id: 'WH-2WR32451HC0233532-67976317FL4543714',
    event_type: 'PAYMENT.SALE.COMPLETED',
    create_time: 1.week.ago.iso8601,
    resource_type: 'sale',
    resource: {
      id: '8RS20933LY1826041',
      amount: { total: '9.99', currency: 'USD' },
      state: 'completed'
    }
  }.to_json
  webhook.status = 'processed'
  webhook.processed_at = 1.week.ago
  webhook.retry_count = 0
end

# Create sample revenue snapshots
puts "\nCreating sample revenue snapshots..."

# Global revenue snapshots for last 6 months
6.times do |i|
  snapshot_date = (i + 1).months.ago.beginning_of_month
  
  # Calculate metrics based on existing data at that time
  mrr_amount = ((i + 1) * 50000) + rand(10000) # Growing MRR
  active_subs = 10 + (i * 2) # Growing subscription count
  
  RevenueSnapshot.find_or_create_by!(account: nil, snapshot_date: snapshot_date) do |snapshot|
    snapshot.mrr_cents = mrr_amount
    snapshot.arr_cents = mrr_amount * 12
    snapshot.active_subscriptions = active_subs
    snapshot.new_subscriptions = rand(1..3)
    snapshot.churned_subscriptions = rand(0..1)
    snapshot.add_metadata('growth_rate', rand(5.0..15.0).round(2))
    snapshot.add_metadata('customer_churn_rate', rand(2.0..8.0).round(2))
    snapshot.add_metadata('revenue_churn_rate', rand(1.0..5.0).round(2))
  end
end

# Account-specific revenue snapshots for top customers
Account.joins(:subscription)
       .joins(subscription: :plan)
       .where.not(subscriptions: { plan: administrator_plan })
       .limit(3).each do |account|
  subscription = account.subscription
  plan = subscription.plan
  
  3.times do |i|
    snapshot_date = (i + 1).months.ago.beginning_of_month
    next if snapshot_date < account.created_at
    
    RevenueSnapshot.find_or_create_by!(account: account, snapshot_date: snapshot_date) do |snapshot|
      snapshot.mrr_cents = plan.price_cents
      snapshot.arr_cents = plan.price_cents * 12
      snapshot.active_subscriptions = 1
      snapshot.new_subscriptions = i == 2 ? 1 : 0 # New in first snapshot
      snapshot.churned_subscriptions = 0
      snapshot.add_metadata('account_specific', true)
    end
  end
end

# Create sample pages
puts "\nCreating sample pages..."

pages_data = [
  {
    title: 'Welcome to Powernode',
    slug: 'welcome',
    content: "# Welcome to Powernode\n\nYour comprehensive subscription management and billing platform is ready to help you grow your business.\n\n## What is Powernode?\n\nPowernode is a powerful subscription management platform designed to automate your billing processes, handle payment processing, and provide deep insights into your subscription business.\n\n## Key Features\n\n### 📊 **Comprehensive Analytics**\n- Monthly and Annual Recurring Revenue (MRR/ARR) tracking\n- Customer churn analysis and cohort reporting\n- Revenue growth and customer lifetime value metrics\n- Real-time dashboard with business insights\n\n### 💳 **Payment Processing**\n- Integrated Stripe and PayPal payment gateways\n- Automated recurring billing and invoicing\n- Smart dunning management for failed payments\n- Multiple payment method support\n\n### 👥 **Account Management**\n- Multi-user accounts with role-based permissions\n- Account delegation and team collaboration\n- Invitation system for new team members\n- Flexible subscription plan management\n\n### 🔧 **Developer Tools**\n- RESTful API for seamless integrations\n- Webhook support for real-time notifications\n- Background job processing with Sidekiq\n- Comprehensive audit logging\n\n## Getting Started\n\n### For New Users\n1. **Sign Up**: Choose from our flexible subscription plans\n2. **Configure**: Set up your account preferences and payment methods\n3. **Integrate**: Use our API or web interface to manage subscriptions\n4. **Grow**: Monitor your metrics and optimize your subscription business\n\n### For Administrators\n- Access the **Administration** panel for system-wide management\n- Configure plans, manage users, and monitor platform health\n- Set up payment gateways and webhook endpoints\n- Review analytics across all customer accounts\n\n## Quick Links\n\n- 📈 [View Dashboard](/dashboard) - See your key metrics at a glance\n- ⚙️ [Account Settings](/account) - Manage your account preferences\n- 💰 [Subscription Plans](/plans) - Browse available plans\n- 📚 [API Documentation](/pages/api-docs) - Integrate with our platform\n- 🔒 [Privacy Policy](/pages/privacy-policy) - Learn about data protection\n- 📋 [Terms of Service](/pages/terms-of-service) - Review our service terms\n\n## Need Help?\n\nOur platform is designed to be intuitive, but we're here to help if you need assistance:\n\n- **System Status**: Monitor platform health in real-time\n- **Support**: Contact our team for technical assistance\n- **Documentation**: Comprehensive guides for all features\n\n---\n\n**Ready to get started?** [Sign up for an account](/signup) or [log in](/login) to access your dashboard.\n\nWelcome to the future of subscription management! 🚀",
    status: 'published',
    meta_description: 'Welcome to Powernode - your comprehensive subscription management and billing platform. Get started with automated billing, analytics, and payment processing.',
    meta_keywords: 'subscription management, billing platform, recurring revenue, payment processing, analytics'
  },
  {
    title: 'Privacy Policy',
    slug: 'privacy-policy',
    content: '# Privacy Policy\n\nThis privacy policy describes how we collect, use, and protect your personal information...\n\n## Data Collection\n\nWe collect information you provide directly to us, such as when you create an account...\n\n## Data Usage\n\nWe use the information we collect to provide, maintain, and improve our services...',
    status: 'published',
    meta_description: 'Learn about our privacy practices and how we protect your personal information.',
    meta_keywords: 'privacy policy, data protection, personal information'
  },
  {
    title: 'Terms of Service',
    slug: 'terms-of-service', 
    content: '# Terms of Service\n\nBy using our service, you agree to these terms...\n\n## Acceptance of Terms\n\nBy accessing and using this service, you accept and agree to be bound by the terms...\n\n## Service Description\n\nOur platform provides subscription management and billing services...',
    status: 'published',
    meta_description: 'Read our terms of service and understand your rights and responsibilities.',
    meta_keywords: 'terms of service, legal agreement, user agreement'
  },
  {
    title: 'API Documentation',
    slug: 'api-docs',
    content: '# API Documentation\n\nWelcome to our API documentation...\n\n## Authentication\n\nAll API requests require authentication using JWT tokens...\n\n## Endpoints\n\n### Accounts\n\n- `GET /api/v1/accounts` - List accounts\n- `POST /api/v1/accounts` - Create account',
    status: 'published',
    meta_description: 'Complete API documentation for developers integrating with our platform.',
    meta_keywords: 'API documentation, developers, integration, endpoints'
  },
  {
    title: 'Getting Started Guide',
    slug: 'getting-started',
    content: '# Getting Started with Powernode\n\nWelcome to Powernode! This guide will help you set up your account...\n\n## Step 1: Create Account\n\nStart by creating your account and choosing a plan...\n\n## Step 2: Configure Settings\n\nCustomize your account settings and preferences...',
    status: 'draft',
    meta_description: 'Learn how to get started with Powernode platform.',
    meta_keywords: 'getting started, tutorial, setup guide'
  }
]

pages_data.each do |page_data|
  Page.find_or_create_by!(slug: page_data[:slug]) do |page|
    page.title = page_data[:title]
    page.content = page_data[:content]
    page.status = page_data[:status]
    page.meta_description = page_data[:meta_description]
    page.meta_keywords = page_data[:meta_keywords]
    page.author = admin_user
    page.published_at = page_data[:status] == 'published' ? 1.month.ago : nil
  end
end

# Create sample payment methods for customers
puts "\nCreating sample payment methods..."

Account.joins(:subscription)
       .joins(subscription: :plan)
       .where.not(subscriptions: { plan: administrator_plan })
       .limit(5).each do |account|
  primary_user = account.users.first
  
  # Create a credit card payment method
  PaymentMethod.find_or_create_by!(account: account, user: primary_user, external_id: "pm_card_#{account.id}") do |pm|
    pm.provider = 'stripe'
    pm.payment_type = 'card'
    pm.last_four = ['4242', '1234', '5678', '9999'].sample
    pm.brand = ['visa', 'mastercard', 'amex'].sample
    pm.exp_month = rand(1..12)
    pm.exp_year = rand(2025..2028)
    pm.is_default = true
  end
  
  # Some accounts have PayPal as well
  if rand < 0.3
    PaymentMethod.find_or_create_by!(account: account, user: primary_user, external_id: "pp_account_#{account.id}") do |pm|
      pm.provider = 'paypal'
      pm.payment_type = 'paypal'
      pm.is_default = false
    end
  end
end

# Create sample account delegations
puts "\nCreating sample account delegations..."

# Create a few additional users that can be delegated to
delegated_users_data = [
  { first_name: 'Alex', last_name: 'Johnson', email: 'alex@example.com' },
  { first_name: 'Maria', last_name: 'Garcia', email: 'maria@consultant.com' },
  { first_name: 'Tom', last_name: 'Wilson', email: 'tom@contractor.net' }
]

delegated_users = []
delegated_users_data.each do |user_data|
  user = User.find_or_create_by!(email: user_data[:email]) do |u|
    u.account = admin_account # These users belong to admin account but can be delegated
    u.first_name = user_data[:first_name]
    u.last_name = user_data[:last_name]
    u.password = 'DelegatedUser2024!@#$'
    u.password_confirmation = 'DelegatedUser2024!@#$'
    u.status = 'active'
    u.role = 'admin' # Assign admin role since they belong to admin account
    u.email_verified = true
    u.email_verified_at = 1.month.ago
  end
  
  # Assign admin role to delegated users (they belong to admin account with Administrator plan)
  user.update!(role: 'admin') unless user.role == 'admin'
  
  delegated_users << user
end

# Create some delegations
enterprise_accounts = Account.joins(:subscription)
                            .joins(subscription: :plan)
                            .where(subscriptions: { plan: enterprise_plan })
                            .limit(2)

# Create delegations with different roles for testing (using single role strings)
delegation_configs = [
  { role: 'admin', expires_months: 6, notes: 'Full administrative access for consultant' },
  { role: 'member', expires_months: 3, notes: 'Limited access for temporary project work' },
  { role: 'admin', expires_months: 12, notes: 'Long-term administrative delegation' }
]

enterprise_accounts.each_with_index do |account, index|
  break if index >= delegated_users.count

  delegated_user = delegated_users[index]
  delegator = account.users.first
  config = delegation_configs[index] || delegation_configs.first
  
  AccountDelegation.find_or_create_by!(account: account, delegated_user: delegated_user, delegated_by: delegator) do |delegation|
    delegation.role = config[:role]
    delegation.status = 'active'
    delegation.expires_at = config[:expires_months].months.from_now
    delegation.notes = config[:notes]
  end
  
  puts "  Created delegation: #{account.name} -> #{delegated_user.email} (#{config[:role]})"
end

# Create sample gateway configurations (using fake values for demo)
puts "\nCreating sample gateway configurations..."

GatewayConfiguration.set_config('stripe', 'publishable_key', 'pk_test_demo_key_for_development')
GatewayConfiguration.set_config('stripe', 'secret_key', 'sk_test_demo_secret_for_development')
GatewayConfiguration.set_config('stripe', 'endpoint_secret', 'whsec_demo_endpoint_secret')
GatewayConfiguration.set_config('stripe', 'webhook_tolerance', '300')

GatewayConfiguration.set_config('paypal', 'client_id', 'demo_paypal_client_id')
GatewayConfiguration.set_config('paypal', 'client_secret', 'demo_paypal_client_secret')
GatewayConfiguration.set_config('paypal', 'webhook_id', 'demo_webhook_id')
GatewayConfiguration.set_config('paypal', 'mode', 'sandbox')

puts "\nSeeding completed!"
puts "\nSample Data Summary:"
puts "- Total Accounts: #{Account.count}"
puts "- Total Users: #{User.count}"
puts "- Total Subscriptions: #{Subscription.count}"
puts "- Total Invoices: #{Invoice.count}"
puts "- Total Payments: #{Payment.count}"
puts "- Total Webhook Events: #{WebhookEvent.count}"
puts "- Total Revenue Snapshots: #{RevenueSnapshot.count}"
puts "- Total Pages: #{Page.count}"
puts "- Total Payment Methods: #{PaymentMethod.count}"
puts "- Total Account Delegations: #{AccountDelegation.count}"
puts "- Total Gateway Configurations: #{GatewayConfiguration.count}"

# Final validation: Ensure all users have a role
puts "\nValidating all users have roles..."
users_without_roles = User.where(role: [nil, ''])
if users_without_roles.exists?
  puts "ERROR: Found #{users_without_roles.count} users without roles:"
  users_without_roles.each do |user|
    puts "  - #{user.email} (#{user.account.name})"
    # Assign member role as fallback
    user.update!(role: 'member')
    puts "    -> Assigned member role as fallback"
  end
else
  puts "✅ All #{User.count} users have a role assigned"
end
