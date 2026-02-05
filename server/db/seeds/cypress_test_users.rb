# frozen_string_literal: true

# Development/Test Users Seed
#
# Creates all development and test users with RANDOMLY GENERATED passwords.
# Passwords are saved to test-credentials.json (gitignored) for use by:
#   - Cypress E2E tests
#   - RSpec integration tests
#   - Jest tests
#   - Manual testing
#
# Run with: rails db:seed
# Or directly: rails runner 'load Rails.root.join("db/seeds/cypress_test_users.rb")'

require 'securerandom'
require 'json'
require 'fileutils'

puts "🧪 Creating development/test users with random passwords..."

# Generate a cryptographically strong random password
# Avoids patterns that trigger password strength validation failures
def generate_secure_password(length = 24)
  chars = [
    ('A'..'Z').to_a,
    ('a'..'z').to_a,
    ('0'..'9').to_a,
    %w[! @ # $ % ^ & * - _ + = ?]
  ]

  # Patterns to avoid (from PasswordStrengthService)
  forbidden_patterns = [
    /(.)\1{2,}/,           # Repeated characters (aaa, 111, etc.)
    /123|abc|qwe|asd/i,    # Sequential patterns
    /password|admin|user|login/i  # Common words
  ]

  loop do
    # Ensure at least one of each character type
    password = [
      chars[0].sample,  # uppercase
      chars[1].sample,  # lowercase
      chars[2].sample,  # digit
      chars[3].sample   # special
    ]

    # Fill the rest randomly
    all_chars = chars.flatten
    (length - 4).times { password << all_chars.sample }

    # Shuffle to randomize position of required chars
    result = password.shuffle.join

    # Check for forbidden patterns and regenerate if found
    next if forbidden_patterns.any? { |pattern| result.match?(pattern) }

    return result
  end
end

# Store credentials for writing to file
test_credentials = {
  generated_at: Time.current.iso8601,
  warning: "DO NOT COMMIT THIS FILE - Contains test passwords",
  users: {}
}

# Get plans for subscriptions
administrator_plan = Plan.find_by(slug: 'administrator') || Plan.find_by(name: 'Administrator')
professional_plan = Plan.find_by(slug: 'professional') || Plan.find_by(name: 'Professional')

unless administrator_plan
  puts "⚠️  Warning: No Administrator plan found. Creating default plan..."
  administrator_plan = Plan.create!(
    name: 'Administrator',
    description: 'Administrator plan for system admins',
    price_cents: 0,
    currency: 'USD',
    billing_interval: 'monthly',
    trial_period_days: 0,
    is_active: true,
    is_public: false,
    slug: 'administrator'
  )
end

unless professional_plan
  puts "⚠️  Warning: No Professional plan found. Creating default plan..."
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
# Admin Account & User (super_admin)
# ============================================
admin_password = generate_secure_password
admin_account = Account.find_or_create_by!(
  name: 'Powernode Admin',
  subdomain: 'admin'
) do |account|
  account.status = 'active'
  account.settings = { timezone: 'UTC', locale: 'en' }
end

# Create subscription for admin account
Subscription.find_or_create_by!(account: admin_account) do |subscription|
  subscription.plan = administrator_plan
  subscription.status = 'active'
  subscription.current_period_start = Time.current
  subscription.current_period_end = 100.years.from_now
end

admin_user = User.find_by(email: 'admin@powernode.org')
if admin_user
  # Preserve existing password - only update credentials file with current password
  admin_password = nil # Signal that we need to generate a new password for credentials file only if needed
  puts "  ⏭️  Admin user already exists - preserving existing password"
else
  admin_user = User.create!(
    account: admin_account,
    email: 'admin@powernode.org',
    name: 'System Admin',
    password: admin_password,
    password_confirmation: admin_password,
    status: 'active',
    email_verified: true,
    email_verified_at: Time.current
  )
end

# Ensure admin user has super_admin role
super_admin_role = Role.find_by(name: 'super_admin')
if super_admin_role && !admin_user.roles.include?(super_admin_role)
  admin_user.roles.clear
  admin_user.roles << super_admin_role
end

test_credentials[:users][:admin] = {
  email: 'admin@powernode.org',
  password: admin_password || '(unchanged - user already existed)',
  role: 'super_admin',
  description: 'System administrator with full access'
}

puts "  ✅ Admin user: admin@powernode.org"

# ============================================
# Demo Account
# ============================================
demo_account = Account.find_or_create_by!(
  name: 'Demo Company',
  subdomain: 'demo'
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
  subscription.stripe_subscription_id = "sub_demo_#{SecureRandom.hex(8)}"
end

# ============================================
# Demo User (manager role - primary test user)
# ============================================
demo_password = generate_secure_password
demo_user = User.find_by(email: 'demo@powernode.org')
if demo_user
  demo_password = nil
  puts "  ⏭️  Demo user already exists - preserving existing password"
else
  demo_user = User.create!(
    account: demo_account,
    email: 'demo@powernode.org',
    name: 'Demo User',
    password: demo_password,
    password_confirmation: demo_password,
    status: 'active',
    email_verified: true,
    email_verified_at: Time.current
  )
end

manager_role = Role.find_by(name: 'manager')
if manager_role && !demo_user.roles.include?(manager_role)
  demo_user.roles << manager_role
end

test_credentials[:users][:demo] = {
  email: 'demo@powernode.org',
  password: demo_password || '(unchanged - user already existed)',
  role: 'manager',
  description: 'Primary test user for smoke tests and E2E testing'
}

puts "  ✅ Demo user: demo@powernode.org"

# ============================================
# Manager User (separate manager account)
# ============================================
manager_password = generate_secure_password
manager_user = User.find_by(email: 'manager@powernode.org')
if manager_user
  manager_password = nil
  puts "  ⏭️  Manager user already exists - preserving existing password"
else
  manager_user = User.create!(
    account: demo_account,
    email: 'manager@powernode.org',
    name: 'Demo Manager',
    password: manager_password,
    password_confirmation: manager_password,
    status: 'active',
    email_verified: true,
    email_verified_at: Time.current
  )
end

if manager_role && !manager_user.roles.include?(manager_role)
  manager_user.roles << manager_role
end

test_credentials[:users][:manager] = {
  email: 'manager@powernode.org',
  password: manager_password || '(unchanged - user already existed)',
  role: 'manager',
  description: 'Manager user for team and permission tests'
}

puts "  ✅ Manager user: manager@powernode.org"

# ============================================
# Billing Manager User
# ============================================
billing_password = generate_secure_password
billing_user = User.find_by(email: 'billing@powernode.org')
if billing_user
  billing_password = nil
  puts "  ⏭️  Billing user already exists - preserving existing password"
else
  billing_user = User.create!(
    account: admin_account,
    email: 'billing@powernode.org',
    name: 'Billing Manager',
    password: billing_password,
    password_confirmation: billing_password,
    status: 'active',
    email_verified: true,
    email_verified_at: Time.current
  )
end

billing_role = Role.find_by(name: 'billing_manager') || Role.find_by(name: 'manager')
if billing_role && !billing_user.roles.include?(billing_role)
  billing_user.roles << billing_role
end

test_credentials[:users][:billing] = {
  email: 'billing@powernode.org',
  password: billing_password || '(unchanged - user already existed)',
  role: 'billing_manager',
  description: 'Billing manager for billing and subscription tests'
}

puts "  ✅ Billing user: billing@powernode.org"

# ============================================
# Regular Member User
# ============================================
member_password = generate_secure_password
member_user = User.find_by(email: 'member@powernode.org')
if member_user
  member_password = nil
  puts "  ⏭️  Member user already exists - preserving existing password"
else
  member_user = User.create!(
    account: demo_account,
    email: 'member@powernode.org',
    name: 'Member User',
    password: member_password,
    password_confirmation: member_password,
    status: 'active',
    email_verified: true,
    email_verified_at: Time.current
  )
end

member_role = Role.find_by(name: 'member')
if member_role && !member_user.roles.include?(member_role)
  member_user.roles << member_role
end

test_credentials[:users][:member] = {
  email: 'member@powernode.org',
  password: member_password || '(unchanged - user already existed)',
  role: 'member',
  description: 'Regular member for member-level permission tests'
}

puts "  ✅ Member user: member@powernode.org"

# ============================================
# Write credentials to files
# ============================================
# Primary location: Project root (easy to find)
project_root = Rails.root.join('..')
primary_credentials_path = project_root.join('test-credentials.json')

# Detailed credentials for server tests
server_credentials_path = Rails.root.join('tmp', 'test_credentials.json')

# Format for frontend/Cypress consumption (hash structure for readability)
# Only include credentials for newly created users (password is not nil)
# For existing users, read from existing credentials file if available
existing_credentials = {}
if File.exist?(primary_credentials_path)
  begin
    existing_credentials = JSON.parse(File.read(primary_credentials_path), symbolize_names: true)
  rescue JSON::ParserError
    existing_credentials = {}
  end
end

frontend_credentials = {
  _comment: "Auto-generated test credentials - DO NOT COMMIT",
  generated_at: Time.current.iso8601,
  demo: {
    email: test_credentials[:users][:demo][:email],
    password: demo_password || existing_credentials.dig(:demo, :password) || '(set manually - run db:seed:reset to regenerate)'
  },
  admin: {
    email: test_credentials[:users][:admin][:email],
    password: admin_password || existing_credentials.dig(:admin, :password) || '(set manually - run db:seed:reset to regenerate)'
  },
  manager: {
    email: test_credentials[:users][:manager][:email],
    password: manager_password || existing_credentials.dig(:manager, :password) || '(set manually - run db:seed:reset to regenerate)'
  },
  billing: {
    email: test_credentials[:users][:billing][:email],
    password: billing_password || existing_credentials.dig(:billing, :password) || '(set manually - run db:seed:reset to regenerate)'
  },
  member: {
    email: test_credentials[:users][:member][:email],
    password: member_password || existing_credentials.dig(:member, :password) || '(set manually - run db:seed:reset to regenerate)'
  }
}

# Write to project root (primary, easy to find)
File.write(primary_credentials_path, JSON.pretty_generate(frontend_credentials))
puts "\n📁 Test credentials written to: #{primary_credentials_path}"

# Write detailed credentials for server tests
File.write(server_credentials_path, JSON.pretty_generate(test_credentials))
puts "📁 Server test details: #{server_credentials_path}"

# ============================================
# Summary
# ============================================
puts "\n🎯 Development/Test Users Created:"
puts "  ┌─────────────────────────────────────────────────────────────┐"
puts "  │ ⚠️  PASSWORDS ARE RANDOMLY GENERATED ON EACH SEED           │"
puts "  │                                                             │"
puts "  │ Credentials saved to: test-credentials.json (project root) │"
puts "  ├─────────────────────────────────────────────────────────────┤"
test_credentials[:users].each do |key, user|
  puts "  │ #{key.to_s.capitalize.ljust(8)} │ #{user[:email].ljust(26)} │ #{user[:role].ljust(16)} │"
end
puts "  └─────────────────────────────────────────────────────────────┘"

puts "\n✅ #{Account.count} accounts and #{User.count} users created"
puts "⚠️  test-credentials.json is gitignored - regenerate after cloning with: rails db:seed"
