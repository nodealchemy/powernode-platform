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
# SOAK (INC-5) — hold the provisioned baseline under sensor observation:
#
#   ... --run-id evo-01 --soak [--soak-seconds N] [--soak-iterations N]
#
# The mission stays ACTIVE at `adapting` (a live phase, not an end state) for a
# BOUNDED window, so ProjectSloSensor/ProjectMetricsCollector have something to
# watch and an operator can amend the brief or approve an adaptation while it
# runs. Every exit is a ceiling — iterations, wall-clock, the LLM budget, or the
# mission leaving the observable state; the bounds default to the DB-driven
# `ai.dryrun.soak_max_*` / `ai.dryrun.budget_usd` settings. Teardown (cancel,
# then sweep by prefix) still runs at the END of the window, and an orphaned
# resource halts before the sweep so forensics survive.
#
# TEARDOWN-ONLY — finish a run left standing (a `--no-cleanup` soak, or one
# whose process died before its teardown ran):
#
#   ... --run-id evo-01 --teardown-only [--force-teardown]
#
# An orphaned resource halts that sweep too, and the record of it is permanent —
# `--force-teardown` is how an operator finishes the job after reading the leak.
# The finding is still reported either way.
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
  o.on("--soak")                         { opts[:soak] = true }
  o.on("--soak-seconds SEC", Integer)    { |v| opts[:soak_max_seconds] = v }
  o.on("--soak-iterations N", Integer)   { |v| opts[:soak_max_iterations] = v }
  o.on("--teardown-only")                { opts[:teardown_only] = true }
  o.on("--force-teardown")               { opts[:force_teardown] = true }
end.parse!(ARGV.reject { |a| a == "run.rb" })

abort("--account is required") unless opts[:account]
# A teardown addresses an EXISTING run; a generated run_id would silently sweep
# a prefix nothing was ever created under and report a clean nothing.
abort("--teardown-only requires --run-id") if opts[:teardown_only] && opts[:run_id].blank?
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
harness_opts[:soak]            = true                   if opts[:soak]
harness_opts[:soak_max_seconds]    = opts[:soak_max_seconds]    if opts[:soak_max_seconds]
harness_opts[:soak_max_iterations] = opts[:soak_max_iterations] if opts[:soak_max_iterations]
harness_opts[:force_teardown]      = true                       if opts[:force_teardown]

harness = Ai::Provisioning::DryrunHarness.new(**harness_opts)
# --teardown-only never provisions: it cancels this run_id's own mission and
# sweeps its prefix. `--soak` is meaningless alongside it (there is nothing to
# hold open), so refuse the combination rather than silently ignoring one.
abort("--teardown-only cannot be combined with --soak") if opts[:teardown_only] && opts[:soak]
# Without the sweep a teardown cancels the mission and stops — a green exit for
# a command whose name promises a teardown. Say so rather than half-doing it.
abort("--teardown-only cannot be combined with --no-cleanup") if opts[:teardown_only] && !opts[:cleanup]
# Forcing past the orphan halt is a RECOVERY decision, taken after reading the
# leak. On a fresh run the halt is the whole point — the fleet still matches the
# plan at that moment, which is the only time forensics are worth anything.
abort("--force-teardown requires --teardown-only") if opts[:force_teardown] && !opts[:teardown_only]
result = opts[:teardown_only] ? harness.teardown_only! : harness.run

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
