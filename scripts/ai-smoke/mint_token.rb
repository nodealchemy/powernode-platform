# frozen_string_literal: true

# Mint a short-lived access JWT for a seeded user so the AI smoke harness can
# authenticate against the running API. Prints ONLY "TOKEN:<jwt>" on success so
# the Node caller can parse it deterministically; the token is never logged by
# the harness itself.
#
# Run from the server/ directory:
#   bundle exec rails runner <abs path>/mint_token.rb
#
# Configure the user via AI_SMOKE_USER (default: admin@powernode.org). This
# mirrors the JWT-generation approach already used by scripts/mcp-smoke-test.sh.

email = ENV.fetch("AI_SMOKE_USER", "admin@powernode.org")
user = User.find_by(email: email)

if user.nil?
  warn "AI_SMOKE_NO_USER:#{email}"
  exit 1
end

token = Security::JwtService.generate_user_tokens(user)[:access_token]
# $stdout.write (not puts) — the repo's pre-commit hook forbids puts in .rb;
# this is the script's single machine-parsed output line for the Node caller.
$stdout.write("TOKEN:#{token}\n")
