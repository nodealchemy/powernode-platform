# frozen_string_literal: true

# Cypress E2E Test Users
# This seed file creates test users with credentials matching Cypress test expectations
# Run with: rails db:seed:cypress_test_users
# or load after main seeds with: rails db:seed

puts "🧪 Creating Cypress E2E test users..."

# Get plans for subscriptions
professional_plan = Plan.find_by(slug: 'professional') || Plan.find_by(name: 'Professional')
basic_plan = Plan.find_by(slug: 'basic') || Plan.find_by(name: 'Basic')
administrator_plan = Plan.find_by(slug: 'administrator') || Plan.find_by(name: 'Administrator')

unless professional_plan
  puts "⚠️  Warning: No Professional plan found. Creating default plan for tests..."
  professional_plan = Plan.create!(
    name: 'Professional',
    description: 'Professional plan for testing',
    price_cents: 4900,
    currency: 'USD',
    billing_interval: 'monthly',
    trial_period_days: 14,
    is_active: true,
    slug: 'professional'
  )
end

# ============================================
# Demo User (for smoke-test.cy.ts)
# Email: demo@democompany.com
# Password: DemoSecure456!@#$%
# ============================================
demo_account = Account.find_or_create_by!(
  name: 'Demo Company',
  subdomain: 'democompany'
) do |account|
  account.status = 'active'
  account.settings = { timezone: 'America/New_York', locale: 'en' }
end

# Create subscription for demo account
Subscription.find_or_create_by!(account: demo_account) do |subscription|
  subscription.plan = professional_plan
  subscription.status = 'active'
  subscription.current_period_start = Time.current.beginning_of_month
  subscription.current_period_end = Time.current.end_of_month + 1.month
  subscription.stripe_subscription_id = "sub_cypress_demo_#{SecureRandom.hex(8)}"
end

demo_user = User.find_or_create_by!(email: 'demo@democompany.com') do |user|
  user.account = demo_account
  user.name = 'Demo User'
  user.password = 'DemoSecure456!@#$%'
  user.password_confirmation = 'DemoSecure456!@#$%'
  user.status = 'active'
  user.email_verified = true
  user.email_verified_at = Time.current
end

# Ensure demo user has manager role
manager_role = Role.find_by(name: 'manager')
if manager_role && !demo_user.roles.include?(manager_role)
  demo_user.roles << manager_role
end

puts "  ✅ Demo user: demo@democompany.com / DemoSecure456!@#\$%"

# ============================================
# Admin User (for billing-commands.ts, admin tests)
# Email: admin@example.com
# Password: Qx7#mK9@pL2$nZ6!
# ============================================
admin_test_account = Account.find_or_create_by!(
  name: 'Admin Test Company',
  subdomain: 'admintest'
) do |account|
  account.status = 'active'
  account.settings = { timezone: 'UTC', locale: 'en' }
end

# Create subscription for admin test account
Subscription.find_or_create_by!(account: admin_test_account) do |subscription|
  subscription.plan = administrator_plan || professional_plan
  subscription.status = 'active'
  subscription.current_period_start = Time.current
  subscription.current_period_end = 100.years.from_now
end

admin_test_user = User.find_or_create_by!(email: 'admin@example.com') do |user|
  user.account = admin_test_account
  user.name = 'Admin Test User'
  user.password = 'Qx7#mK9@pL2$nZ6!'
  user.password_confirmation = 'Qx7#mK9@pL2$nZ6!'
  user.status = 'active'
  user.email_verified = true
  user.email_verified_at = Time.current
end

# Ensure admin user has super_admin role with all permissions
super_admin_role = Role.find_by(name: 'super_admin')
if super_admin_role && !admin_test_user.roles.include?(super_admin_role)
  admin_test_user.roles.clear
  admin_test_user.roles << super_admin_role
end

puts "  ✅ Admin user: admin@example.com / Qx7#mK9@pL2\$nZ6!"

# ============================================
# Billing Manager User (for billing-commands.ts)
# Email: billing@example.com
# Password: Rw8$jN4#vX3@qM5!
# ============================================
billing_user = User.find_or_create_by!(email: 'billing@example.com') do |user|
  user.account = admin_test_account
  user.name = 'Billing Manager'
  user.password = 'Rw8$jN4#vX3@qM5!'
  user.password_confirmation = 'Rw8$jN4#vX3@qM5!'
  user.status = 'active'
  user.email_verified = true
  user.email_verified_at = Time.current
end

# Assign billing manager permissions
billing_role = Role.find_by(name: 'billing_manager') || Role.find_by(name: 'manager')
if billing_role && !billing_user.roles.include?(billing_role)
  billing_user.roles << billing_role
end

puts "  ✅ Billing user: billing@example.com / Rw8\$jN4#vX3@qM5!"

# ============================================
# Regular Member User (for member tests)
# Email: member@example.com
# Password: Ty9@kP6#wZ1$mQ8!
# ============================================
member_user = User.find_or_create_by!(email: 'member@example.com') do |user|
  user.account = demo_account
  user.name = 'Member User'
  user.password = 'Ty9@kP6#wZ1$mQ8!'
  user.password_confirmation = 'Ty9@kP6#wZ1$mQ8!'
  user.status = 'active'
  user.email_verified = true
  user.email_verified_at = Time.current
end

member_role = Role.find_by(name: 'member')
if member_role && !member_user.roles.include?(member_role)
  member_user.roles << member_role
end

puts "  ✅ Member user: member@example.com / Ty9@kP6#wZ1\$mQ8!"

# ============================================
# Summary
# ============================================
puts "\n🎯 Cypress Test Credentials Summary:"
puts "  ┌─────────────────────────────────────────────────────────────┐"
puts "  │ Demo Login (smoke-test.cy.ts)                               │"
puts "  │   Email:    demo@democompany.com                            │"
puts "  │   Password: DemoSecure456!@#\$%                              │"
puts "  ├─────────────────────────────────────────────────────────────┤"
puts "  │ Admin Login (admin tests, billing-commands.ts)              │"
puts "  │   Email:    admin@example.com                               │"
puts "  │   Password: Qx7#mK9@pL2\$nZ6!                                │"
puts "  ├─────────────────────────────────────────────────────────────┤"
puts "  │ Billing Manager Login (billing-commands.ts)                 │"
puts "  │   Email:    billing@example.com                             │"
puts "  │   Password: Rw8\$jN4#vX3@qM5!                                │"
puts "  ├─────────────────────────────────────────────────────────────┤"
puts "  │ Member Login (member tests)                                 │"
puts "  │   Email:    member@example.com                              │"
puts "  │   Password: Ty9@kP6#wZ1\$mQ8!                                │"
puts "  └─────────────────────────────────────────────────────────────┘"

puts "\n✅ Cypress test users created successfully!"
