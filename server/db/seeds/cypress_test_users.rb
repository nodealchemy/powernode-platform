# frozen_string_literal: true

# Development/Test Users Seed
#
# Ensures the standard development/test users exist
# (demo/admin/manager/billing/member @powernode.org). Each is created with a
# RANDOM, DISCARDED password — no credentials are ever written to disk.
#
# How test suites authenticate as these users (no credentials file):
#   - Cypress / Playwright: provision a per-run password via the REAL reset
#     endpoint at setup time (scripts/e2e/provision-test-logins.cjs).
#   - RSpec: factories + JWT auth helpers (spec/support/auth_helpers.rb).
#
# Run with: POWERNODE_SEED_DEMO=true rails db:seed
# Or directly: rails runner 'load Rails.root.join("db/seeds/cypress_test_users.rb")'

puts "🧪 Ensuring development/test users (random per-create passwords, never exported)..."

# A random password satisfying PasswordStrengthService (>= 12 chars; upper,
# lower, digit, special; no repeated/sequential/common-word patterns). Used only
# to satisfy has_secure_password at create time, then discarded — real passwords
# are set per test run via the reset endpoint.
def generate_secure_password(length = 24)
  chars = [ ('A'..'Z').to_a, ('a'..'z').to_a, ('0'..'9').to_a, %w[! @ # $ % ^ & * - _ + = ?] ]
  forbidden = [ /(.)\1{2,}/, /123|abc|qwe|asd/i, /password|admin|user|login/i ]
  loop do
    pw = [ chars[0].sample, chars[1].sample, chars[2].sample, chars[3].sample ]
    all = chars.flatten
    (length - 4).times { pw << all.sample }
    result = pw.shuffle.join
    next if forbidden.any? { |re| result.match?(re) }

    return result
  end
end

def ensure_test_user!(email:, name:, account:)
  User.find_by(email: email) || begin
    pw = generate_secure_password
    User.create!(
      account: account, email: email, name: name,
      password: pw, password_confirmation: pw,
      status: 'active', email_verified: true, email_verified_at: Time.current
    )
  end
end

admin_account = Account.find_or_create_by!(name: 'Powernode Admin', subdomain: 'admin') do |a|
  a.status = 'active'
  a.settings = { timezone: 'UTC', locale: 'en' }
end
demo_account = Account.find_or_create_by!(name: 'Demo Company', subdomain: 'demo') do |a|
  a.status = 'active'
  a.settings = { timezone: 'America/New_York', locale: 'en' }
end

super_admin_role = Role.find_by(name: 'super_admin')
manager_role     = Role.find_by(name: 'manager')
billing_role     = Role.find_by(name: 'billing_manager') || manager_role
member_role      = Role.find_by(name: 'member')

# Admin — super_admin only (mirrors prior clear-then-set behavior).
admin_user = ensure_test_user!(email: 'admin@powernode.org', name: 'System Admin', account: admin_account)
if super_admin_role && !admin_user.roles.include?(super_admin_role)
  admin_user.roles.clear
  admin_user.roles << super_admin_role
end
puts "  ✅ admin@powernode.org"

{
  'demo@powernode.org'    => [ 'Demo User',       demo_account,  manager_role ],
  'manager@powernode.org' => [ 'Demo Manager',    demo_account,  manager_role ],
  'billing@powernode.org' => [ 'Billing Manager', admin_account, billing_role ],
  'member@powernode.org'  => [ 'Member User',     demo_account,  member_role ]
}.each do |email, (name, account, role)|
  user = ensure_test_user!(email: email, name: name, account: account)
  user.roles << role if role && !user.roles.include?(role)
  puts "  ✅ #{email}"
end

puts "\n✅ #{Account.count} accounts and #{User.count} users present"
puts "🔐 Passwords are provisioned PER TEST RUN via the reset endpoint — no credentials file."
