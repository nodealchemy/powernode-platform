# frozen_string_literal: true

# Minimal production seed data
# This file contains only essential data needed for all environments

puts "🌱 Seeding Powernode platform..."

# Sync permissions and roles from configuration
puts "📝 Creating permissions and roles from configuration..."
Permission.sync_from_config!
puts "✅ Created #{Permission.count} permissions"

Role.sync_from_config!
puts "✅ Created #{Role.count} roles"

# Validate permission system integrity
puts "\n🔍 Validating permission system integrity..."
validation_issues = []

# Check for super_admin role
super_admin_role = Role.find_by(name: 'super_admin')
if super_admin_role.nil?
  validation_issues << "Critical: super_admin role not found!"
else
  # Verify super_admin has system.admin permission
  unless super_admin_role.permissions.exists?(name: 'system.admin')
    validation_issues << "Critical: super_admin role missing system.admin permission!"
  end
end

# Check for system.admin permission
system_admin_perm = Permission.find_by(name: 'system.admin')
if system_admin_perm.nil?
  validation_issues << "Critical: system.admin permission not found!"
end

# Check permission categories
permission_categories = Permission.pluck(:name).map { |name| name.split('.').first }.uniq
expected_categories = [ 'users', 'admin', 'billing', 'system', 'analytics', 'pages', 'storage' ]
missing_categories = expected_categories - permission_categories

if missing_categories.any?
  validation_issues << "Warning: Missing permission categories: #{missing_categories.join(', ')}"
end

# Report validation results
if validation_issues.empty?
  puts "✅ Permission system validation passed"
  puts "   Total Permissions: #{Permission.count}"
  puts "   Total Roles: #{Role.count}"
  puts "   Permission Categories: #{permission_categories.count} (#{permission_categories.join(', ')})"
else
  puts "⚠️  Permission system validation found #{validation_issues.count} issues:"
  validation_issues.each { |issue| puts "   - #{issue}" }
  if validation_issues.any? { |i| i.start_with?('Critical:') }
    puts "\n❌ Critical validation errors found. Please check permissions.rb configuration!"
  end
end

# Create default plans
administrator_plan = Plan.find_or_create_by!(name: 'Administrator') do |plan|
  plan.description = 'Special plan for system administrators'
  plan.price_cents = 0
  plan.currency = 'USD'
  plan.billing_interval = 'monthly'
  plan.trial_period_days = 0
  plan.features = {
    # Core Features (all included for admin)
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    # Advanced Features (all included for admin)
    'email_support' => true,
    'advanced_analytics' => true,
    'priority_support' => true,
    'api_access' => true,
    'custom_branding' => true,
    'data_export' => true,
    'team_collaboration' => true,
    'webhook_integrations' => true,
    # Enterprise Features (all included for admin)
    'custom_fields' => true,
    'advanced_filters' => true,
    'custom_integrations' => true,
    'dedicated_support' => true,
    'white_label' => true,
    'sso_integration' => true,
    'advanced_security' => true,
    'audit_logs' => true,
    'sla_guarantees' => true,
    # Marketplace Publishing (unlimited for admins)
    'marketplace_publish_enabled' => true,
    'marketplace_publish_limit' => nil
  }
  plan.limits = {
    'max_users' => 9999,
    'max_api_keys' => 100,
    'max_webhooks' => 100,
    'max_workers' => 100
  }
  plan.is_public = false # Hidden from public view
  plan.slug = 'administrator'
end

# Add Free plan
free_plan = Plan.find_or_create_by!(name: 'Free') do |plan|
  plan.description = 'Perfect for individuals and small teams getting started'
  plan.price_cents = 0
  plan.currency = 'USD'
  plan.billing_interval = 'monthly'
  plan.trial_period_days = 0
  plan.features = {
    # Core Features
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    # Advanced Features (limited for free)
    'email_support' => false,
    'advanced_analytics' => false,
    'priority_support' => false,
    'api_access' => false,
    'custom_branding' => false,
    'data_export' => false,
    'team_collaboration' => false,
    'webhook_integrations' => false,
    # Enterprise Features (none for free)
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
    'max_workers' => 1
  }
  plan.is_active = true
  plan.slug = 'free'
end

basic_plan = Plan.find_or_create_by!(name: 'Basic') do |plan|
  plan.description = 'Essential features for growing teams and small businesses'
  plan.price_cents = 1500
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 14
  plan.features = {
    # Core Features
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    # Advanced Features (some included)
    'email_support' => true,
    'advanced_analytics' => false,
    'priority_support' => false,
    'api_access' => true,
    'custom_branding' => false,
    'data_export' => true,
    'team_collaboration' => true,
    'webhook_integrations' => false,
    # Enterprise Features (none for basic)
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
    'max_workers' => 5
  }
  plan.is_active = true
  plan.slug = 'basic'
  # Add promotional discount
  plan.promotional_discount_percent = 20.0
  plan.promotional_discount_start = Time.current
  plan.promotional_discount_end = 30.days.from_now
end

professional_plan = Plan.find_or_create_by!(name: 'Professional') do |plan|
  plan.description = 'Advanced tools and integrations for scaling businesses'
  plan.price_cents = 4900
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 14
  plan.features = {
    # Core Features (all included)
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    # Advanced Features (most included)
    'email_support' => true,
    'advanced_analytics' => true,
    'priority_support' => true,
    'api_access' => true,
    'custom_branding' => true,
    'data_export' => true,
    'team_collaboration' => true,
    'webhook_integrations' => true,
    # Enterprise Features (some included)
    'custom_fields' => true,
    'advanced_filters' => true,
    'custom_integrations' => false,
    'dedicated_support' => false,
    'white_label' => false,
    'sso_integration' => false,
    'advanced_security' => false,
    'audit_logs' => true,
    'sla_guarantees' => false,
    # Marketplace Publishing
    'marketplace_publish_enabled' => true,
    'marketplace_publish_limit' => 5
  }
  plan.limits = {
    'max_users' => 50,
    'max_api_keys' => 25,
    'max_webhooks' => 25,
    'max_workers' => 15
  }
  plan.is_active = true
  plan.slug = 'professional'
  # Add annual discount
  plan.annual_discount_percent = 25.0
end

enterprise_plan = Plan.find_or_create_by!(name: 'Enterprise') do |plan|
  plan.description = 'Complete solution with enterprise security and dedicated support'
  plan.price_cents = 15000
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 30
  plan.features = {
    # Core Features (all included)
    'community_access' => true,
    'dashboard_access' => true,
    'mobile_responsive' => true,
    'email_notifications' => true,
    'basic_reporting' => true,
    'standard_support' => true,
    'basic_analytics' => true,
    # Advanced Features (all included)
    'email_support' => true,
    'advanced_analytics' => true,
    'priority_support' => true,
    'api_access' => true,
    'custom_branding' => true,
    'data_export' => true,
    'team_collaboration' => true,
    'webhook_integrations' => true,
    # Enterprise Features (all included)
    'custom_fields' => true,
    'advanced_filters' => true,
    'custom_integrations' => true,
    'dedicated_support' => true,
    'white_label' => true,
    'sso_integration' => true,
    'advanced_security' => true,
    'audit_logs' => true,
    'sla_guarantees' => true,
    # Marketplace Publishing (unlimited)
    'marketplace_publish_enabled' => true,
    'marketplace_publish_limit' => nil
  }
  plan.limits = {
    'max_users' => 9999,
    'max_api_keys' => 100,
    'max_webhooks' => 100,
    'max_workers' => 50
  }
  plan.is_active = true
  plan.slug = 'enterprise'
  # Add annual discount
  plan.annual_discount_percent = 30.0
end

puts "✅ Created #{Plan.count} plans"

# Create system worker (required for worker-backend communication)
puts "🔧 Creating system worker..."

begin
  # Check if WORKER_TOKEN is set in environment
  worker_token = ENV['WORKER_TOKEN']
  if worker_token.blank?
    puts "⚠️ WORKER_TOKEN not found in environment - generating new token"
    worker_token = "swt_#{SecureRandom.urlsafe_base64(32)}"
    puts "💡 Set this token in your environment: WORKER_TOKEN=#{worker_token}"
  end

  system_worker = Worker.find_by(name: 'System Worker')

  if system_worker
    puts "✅ System worker already exists"
  else
    system_worker = Worker.create_worker!(
      name: 'System Worker',
      description: 'System worker for background processing and API communication',
      account: nil,
      roles: [ 'system_worker' ],
      token: worker_token
    )
  end

  puts "✅ System worker created successfully"
  puts "   Token: #{system_worker.masked_token}"
  puts "   Roles: #{system_worker.role_names.join(', ')}"

rescue => e
  puts "❌ Failed to create system worker: #{e.message}"
  puts "   This may cause worker authentication issues"
end

# Only create admin account in development/test environments
if Rails.env.development? || Rails.env.test?
  puts "\n🏢 Creating development/test accounts and users..."

  # Load the unified test user seed which handles all user creation
  # and writes credentials to test-credentials.json
  load Rails.root.join('db', 'seeds', 'cypress_test_users.rb')
end

# 📄 Create public pages
puts "\n📄 Creating public pages..."

# Get admin user as author
admin_user = User.find_by(email: 'admin@powernode.org')

# Welcome page
Page.find_or_create_by!(slug: 'welcome') do |page|
  page.title = 'Welcome to Powernode'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Streamline your subscription business with automated billing, analytics, and customer lifecycle management.'
  page.meta_keywords = 'subscription management, billing automation, recurring revenue, SaaS platform'
  page.content = <<~MARKDOWN
    # Welcome to Powernode

    ## Streamline Your Subscription Business

    Powernode is a comprehensive subscription management platform designed to help businesses automate billing, track analytics, and manage customer lifecycles with ease.

    ### 🚀 Key Features

    - **Automated Billing**: Seamless subscription billing and invoicing
    - **Real-time Analytics**: Track revenue, churn, and customer metrics
    - **Customer Management**: Complete subscriber lifecycle management
    - **Multiple Payment Gateways**: Support for Stripe, PayPal, and more
    - **API-First Architecture**: Integrate with your existing tools
    - **Enterprise Security**: PCI compliance and data protection

    ### 💼 Perfect for Growing Businesses

    Whether you're a startup launching your first subscription product or an established company looking to optimize your recurring revenue, Powernode provides the tools you need to succeed.

    ### 🎯 Get Started Today

    Ready to transform your subscription business? [Sign up for free](/register) and start your journey with Powernode.

    ---

    *Questions? Visit our [help center](/help) or [contact our team](/contact).*
  MARKDOWN
end


# Terms of Service page
Page.find_or_create_by!(slug: 'terms') do |page|
  page.title = 'Terms of Service'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Terms of Service for Powernode subscription management platform.'
  page.meta_keywords = 'terms of service, legal, agreement, user agreement'
  page.content = <<~MARKDOWN
    # Terms of Service

    **Last updated: #{Date.current.strftime('%B %d, %Y')}**

    ## 1. Acceptance of Terms

    By accessing and using Powernode ("Service"), you accept and agree to be bound by the terms and provision of this agreement.

    ## 2. Use License

    Permission is granted to temporarily access Powernode for personal, non-commercial transitory viewing only. This is the grant of a license, not a transfer of title, and under this license you may not:

    - Modify or copy the materials
    - Use the materials for any commercial purpose or for any public display
    - Attempt to reverse engineer any software contained on the website
    - Remove any copyright or other proprietary notations from the materials

    ## 3. Subscription Services

    ### 3.1 Service Availability
    We strive to maintain 99.9% uptime but do not guarantee uninterrupted service availability.

    ### 3.2 Billing and Payment
    - Subscription fees are billed in advance on a monthly or annual basis
    - All payments are non-refundable except as required by law
    - We reserve the right to change pricing with 30 days notice

    ### 3.3 Account Termination
    We may terminate accounts that violate these terms or engage in fraudulent activity.

    ## 4. Privacy

    Your privacy is important to us. Please review our Privacy Policy, which also governs your use of the Service.

    ## 5. Data Security

    We implement industry-standard security measures to protect your data. However, no method of transmission over the Internet is 100% secure.

    ## 6. Limitation of Liability

    In no event shall Powernode be liable for any damages arising out of the use or inability to use the Service.

    ## 7. Governing Law

    These terms shall be governed by and construed in accordance with the laws of [Jurisdiction], without regard to its conflict of law provisions.

    ## 8. Changes to Terms

    We reserve the right to modify these terms at any time. Users will be notified of significant changes.

    ## Contact Information

    Questions about these Terms of Service should be sent to: legal@powernode.org
  MARKDOWN
end

# Privacy Policy page
Page.find_or_create_by!(slug: 'privacy') do |page|
  page.title = 'Privacy Policy'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Privacy Policy for Powernode - learn how we collect, use, and protect your personal information.'
  page.meta_keywords = 'privacy policy, data protection, GDPR, personal information, cookies'
  page.content = <<~MARKDOWN
    # Privacy Policy

    **Last updated: #{Date.current.strftime('%B %d, %Y')}**

    ## Introduction

    Powernode ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our subscription management platform.

    ## Information We Collect

    ### Personal Information
    - Name and contact information
    - Billing and payment information
    - Account credentials
    - Usage data and analytics

    ### Automatically Collected Information
    - IP addresses and device information
    - Browser type and operating system
    - Pages visited and time spent
    - Cookies and similar technologies

    ## How We Use Your Information

    We use your information to:
    - Provide and maintain our services
    - Process payments and billing
    - Send important account notifications
    - Improve our platform and user experience
    - Comply with legal obligations

    ## Information Sharing

    We do not sell your personal information. We may share information with:
    - Service providers and business partners
    - Legal authorities when required by law
    - In connection with business transfers or mergers

    ## Data Security

    We implement appropriate technical and organizational measures to protect your information against unauthorized access, alteration, disclosure, or destruction.

    ### Security Measures Include:
    - Encryption in transit and at rest
    - Regular security audits and updates
    - Access controls and authentication
    - PCI DSS compliance for payment data

    ## Your Rights

    Depending on your location, you may have the following rights:
    - Access your personal information
    - Correct inaccurate information
    - Delete your information
    - Data portability
    - Opt-out of marketing communications

    ## Cookies and Tracking

    We use cookies and similar technologies to enhance your experience. You can control cookie preferences through your browser settings.

    ## International Transfers

    Your information may be processed in countries other than your own. We ensure appropriate safeguards are in place for such transfers.

    ## Children's Privacy

    Our services are not directed to children under 13. We do not knowingly collect personal information from children under 13.

    ## Changes to Privacy Policy

    We may update this Privacy Policy from time to time. We will notify you of any significant changes.

    ## Contact Us

    Questions about this Privacy Policy should be directed to:
    - Email: privacy@powernode.org
    - Address: [Your Company Address]

    For EU residents: You may also contact our Data Protection Officer at dpo@powernode.org
  MARKDOWN
end

# Help/Support page
Page.find_or_create_by!(slug: 'help') do |page|
  page.title = 'Help & Support'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Get help with Powernode - find answers to common questions and learn how to use our subscription management platform.'
  page.meta_keywords = 'help, support, FAQ, documentation, guides, customer support'
  page.content = <<~MARKDOWN
    # Help & Support

    ## Get the Most Out of Powernode

    Welcome to our Help Center! Find answers to common questions and learn how to maximize your subscription business with Powernode.

    ## 🚀 Getting Started

    ### Quick Setup Guide
    1. **Create Your Account** - Sign up and verify your email
    2. **Set Up Billing** - Configure your payment gateway
    3. **Create Your First Plan** - Define your subscription offerings
    4. **Invite Team Members** - Collaborate with your team
    5. **Launch Your Service** - Start accepting subscribers

    ### Essential Features
    - **Dashboard Overview** - Monitor key metrics at a glance
    - **Subscription Management** - Create and manage subscription plans
    - **Customer Portal** - Self-service options for subscribers
    - **Analytics & Reporting** - Track performance and growth

    ## 📖 Frequently Asked Questions

    ### Account & Billing
    **Q: How do I change my subscription plan?**
    A: Visit your account settings and select "Change Plan" to upgrade or downgrade.

    **Q: When am I charged for my subscription?**
    A: Billing occurs on your subscription anniversary date each month or year.

    **Q: Can I cancel my subscription anytime?**
    A: Yes, you can cancel anytime from your account settings. No long-term contracts.

    ### Technical Support
    **Q: How do I integrate Powernode with my existing website?**
    A: Use our REST API or JavaScript SDK. Check our developer documentation for details.

    **Q: What payment gateways do you support?**
    A: We support Stripe, PayPal, and other major payment processors.

    **Q: Is my data secure?**
    A: Yes, we use enterprise-grade security including encryption, PCI compliance, and regular audits.

    ## 🛠️ Advanced Features

    ### API Integration
    - REST API for custom integrations
    - Webhooks for real-time notifications
    - SDKs for popular programming languages

    ### Analytics & Reporting
    - Revenue tracking and forecasting
    - Customer lifecycle analysis
    - Churn prediction and prevention
    - Custom report generation

    ### Team Collaboration
    - Role-based access control
    - Team member invitations
    - Audit logs and activity tracking

    ## 📞 Contact Support

    Can't find what you're looking for? Our support team is here to help!

    ### Support Channels
    - **Email Support**: support@powernode.org
    - **Live Chat**: Available 24/7 for paid plans
    - **Phone Support**: Available for Business and Enterprise plans
    - **Help Desk**: Submit a ticket through your dashboard

    ### Response Times
    - **Starter Plan**: 48 hours
    - **Professional Plan**: 24 hours
    - **Business Plan**: 12 hours
    - **Enterprise Plan**: 2 hours

    ## 📚 Additional Resources

    - [API Documentation](/docs/api)
    - [Video Tutorials](/tutorials)
    - [Developer Guides](/docs/guides)
    - [Status Page](/status)
    - [Community Forum](/community)

    ---

    **Still need help?** [Contact our support team](mailto:support@powernode.org) - we're here to ensure your success!
  MARKDOWN
end

# About page
Page.find_or_create_by!(slug: 'about') do |page|
  page.title = 'About Powernode'
  page.author = admin_user
  page.status = 'published'
  page.meta_description = 'Learn about Powernode - our mission to simplify subscription management for businesses of all sizes.'
  page.meta_keywords = 'about, company, mission, team, subscription management, SaaS'
  page.content = <<~MARKDOWN
    # About Powernode

    ## Simplifying Subscription Management for Everyone

    Founded with the mission to democratize subscription business management, Powernode provides powerful tools that help businesses of all sizes build, manage, and scale their recurring revenue streams.

    ## Our Mission

    **To empower businesses to focus on what they do best while we handle the complexity of subscription management.**

    We believe that every business should have access to enterprise-grade subscription tools, regardless of their size or technical expertise.

    ## Our Story

    Powernode was born from the frustration of managing subscriptions across multiple platforms, dealing with complex billing scenarios, and lacking actionable insights into customer behavior.#{' '}

    We set out to build a platform that would:
    - Simplify subscription billing and management
    - Provide clear, actionable analytics
    - Scale with businesses as they grow
    - Integrate seamlessly with existing tools

    ## What Sets Us Apart

    ### 🎯 Customer-Centric Design
    Every feature is built with the end-user in mind, ensuring intuitive experiences for both businesses and their customers.

    ### 🔧 Developer-Friendly
    Comprehensive APIs, webhooks, and SDKs make integration straightforward for technical teams.

    ### 📈 Growth-Oriented
    Our platform grows with your business, from first subscriber to IPO and beyond.

    ### 🛡️ Security-First
    Enterprise-grade security and compliance built into every aspect of our platform.

    ## Our Values

    **Transparency** - Clear pricing, open communication, and honest business practices.

    **Innovation** - Continuously improving our platform based on customer feedback and industry trends.

    **Reliability** - Building robust, scalable infrastructure that businesses can depend on.

    **Support** - Providing exceptional customer service and resources for success.

    ## The Team

    Our diverse team combines expertise in subscription business models, financial technology, and user experience design. We're passionate about helping businesses succeed in the subscription economy.

    ## Join Our Journey

    Whether you're launching your first subscription product or optimizing an established business, we're here to support your success.

    [Start your free trial today](/register) and discover how Powernode can transform your subscription business.

    ---

    **Questions about our company or platform?** [Contact us](/contact) - we'd love to hear from you!
  MARKDOWN
end

puts "✅ Created #{Page.count} public pages"

# Load Knowledge Base data
puts "\n📚 Loading Knowledge Base content..."
load Rails.root.join('db', 'seeds', 'knowledge_base_permissions.rb')
load Rails.root.join('db', 'seeds', 'knowledge_base_articles.rb')

# Load AI Providers and Workflows (only in development/test)
if Rails.env.development? || Rails.env.test?
  puts "\n🤖 Loading Comprehensive AI Providers (OpenAI, Grok, Ollama, Claude)..."
  load Rails.root.join('db', 'seeds', 'comprehensive_ai_providers_seed.rb')

  puts "\n🧠 Loading Claude-Powered Workflow Agents..."
  load Rails.root.join('db', 'seeds', 'claude_agents_seed.rb')

  puts "\n📊 Loading Monitoring and Analytics Agents..."
  load Rails.root.join('db', 'seeds', 'monitoring_analytics_agents_seed.rb')

  puts "\n🔌 Loading MCP Servers..."
  load Rails.root.join('db', 'seeds', 'mcp_servers_seeds.rb')

  puts "\n🚀 Loading AI Workflow Showcase Examples..."
  load Rails.root.join('db', 'seeds', 'ai_workflow_showcase_seeds.rb')

  puts "\n🗄️  Loading File Storage configurations..."
  load Rails.root.join('db', 'seeds', 'file_storage_seeds.rb')
end

puts "\n🎉 Seeding complete!"
puts "   Permissions: #{Permission.count}"
puts "   Roles: #{Role.count}"
puts "   Plans: #{Plan.count}"
puts "   Workers: #{Worker.count}"
puts "   Public Pages: #{Page.count}"
puts "   KB Categories: #{KnowledgeBaseCategory.count}"
puts "   KB Articles: #{KnowledgeBaseArticle.count}"

if Rails.env.development? || Rails.env.test?
  puts "   AI Providers: #{Ai::Provider.count}"
  puts "   AI Agents: #{Ai::Agent.count}"
  puts "   AI Workflows: #{Ai::Workflow.count}"
  puts "   AI Workflow Templates: #{Ai::WorkflowTemplate.count}"
  puts "   AI Workflow Runs: #{Ai::WorkflowRun.count}"
end

# 🔧 Create default site settings
puts "\n🔧 Creating default site settings..."

# Site information
SiteSetting.set('site_name', 'Powernode', description: 'Name of the site', setting_type: 'string', is_public: true)
SiteSetting.set('footer_description', 'Powerful subscription management platform designed to help businesses grow. Trusted by thousands of companies worldwide.', description: 'Footer description text', setting_type: 'text', is_public: true)

# Copyright information
SiteSetting.set('copyright_text', 'All rights reserved.', description: 'Copyright text displayed in footer', setting_type: 'string', is_public: true)
SiteSetting.set('copyright_year', Date.current.year.to_s, description: 'Copyright year', setting_type: 'string', is_public: true)

# Contact information
SiteSetting.set('contact_email', 'hello@powernode.org', description: 'Main contact email', setting_type: 'string', is_public: true)
SiteSetting.set('contact_phone', '+1 (555) 123-4567', description: 'Contact phone number', setting_type: 'string', is_public: true)
SiteSetting.set('company_address', '123 Innovation Drive, Tech City, TC 12345', description: 'Company address', setting_type: 'string', is_public: true)

# Social media links
SiteSetting.set('social_twitter', '', description: 'Twitter/X profile URL', setting_type: 'string', is_public: true)
SiteSetting.set('social_linkedin', '', description: 'LinkedIn profile URL', setting_type: 'string', is_public: true)
SiteSetting.set('social_facebook', '', description: 'Facebook page URL', setting_type: 'string', is_public: true)
SiteSetting.set('social_instagram', '', description: 'Instagram profile URL', setting_type: 'string', is_public: true)
SiteSetting.set('social_youtube', '', description: 'YouTube channel URL', setting_type: 'string', is_public: true)

# Admin-only settings
SiteSetting.set('maintenance_mode', 'false', description: 'Enable maintenance mode', setting_type: 'boolean', is_public: false)
SiteSetting.set('analytics_tracking_id', '', description: 'Google Analytics tracking ID', setting_type: 'string', is_public: false)
SiteSetting.set('seo_default_title', 'Powernode - Subscription Management Platform', description: 'Default SEO title', setting_type: 'string', is_public: false)
SiteSetting.set('seo_default_description', 'Streamline your subscription business with automated billing, analytics, and customer lifecycle management.', description: 'Default SEO description', setting_type: 'text', is_public: false)

# Footer caching
SiteSetting.set('footer_cache_enabled', 'true', description: 'Enable caching for footer data to improve performance', setting_type: 'boolean', is_public: false)

puts "✅ Created #{SiteSetting.count} site settings"

# Supply Chain Licenses
puts "\n📜 Seeding Supply Chain licenses..."
load Rails.root.join('db', 'seeds', 'supply_chain_licenses.rb')
puts "✅ Created #{SupplyChain::License.count} licenses"

if Rails.env.development? || Rails.env.test?
  puts "   Accounts: #{Account.count}"
  puts "   Users: #{User.count}"
  puts "   Subscriptions: #{Subscription.count}"
  puts "   Site Settings: #{SiteSetting.count}"
  puts "   Supply Chain Licenses: #{SupplyChain::License.count}"
end
