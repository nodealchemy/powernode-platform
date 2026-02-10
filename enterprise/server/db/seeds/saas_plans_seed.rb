# frozen_string_literal: true

# Enterprise SaaS Plans - only loaded when enterprise engine is present
puts "💰 Seeding SaaS subscription plans..."

# Free plan
Plan.find_or_create_by!(name: 'Free') do |plan|
  plan.description = 'Perfect for individuals and small teams getting started'
  plan.price_cents = 0
  plan.currency = 'USD'
  plan.billing_interval = 'monthly'
  plan.trial_period_days = 0
  plan.features = {
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    'email_support' => false,
    'advanced_analytics' => false,
    'priority_support' => false,
    'api_access' => false,
    'custom_branding' => false,
    'data_export' => false,
    'team_collaboration' => false,
    'webhook_integrations' => false,
    'custom_fields' => false,
    'advanced_filters' => false,
    'custom_integrations' => false,
    'dedicated_support' => false,
    'white_label' => false,
    'sso_integration' => false,
    'advanced_security' => false,
    'audit_logs' => false,
    'sla_guarantees' => false
  }
  plan.limits = {
    'max_users' => 3,
    'max_api_keys' => 2,
    'max_webhooks' => 2,
    'max_workers' => 1,
    'max_repositories' => 5
  }
  plan.is_active = true
  plan.slug = 'free'
end

# Basic plan
Plan.find_or_create_by!(name: 'Basic') do |plan|
  plan.description = 'Essential features for growing teams and small businesses'
  plan.price_cents = 1500
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 14
  plan.features = {
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    'email_support' => true,
    'advanced_analytics' => false,
    'priority_support' => false,
    'api_access' => true,
    'custom_branding' => false,
    'data_export' => true,
    'team_collaboration' => true,
    'webhook_integrations' => false,
    'custom_fields' => false,
    'advanced_filters' => false,
    'custom_integrations' => false,
    'dedicated_support' => false,
    'white_label' => false,
    'sso_integration' => false,
    'advanced_security' => false,
    'audit_logs' => false,
    'sla_guarantees' => false
  }
  plan.limits = {
    'max_users' => 10,
    'max_api_keys' => 10,
    'max_webhooks' => 10,
    'max_workers' => 5,
    'max_repositories' => 15
  }
  plan.is_active = true
  plan.slug = 'basic'
  plan.promotional_discount_percent = 20.0
  plan.promotional_discount_start = Time.current
  plan.promotional_discount_end = 30.days.from_now
end

# Professional plan
Plan.find_or_create_by!(name: 'Professional') do |plan|
  plan.description = 'Advanced tools and integrations for scaling businesses'
  plan.price_cents = 4900
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 14
  plan.features = {
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    'email_support' => true,
    'advanced_analytics' => true,
    'priority_support' => true,
    'api_access' => true,
    'custom_branding' => true,
    'data_export' => true,
    'team_collaboration' => true,
    'webhook_integrations' => true,
    'custom_fields' => true,
    'advanced_filters' => true,
    'custom_integrations' => false,
    'dedicated_support' => false,
    'white_label' => false,
    'sso_integration' => false,
    'advanced_security' => false,
    'audit_logs' => true,
    'sla_guarantees' => false,
    'marketplace_publish_enabled' => true,
    'marketplace_publish_limit' => 5
  }
  plan.limits = {
    'max_users' => 50,
    'max_api_keys' => 25,
    'max_webhooks' => 25,
    'max_workers' => 15,
    'max_repositories' => 50
  }
  plan.is_active = true
  plan.slug = 'professional'
  plan.annual_discount_percent = 25.0
end

# Enterprise plan
Plan.find_or_create_by!(name: 'Enterprise') do |plan|
  plan.description = 'Complete solution with enterprise security and dedicated support'
  plan.price_cents = 15000
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 30
  plan.features = {
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    'email_support' => true,
    'advanced_analytics' => true,
    'priority_support' => true,
    'api_access' => true,
    'custom_branding' => true,
    'data_export' => true,
    'team_collaboration' => true,
    'webhook_integrations' => true,
    'custom_fields' => true,
    'advanced_filters' => true,
    'custom_integrations' => true,
    'dedicated_support' => true,
    'white_label' => true,
    'sso_integration' => true,
    'advanced_security' => true,
    'audit_logs' => true,
    'sla_guarantees' => true,
    'marketplace_publish_enabled' => true,
    'marketplace_publish_limit' => nil
  }
  plan.limits = {
    'max_users' => 9999,
    'max_api_keys' => 100,
    'max_webhooks' => 100,
    'max_workers' => 50,
    'max_repositories' => 9999
  }
  plan.is_active = true
  plan.slug = 'enterprise'
  plan.annual_discount_percent = 30.0
end

puts "✅ SaaS plans seeded: Free, Basic, Professional, Enterprise"
