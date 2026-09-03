# frozen_string_literal: true

# Claude Code provider scope (baseline, per account) — IMP-e8513b30152d.
#
# One INACTIVE, credential-less, non-routable `claude-code` Ai::Provider per
# account: the scope Ai::ClaudeExport::ExecutionRecorder records a Claude Code
# run of a platform agent under when the account holds no credentialed
# Anthropic provider (platform.record_agent_execution). Seeded here rather
# than minted on first report so the report path — reachable by any
# ai.agents.execute holder — never creates a provider row. Keyed by
# Ai::ClaudeExport::ProviderScopeSeeder::SOURCE_KEY: idempotent, and a row the
# pre-seed on-demand path minted is adopted, not duplicated.
#
# Seeds never re-run after first boot: an account created later gets its scope
# from Accounts::ProvisionService through the same seam. No account yet
# (fresh core/prod before the setup wizard) ⇒ harmless no-op.
puts "\n🧾 Seeding the Claude Code provider scope (one inactive row per account)..."

if Account.exists?
  seeded = Ai::ClaudeExport::ProviderScopeSeeder.ensure_all!
  puts "✅ Claude Code provider scope ensured for #{seeded} account(s)"
else
  puts "⏭️  No account yet — the scope is seeded at first-account bootstrap (re-seed after setup)"
end
