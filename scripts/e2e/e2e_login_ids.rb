# frozen_string_literal: true

# E2E login provisioning bootstrap. Mints a short-lived admin access JWT and
# emits the seeded E2E test users' ids so the Node provisioner
# (scripts/e2e/provision-test-logins.cjs) can call the real
# POST /api/v1/users/:id/reset_password for each — establishing per-run
# passwords without any credentials file on disk.
#
# Prints ONLY machine-parsed lines the Node caller consumes:
#   TOKEN:<jwt>
#   USER:<role>:<id>:<email>
# The token is never logged by the harness itself. Uses $stdout.write (not
# puts) per the repo's no-puts-in-.rb rule.
#
# Run from server/:  bundle exec rails runner <abs path>/e2e_login_ids.rb

ROLE_EMAILS = {
  'demo' => 'demo@powernode.org',
  'admin' => 'admin@powernode.org',
  'manager' => 'manager@powernode.org',
  'billing' => 'billing@powernode.org',
  'member' => 'member@powernode.org'
}.freeze

admin = User.find_by(email: 'admin@powernode.org')
admin ||= User.joins(:roles).where(roles: { name: %w[super_admin admin] }).first

if admin.nil?
  warn 'E2E_NO_ADMIN — seed demo users first (POWERNODE_SEED_DEMO=true rails db:seed)'
  exit 1
end

token = Security::JwtService.generate_user_tokens(admin)[:access_token]
$stdout.write("TOKEN:#{token}\n")

ROLE_EMAILS.each do |role, email|
  user = User.find_by(email: email)
  $stdout.write("USER:#{role}:#{user.id}:#{email}\n") if user
end
