# frozen_string_literal: true

require "spec_helper"

# Ratchet against reintroducing the stale "powernode-backend@default"-style
# systemd template unit names into a seeded agent prompt.
#
# CLAUDE.md is explicit: on module-composed nodes the agent generates
# powernode-<moduleID>-<serviceName>.service (a UUID, never a hand-typed
# name), and `systemctl list-unit-files 'powernode*'` shows NO `@` template
# unit at all on either dev-cell or ops-hub. `systemctl restart` on a
# nonexistent unit fails silently in a `||` chain — new code lands on disk
# while the old process keeps running, which looks exactly like a
# successful deploy. ai_dev_team_seed.rb, ai_memory_pools_seed.rb and
# ai_utility_agents_seed.rb all instructed agents to run exactly that
# (`sudo systemctl restart powernode-backend@default`, `Services:
# powernode-backend@, powernode-worker@, ...`) before this spec existed.
#
# Deliberately NOT a blanket string ban: the corrected prompts keep the
# fabricated name visible as a NEGATIVE example ("NEVER guess a name like
# powernode-backend@default; discover it instead") — the repo's matched-pair
# convention, so an operator who half-remembers the old name can still find
# the correction. A bare `expect(content).not_to include(...)` would fail on
# that corrective text too, defeating the fix this spec is meant to guard.
# So the oracle is CONTEXTUAL: a template-unit token is only a violation if
# nothing within the preceding ~80 characters says not to guess it.
RSpec.describe "seeded prompts do not name a stale powernode-*@ template unit" do
  seeds_dir = File.expand_path("../../../db/seeds", __dir__)

  # Matches the exact stale forms this defect took: powernode-backend@,
  # powernode-worker@, powernode-worker-web@, powernode-frontend@ (bare
  # template or with an instance suffix like `@default`).
  STALE_UNIT_TOKEN = /powernode-(?:backend|worker-web|worker|frontend)@/

  # The corrective phrasing every fix in this file uses. Matched
  # case-insensitively against the text immediately before the token so the
  # negative-example mentions stay green while a reintroduced directive
  # (`restart powernode-backend@default`, `Services: powernode-backend@, ...`)
  # is caught.
  CORRECTIVE_LEAD_IN = /never guess/i

  it "names no stale template unit outside a 'never guess' correction" do
    seed_files = Dir.glob(File.join(seeds_dir, "**", "*.rb"))
    raise "no seed files found under #{seeds_dir} — this spec would be vacuous" if seed_files.empty?

    violations = []

    seed_files.sort.each do |path|
      content = File.read(path)
      content.to_enum(:scan, STALE_UNIT_TOKEN).each do
        match_start = Regexp.last_match.begin(0)
        matched_token = Regexp.last_match(0)
        preceding = content[[ match_start - 80, 0 ].max...match_start]
        next if preceding.match?(CORRECTIVE_LEAD_IN)

        line_no = content[0...match_start].count("\n") + 1
        rel = path.delete_prefix("#{File.expand_path('../../..', __dir__)}/")
        violations << "#{rel}:#{line_no} — #{matched_token}"
      end
    end

    expect(violations).to be_empty,
      "seeded prompt(s) instruct a stale powernode-*@ systemd unit name outside a " \
      "'never guess' correction (systemctl restart on a nonexistent unit fails silently " \
      "in a `||` chain): #{violations.join(', ')}"
  end
end
