# frozen_string_literal: true

# P2 — headless platform-autonomy dry-run. One command, exit code = finding count.
#
#   bundle exec rails runner scripts/dryrun/run.rb \
#     --account "Powernode Admin" --run-id 20260809h \
#     [--objective "..."] [--md report.md] [--json report.json] [--no-cleanup]
#
# Drives a `dryrun-<runId>` mission end-to-end through the real pipeline
# (Ai::Provisioning::DryrunHarness), approves its own gates individually, grades
# the outcome against the protocol §5 oracles, and tears the stack down. The
# harness restores the account's routing gate on the way out.
#
# Reports mirror scripts/ai-smoke conventions (--md / --json). stderr carries
# progress; stdout stays clean for piping. Exit code == number of findings
# (0 = clean pass), so CI/cron can gate on it.

require "optparse"
require "json"

opts = { cleanup: true }
OptionParser.new do |o|
  o.on("--account NAME") { |v| opts[:account] = v }
  o.on("--run-id ID")    { |v| opts[:run_id] = v }
  o.on("--objective S")  { |v| opts[:objective] = v }
  o.on("--user EMAIL")   { |v| opts[:user] = v }
  o.on("--md PATH")      { |v| opts[:md] = v }
  o.on("--json PATH")    { |v| opts[:json] = v }
  o.on("--no-cleanup")   { opts[:cleanup] = false }
  o.on("--expected-count N", Integer) { |v| opts[:expected_count] = v }
  o.on("--compose-timeout SEC", Integer) { |v| opts[:compose_timeout] = v }
  o.on("--execute-timeout SEC", Integer) { |v| opts[:execute_timeout] = v }
  o.on("--poll-interval SEC", Integer)   { |v| opts[:poll_interval] = v }
end.parse!(ARGV.reject { |a| a == "run.rb" })

abort("--account is required") unless opts[:account]
run_id = opts[:run_id] || Time.now.utc.strftime("%Y%m%d%H%M%S")
warn "[dryrun] run_id=#{run_id} account=#{opts[:account]}"

account = Account.find_by!(name: opts[:account])
user = if opts[:user]
         account.users.find_by!(email: opts[:user])
       else
         account.users.order(:created_at).first
       end
abort("no user for account #{opts[:account]}") unless user

objective = opts[:objective] ||
            "dryrun-#{run_id}: Provision a 3-node Powernode stack across the dna and rna " \
            "regions using the 'IPNode PVE' provider, cloned from the powernode-ops-cell " \
            "template. The use case is an end-to-end platform-validation test workload " \
            "exercising provisioning, module assignment, and the container-runtime handshake. " \
            "Initial scale 3, target 3, steady growth. Monthly budget cap 5 USD. Every " \
            "created artifact must carry the dryrun- name prefix."

harness_opts = {
  account: account, user: user, objective: objective, run_id: run_id,
  cleanup: opts[:cleanup], expected_count: opts[:expected_count]
}
harness_opts[:compose_timeout] = opts[:compose_timeout] if opts[:compose_timeout]
harness_opts[:execute_timeout] = opts[:execute_timeout] if opts[:execute_timeout]
harness_opts[:poll_interval]   = opts[:poll_interval]   if opts[:poll_interval]

result = Ai::Provisioning::DryrunHarness.new(**harness_opts).run

File.write(opts[:md], result.to_markdown) if opts[:md]
File.write(opts[:json], JSON.pretty_generate(result.to_h)) if opts[:json]

warn "[dryrun] #{result.passed? ? 'PASS' : "FAIL (#{result.exit_code} finding(s))"} " \
     "— reached #{result.reached_phase}; oracles #{result.oracles.inspect}"
result.findings.each { |f| warn "  [#{f.severity}] #{f.dimension}: #{f.detail}" }

# stdout: machine-readable one-liner; exit code = finding count.
puts JSON.generate(result.to_h.slice(:run_id, :passed, :exit_code, :oracles))
# Clamp to a byte: a POSIX exit code wraps mod 256, so 256 findings would
# otherwise exit 0 (a false pass). Any finding still exits non-zero.
exit([ result.exit_code, 255 ].min)
