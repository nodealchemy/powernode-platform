# Minimal production seed data
# This file contains only essential data needed for all environments
# Additional test data is loaded separately in development/test environments

puts "🌱 Seeding Powernode platform..."

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

puts "✅ Permissions created"

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
  resource: ['accounts', 'users', 'subscriptions', 'billing', 'analytics'],
  action: 'read'
)
member_role.permissions = member_permissions

puts "✅ Created #{Role.count} roles"

# Create default plans
administrator_plan = Plan.find_or_create_by!(name: 'Administrator') do |plan|
  plan.description = 'Special plan for system administrators'
  plan.price_cents = 0
  plan.currency = 'USD'
  plan.billing_cycle = 'monthly'
  plan.trial_days = 0
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
    'system_administration' => true
  }
  plan.limits = {
    'users' => -1,
    'projects' => -1,
    'storage_gb' => -1,
    'api_requests_per_month' => -1
  }
  plan.default_roles = ['Admin']
  plan.status = 'active'
  plan.is_public = false
end

starter_plan = Plan.find_or_create_by!(name: 'Starter') do |plan|
  plan.description = 'Perfect for individuals and small teams'
  plan.price_cents = 999
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
  plan.default_roles = ['Member']
  plan.status = 'active'
  plan.is_public = true
end

professional_plan = Plan.find_or_create_by!(name: 'Professional') do |plan|
  plan.description = 'For growing teams with advanced needs'
  plan.price_cents = 2999
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
  plan.default_roles = ['Member']
  plan.status = 'active'
  plan.is_public = true
end

enterprise_plan = Plan.find_or_create_by!(name: 'Enterprise') do |plan|
  plan.description = 'For large organizations'
  plan.price_cents = 9999
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
    'users' => -1,
    'projects' => -1,
    'storage_gb' => 500,
    'api_requests_per_month' => 100000
  }
  plan.default_roles = ['Member']
  plan.status = 'active'
  plan.is_public = true
end

puts "✅ Created #{Plan.count} plans"

# Create Admin account and user
admin_account = Account.find_or_create_by!(name: 'Powernode Administration') do |account|
  account.subdomain = 'admin'
  account.status = 'active'
end

admin_subscription = Subscription.find_or_create_by!(account: admin_account) do |subscription|
  subscription.plan = administrator_plan
  subscription.status = 'active'
  subscription.current_period_start = Time.current
  subscription.current_period_end = 1.year.from_now
  subscription.trial_end = nil
end

admin_user = User.find_or_create_by!(email: 'admin@powernode.dev') do |user|
  user.account = admin_account
  user.first_name = 'System'
  user.last_name = 'Administrator'
  user.password = 'AdminStrong2024!@#$'
  user.password_confirmation = 'AdminStrong2024!@#$'
  user.status = 'active'
  user.role = 'admin'
  user.email_verified = true
  user.email_verified_at = Time.current
  user.last_login_at = Time.current
end

# Ensure admin role is applied (in case user already exists)
admin_user.update!(role: 'admin') unless admin_user.role == 'admin'

puts ""
puts "✅ Created Admin Account:"
puts "  - Email: admin@powernode.dev"
puts '  - Password: AdminStrong2024!@#$'
puts '  - Plan: Administrator (Free)'

# Create one demo customer account
demo_account = Account.find_or_create_by!(name: 'Demo Company') do |account|
  account.subdomain = 'demo'
  account.status = 'active'
  account.billing_email = 'billing@democompany.com'
  account.created_at = 30.days.ago
end

demo_subscription = Subscription.find_or_create_by!(account: demo_account) do |subscription|
  subscription.plan = professional_plan
  subscription.status = 'active'
  subscription.current_period_start = 30.days.ago
  subscription.current_period_end = 30.days.from_now
  subscription.trial_end = nil
end

demo_user = User.find_or_create_by!(email: 'demo@democompany.com') do |user|
  user.account = demo_account
  user.first_name = 'Demo'
  user.last_name = 'User'
  user.password = 'DemoSecure456!@#$%'
  user.password_confirmation = 'DemoSecure456!@#$%'
  user.status = 'active'
  user.role = 'owner'
  user.email_verified = true
  user.email_verified_at = 30.days.ago
  user.last_login_at = 1.day.ago
end

# Create a payment method for demo account
stripe_id = "pm_demo_#{SecureRandom.hex(8)}"
demo_payment_method = PaymentMethod.find_or_create_by!(
  account: demo_account,
  user: demo_user,
  provider: 'stripe',
  external_id: stripe_id
) do |pm|
  pm.payment_type = 'card'
  pm.brand = 'visa'
  pm.last_four = '4242'
  pm.exp_month = 12
  pm.exp_year = Date.current.year + 2
  pm.holder_name = "#{demo_user.first_name} #{demo_user.last_name}"
  pm.is_default = true
  pm.metadata = { demo: true }
end

puts ""
puts "✅ Created Demo Customer Account:"
puts "  - Email: demo@democompany.com"
puts '  - Password: DemoSecure456!@#$%'
puts '  - Plan: Professional ($29.99/month)'
puts "  - Payment: Visa ending in 4242"

# Create essential pages
puts "\n📄 Creating essential pages..."

essential_pages = [
  {
    title: 'Welcome to Powernode',
    slug: 'welcome',
    content: '# 🚀 **Powernode** - Subscription Superpowers for Modern Businesses

## **Transform Your Business with the Ultimate Subscription Platform**

### 💡 **One Platform. Infinite Possibilities.**

Stop juggling multiple tools. Powernode brings **everything** you need to launch, manage, and scale your subscription business into one powerful, intuitive platform.

---

## 🎯 **Why Industry Leaders Choose Powernode**

### **📈 350% Average Revenue Growth**
Our customers see explosive growth within their first year. Join thousands of businesses that have transformed their revenue models with Powernode.

### **⚡ Launch in Minutes, Not Months**
Pre-built components, instant payment processing, and automated workflows mean you can start accepting subscriptions today.

### **🛡️ Enterprise-Grade Security**
Bank-level encryption, PCI DSS compliance, and SOC 2 certification keep your business and customers protected.

---

## ✨ **Features That Set You Apart**

### **💳 Seamless Payment Processing**
- **Stripe & PayPal** integration out of the box
- Support for **25+ currencies** and **135+ countries**
- Smart retry logic reduces failed payments by **38%**
- Automated dunning recovers **up to 15%** of failed charges

### **📊 Real-Time Analytics Dashboard**
- Track **MRR, ARR, LTV, and Churn** at a glance
- Customer cohort analysis and retention insights
- Revenue forecasting with **95% accuracy**
- Export-ready reports for investors and stakeholders

### **🎨 Flexible Subscription Models**
- **Flat-rate, tiered, per-seat, and usage-based** pricing
- Free trials, freemium, and hybrid models
- Proration and mid-cycle plan changes
- Grandfather pricing and custom discounts

### **🤝 Customer Self-Service Portal**
- Branded customer experience
- One-click upgrades and downgrades
- Invoice history and payment method management
- Pause and resume subscriptions

### **🔧 Developer-First API**
- RESTful API with **99.99% uptime SLA**
- Webhooks for real-time events
- SDKs for popular languages
- Comprehensive API documentation

### **👥 Team Collaboration**
- Role-based access control (RBAC)
- Multi-account management
- Activity logs and audit trails
- Team performance metrics

---

## 📈 **By the Numbers**

### **The Powernode Impact**

- **$2.3B+** Total payment volume processed
- **12M+** Active subscriptions managed
- **99.99%** Platform uptime guarantee
- **4.8/5** Average customer satisfaction score
- **<100ms** Average API response time
- **45%** Reduction in operational costs

---

## 💬 **What Our Customers Say**

> "**Powernode transformed our business model.** We went from one-time sales to predictable recurring revenue in just 3 months. Revenue is up 400% year-over-year."
> 
> — **Sarah Chen**, CEO at TechStart

> "The analytics alone are worth it. **We discovered revenue opportunities we never knew existed.** Powernode paid for itself in the first week."
> 
> — **Michael Rodriguez**, Head of Growth at ScaleUp Inc

> "**Migration was seamless.** The team helped us move 50,000 subscribers without a single minute of downtime. Incredible."
> 
> — **Jennifer Park**, CTO at Enterprise Solutions

---

## 💎 **Choose Your Growth Path**

### **🌱 Starter** - *$9.99/month*
Perfect for launching your subscription business
- Up to 100 subscribers
- Core analytics dashboard
- Email support
- 2.9% + 30¢ per transaction

### **🚀 Professional** - *$29.99/month*
Scale with confidence
- Up to 2,500 subscribers
- Advanced analytics & cohorts
- Priority support
- API access
- 2.5% + 30¢ per transaction

### **🏢 Enterprise** - *$99.99/month*
Unlimited growth potential
- Unlimited subscribers
- Custom integrations
- Dedicated account manager
- White-label options
- Volume-based pricing

### **✨ All Plans Include:**
- ✅ Zero setup fees
- ✅ 14-day free trial
- ✅ No credit card required
- ✅ Cancel anytime
- ✅ Free migration assistance

---

## 🎬 **See Powernode in Action**

### **Join a Live Demo Every Tuesday & Thursday**
Watch how leading companies use Powernode to accelerate growth. See real dashboards, live integrations, and get your questions answered.

**[Reserve Your Spot →](/demo)**

---

## 🏆 **Trusted by Industry Leaders**

Companies of all sizes trust Powernode to power their subscription business:

**TechCrunch** • **Forbes** • **Gartner** • **Y Combinator** • **500 Startups**

"*Best Subscription Platform 2024*" - SaaS Awards

"*Top 10 Fintech Innovation*" - Finance Weekly

"*Customer Choice Award*" - G2 Crowd

---

## 🚀 **Ready to Transform Your Business?**

### **Join 10,000+ companies already growing with Powernode**

Every second counts. While you read this, businesses using Powernode are:
- Processing **$2,847** in recurring revenue
- Onboarding **14 new subscribers**
- Saving **3.2 hours** of manual work

### **🎯 Start Your Success Story Today**

**[Start Free Trial](/register)** • **[View Plans](/plans)** • **[Schedule Demo](/demo)**

---

## 💡 **Still Have Questions?**

### **📚 Resources**
- [Getting Started Guide](/getting-started)
- [API Documentation](/api-docs)
- [Video Tutorials](/tutorials)
- [Success Stories](/case-studies)

### **🤝 We\'re Here to Help**
- 24/7 Live Chat Support
- Expert onboarding team
- Dedicated success managers
- Active community forum

### **📧 Contact Sales**
Enterprise needs? Custom requirements? Let\'s talk.

**[Contact Our Team](/contact)** • **sales@powernode.dev** • **1-800-POWER-UP**

---

## 🌟 **The Future of Subscriptions Starts Here**

Don\'t let another day pass with unpredictable revenue. Join the subscription revolution and build the recurring revenue business you\'ve always dreamed of.

**It\'s time to power up with Powernode.**

**[🚀 Start Your Free Trial Now](/register)**

*No credit card required • Setup in 5 minutes • Cancel anytime*

---

*© 2025 Powernode. Empowering subscription businesses worldwide.*',
    status: 'published'
  },
  {
    title: 'Terms of Service',
    slug: 'terms',
    content: '# Terms of Service

Last updated: ' + Date.current.strftime('%B %d, %Y') + '

These Terms of Service govern your use of the Powernode platform.

## 1. Acceptance of Terms

By accessing or using Powernode, you agree to be bound by these Terms.

## 2. Use of Service

You may use Powernode only for lawful purposes and in accordance with these Terms.

## 3. Account Registration

You must provide accurate and complete information when creating an account.

## 4. Subscription and Billing

Subscription fees are billed in advance on a monthly or annual basis.

## 5. Privacy

Your use of Powernode is also governed by our Privacy Policy.',
    status: 'published'
  },
  {
    title: 'Privacy Policy',
    slug: 'privacy',
    content: '# Privacy Policy

Last updated: ' + Date.current.strftime('%B %d, %Y') + '

Powernode respects your privacy and is committed to protecting your personal data.

## Information We Collect

We collect information you provide directly to us, such as when you create an account.

## How We Use Your Information

We use the information to provide, maintain, and improve our services.

## Data Security

We implement appropriate security measures to protect your personal information.

## Contact Us

If you have questions about this Privacy Policy, please contact us.',
    status: 'published'
  }
]

essential_pages.each do |page_data|
  Page.find_or_create_by!(slug: page_data[:slug]) do |page|
    page.title = page_data[:title]
    page.content = page_data[:content]
    page.status = page_data[:status]
    page.author_id = admin_user.id
    page.published_at = Time.current
  end
end

puts "✅ Created #{essential_pages.count} essential pages"

# Create System Worker (Global - used by Sidekiq worker component)
puts "\n🤖 Creating global system worker..."

system_worker = Worker.find_or_create_by!(
  role: 'system'
) do |worker|
  worker.account = admin_account
  worker.name = 'Powernode System Worker'
  worker.description = 'Global system worker for application background job processing and system tasks'
  worker.permissions = 'super_admin'
  worker.status = 'active'
  # Token will be automatically generated by the before_create callback
end

puts "✅ Created System Worker:"
puts "  - Name: #{system_worker.name}"
puts "  - Role: #{system_worker.role}"
puts "  - Permissions: #{system_worker.permissions}"
puts "  - Token: #{system_worker.masked_token}"
puts "  - Account: #{system_worker.account.name}"

# Load comprehensive test data in development and test environments
if Rails.env.development? || Rails.env.test?
  test_data_file = Rails.root.join('db', 'seeds', 'test_data.rb')
  if File.exist?(test_data_file)
    puts "\n📦 Loading test data for #{Rails.env} environment..."
    load test_data_file
  else
    puts "\n⚠️  Test data file not found at db/seeds/test_data.rb"
    puts "  Run 'rails db:seed:test_data' to generate comprehensive test data"
  end
end

puts "\n✨ Seeding completed successfully!"
puts ""
puts "Summary:"
puts "  - Permissions: #{Permission.count}"
puts "  - Roles: #{Role.count}"
puts "  - Plans: #{Plan.count}"
puts "  - Accounts: #{Account.count}"
puts "  - Users: #{User.count}"
puts "  - Subscriptions: #{Subscription.count}"
puts "  - Workers: #{Worker.count}"