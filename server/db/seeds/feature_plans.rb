# frozen_string_literal: true

# Feature Plans with Role-Based Access Examples
# This seed file creates example plans that demonstrate role-based feature access

puts "🎯 Creating Feature Plans with Role-Based Access..."

# Ensure we have the required permissions in the system
required_permissions = [
  # User Management
  'user.view', 'user.edit_self', 'user.delete_self',

  # Team Management
  'team.view', 'team.invite', 'team.remove', 'team.assign_roles',

  # Billing & Subscriptions
  'billing.view', 'billing.update', 'billing.cancel',
  'invoice.view', 'invoice.download',

  # Content Management
  'page.create', 'page.view', 'page.edit', 'page.delete', 'page.publish',

  # Analytics & Reports
  'analytics.view', 'analytics.export',
  'report.view', 'report.generate', 'report.export',

  # API Access
  'api.read', 'api.write', 'api.manage_keys',

  # Webhooks
  'webhook.view', 'webhook.create', 'webhook.edit', 'webhook.delete',

  # Audit Logs
  'audit.view', 'audit.export'
]

# Create permissions if they don't exist
required_permissions.each do |perm_name|
  resource, action = perm_name.split('.')
  Permission.find_or_create_by(name: perm_name) do |perm|
    perm.resource = resource
    perm.action = action
    perm.description = "#{action.humanize} #{resource.humanize.downcase}"
  end
end

puts "✅ Ensured #{required_permissions.count} permissions exist"

# Helper method to create roles with permissions
def create_role_with_permissions(name, description, permission_names)
  role = Role.find_or_create_by(name: name) do |r|
    r.description = description
    r.display_name = name.split('.').map(&:capitalize).join(' ')
    r.role_type = 'user'
    r.is_system = false
  end

  # Add permissions to role
  permissions = Permission.where(name: permission_names)
  role.permissions = permissions
  role.save!

  puts "  ✅ Created role: #{name} with #{permissions.count} permissions"
  role
end

# 1. STARTER PLAN ROLES
puts "\n📦 Creating Starter Plan Roles..."

starter_member = create_role_with_permissions(
  'starter.member',
  'Basic account access with limited content creation',
  [ 'user.view', 'user.edit_self', 'page.view', 'page.create', 'page.edit', 'analytics.view', 'api.read' ]
)

starter_creator = create_role_with_permissions(
  'starter.creator',
  'Enhanced content management for starter plan',
  [ 'page.create', 'page.edit', 'page.delete', 'page.publish', 'webhook.view', 'analytics.view', 'analytics.export' ]
)

# 2. PROFESSIONAL PLAN ROLES
puts "\n💼 Creating Professional Plan Roles..."

pro_member = create_role_with_permissions(
  'pro.member',
  'Standard professional account member access',
  [ 'user.view', 'user.edit_self', 'page.view', 'analytics.view', 'api.read' ]
)

pro_collaborator = create_role_with_permissions(
  'pro.collaborator',
  'Team collaboration and enhanced content management',
  [ 'team.view', 'team.invite', 'page.create', 'page.edit', 'page.publish',
   'webhook.view', 'webhook.create', 'api.read', 'api.write' ]
)

pro_content_manager = create_role_with_permissions(
  'pro.content_manager',
  'Full content and webhook management for professional plan',
  [ 'page.create', 'page.edit', 'page.delete', 'page.publish',
   'webhook.view', 'webhook.create', 'webhook.edit',
   'analytics.view', 'analytics.export', 'report.view', 'report.generate' ]
)

pro_analyst = create_role_with_permissions(
  'pro.analyst',
  'Advanced analytics and reporting access',
  [ 'analytics.view', 'analytics.export', 'report.view', 'report.generate', 'report.export', 'audit.view' ]
)

# 3. BUSINESS PLAN ROLES
puts "\n🏢 Creating Business Plan Roles..."

biz_member = create_role_with_permissions(
  'business.member',
  'Standard business account access',
  [ 'user.view', 'user.edit_self', 'page.view', 'analytics.view', 'api.read' ]
)

biz_team_manager = create_role_with_permissions(
  'business.team_manager',
  'Comprehensive team management and content oversight',
  [ 'team.view', 'team.invite', 'team.remove', 'team.assign_roles', 'user.view',
   'page.create', 'page.edit', 'page.publish', 'webhook.view', 'webhook.create', 'webhook.edit',
   'analytics.view', 'analytics.export' ]
)

biz_billing_manager = create_role_with_permissions(
  'business.billing_manager',
  'Billing and subscription management',
  [ 'billing.view', 'billing.update', 'invoice.view', 'invoice.download', 'team.view', 'user.view' ]
)

biz_content_manager = create_role_with_permissions(
  'business.content_manager',
  'Complete content and webhook management',
  [ 'page.create', 'page.edit', 'page.delete', 'page.publish',
   'webhook.view', 'webhook.create', 'webhook.edit', 'webhook.delete',
   'analytics.view', 'analytics.export', 'report.view', 'report.generate', 'report.export', 'audit.view' ]
)

biz_api_developer = create_role_with_permissions(
  'business.api_developer',
  'Full API access and development tools',
  [ 'api.read', 'api.write', 'api.manage_keys',
   'webhook.view', 'webhook.create', 'webhook.edit', 'webhook.delete',
   'page.view', 'page.edit', 'analytics.view' ]
)

biz_support_agent = create_role_with_permissions(
  'business.support_agent',
  'Customer support and assistance access',
  [ 'user.view', 'team.view', 'page.view', 'analytics.view', 'report.view', 'audit.view' ]
)

# 4. ENTERPRISE PLAN ROLES
puts "\n🏛️ Creating Enterprise Plan Roles..."

ent_member = create_role_with_permissions(
  'enterprise.member',
  'Standard enterprise account access',
  [ 'user.view', 'user.edit_self', 'page.view', 'analytics.view', 'api.read' ]
)

ent_account_manager = create_role_with_permissions(
  'enterprise.account_manager',
  'Full account management capabilities',
  [ 'team.view', 'team.invite', 'team.remove', 'team.assign_roles', 'user.view',
   'billing.view', 'billing.update', 'page.create', 'page.edit', 'page.delete', 'page.publish',
   'webhook.view', 'webhook.create', 'webhook.edit', 'webhook.delete',
   'analytics.view', 'analytics.export', 'report.view', 'report.generate', 'report.export',
   'audit.view', 'audit.export', 'api.read', 'api.write', 'api.manage_keys' ]
)

ent_security_officer = create_role_with_permissions(
  'enterprise.security_officer',
  'Security monitoring and compliance oversight',
  [ 'user.view', 'team.view', 'billing.view', 'audit.view', 'audit.export',
   'analytics.view', 'report.view', 'report.generate', 'report.export' ]
)

# Create sample plans
puts "\n🎫 Creating Feature Plans..."

# Starter Plan
starter_plan = Plan.find_or_create_by(name: 'Starter') do |plan|
  plan.description = 'Perfect for small teams and individuals getting started'
  plan.price_cents = 2900  # $29.00
  plan.billing_cycle = 'monthly'
  plan.features = {
    'pages_limit' => 5,
    'api_calls_per_month' => 1000,
    'team_members_limit' => 3,
    'webhooks_limit' => 0,
    'support_level' => 'community'
  }
  plan.status = 'active'
  plan.metadata = {
    'available_roles' => [ starter_member.name, starter_creator.name ]
  }
  plan.default_roles = [ starter_member.name ]
end

puts "✅ Created Starter plan: $#{starter_plan.price_cents / 100.0}/month"

# Professional Plan
professional_plan = Plan.find_or_create_by(name: 'Professional') do |plan|
  plan.description = 'Ideal for growing businesses with team collaboration needs'
  plan.price_cents = 7900  # $79.00
  plan.billing_cycle = 'monthly'
  plan.features = {
    'pages_limit' => 50,
    'api_calls_per_month' => 25000,
    'team_members_limit' => 10,
    'webhooks_limit' => 5,
    'support_level' => 'priority'
  }
  plan.status = 'active'
  plan.metadata = {
    'available_roles' => [ pro_member.name, pro_collaborator.name, pro_content_manager.name, pro_analyst.name ]
  }
  plan.default_roles = [ pro_member.name ]
end

puts "✅ Created Professional plan: $#{professional_plan.price_cents / 100.0}/month"

# Business Plan
business_plan = Plan.find_or_create_by(name: 'Business') do |plan|
  plan.description = 'For established businesses with complex requirements'
  plan.price_cents = 19900  # $199.00
  plan.billing_cycle = 'monthly'
  plan.features = {
    'pages_limit' => 999999,
    'api_calls_per_month' => 100000,
    'team_members_limit' => 25,
    'webhooks_limit' => 25,
    'support_level' => 'dedicated'
  }
  plan.status = 'active'
  plan.metadata = {
    'available_roles' => [ biz_member.name, biz_team_manager.name, biz_billing_manager.name,
                         biz_content_manager.name, biz_api_developer.name, biz_support_agent.name ]
  }
  plan.default_roles = [ biz_member.name ]
end

puts "✅ Created Business plan: $#{business_plan.price_cents / 100.0}/month"

# Enterprise Plan
enterprise_plan = Plan.find_or_create_by(name: 'Enterprise') do |plan|
  plan.description = 'For large organizations with advanced security and compliance needs'
  plan.price_cents = 49900  # $499.00
  plan.billing_cycle = 'monthly'
  plan.features = {
    'pages_limit' => 999999,
    'api_calls_per_month' => 999999,
    'team_members_limit' => 999999,
    'webhooks_limit' => 999999,
    'audit_retention_days' => 365,
    'sso_enabled' => true,
    'support_level' => 'enterprise'
  }
  plan.status = 'active'
  plan.metadata = {
    'available_roles' => [ ent_member.name, ent_account_manager.name, ent_security_officer.name,
                         # Also includes all business plan roles
                         biz_team_manager.name, biz_billing_manager.name, biz_content_manager.name,
                         biz_api_developer.name, biz_support_agent.name ]
  }
  plan.default_roles = [ ent_member.name ]
end

puts "✅ Created Enterprise plan: $#{enterprise_plan.price_cents / 100.0}/month"

puts "✅ Created #{Plan.count} feature plans"
puts "✅ Created #{Role.where(is_system: false).count} feature roles"
puts "✅ Total permissions: #{Permission.count}"

puts "\n🎉 Feature Plans with Role-Based Access created successfully!"
puts "\nPlans created:"
Plan.all.each do |plan|
  available_roles_count = plan.metadata&.dig('available_roles')&.count || 0
  puts "  • #{plan.name}: $#{plan.price_cents / 100.0}/month (#{available_roles_count} roles available)"
end
