# frozen_string_literal: true

# Core CAPABILITY skills (skills-first agents, PRE-1). Each data file under
# db/seeds/capability_skills/ is a YAML list authored to the contract in
# Ai::Skills::Contract; the batch passes Ai::Skills::SeedGate (contract,
# one owner per capability, slug collisions, registered verbs, relations,
# purity, duplicate / overlap bands) before any row is written, so a
# non-conforming or duplicate skill fails this seed whole. Rows are GLOBAL
# (account_id nil, source_key = slug); a re-run never reactivates, re-enables
# or overwrites an operator-modified row (see Ai::Skills::CapabilitySeeder).
#
# A failure is recorded with Ai::Skills::CapabilitySeeder.record_failure! and
# re-raised, and db/seeds.rb ends the run with a marked error banner (non-zero
# exit under POWERNODE_SEED_STRICT=true) — never a warning lost mid-log.
#
# The gate's embedding space: POWERNODE_SKILL_GATE_EMBEDDER = auto (default) |
# provider | lexical. Dry-run first: rails "skills:gate:check[core,provider]".
#
# Legacy skills seeded by ai_skills_seed.rb are left untouched here; they are
# retired separately.
return unless Powernode::Seeds.baseline?

puts "  [Skills] Seeding core capability skills..."

begin
  entries = Ai::Skills::CapabilitySeeder.load_entries(Rails.root.join("db", "seeds", "capability_skills"))
  result = Ai::Skills::CapabilitySeeder.new(
    owner_repo: Ai::Skills::Contract::CORE_OWNER,
    embedder: ENV.fetch("POWERNODE_SKILL_GATE_EMBEDDER", "auto")
  ).seed!(entries)

  Rails.logger.info "[Seeds] Core capability skills: #{result.summary}"
  puts "  ✅ Core capability skills: #{result.summary}"
  result.warnings.each do |warning|
    Rails.logger.warn "[Seeds] Core capability skill warning: #{warning}"
    puts "  ⚠️  #{warning}"
  end
  if result.graph_failures.any?
    puts "  ⚠️  Knowledge-graph sync failures: #{result.graph_failures.size}"
    result.graph_failures.first(10).each { |failure| puts "     - #{failure}" }
  end
rescue StandardError => e
  Ai::Skills::CapabilitySeeder.record_failure!(Ai::Skills::Contract::CORE_OWNER, e)
  puts "  ❌ CORE CAPABILITY SKILL SEED FAILED: #{e.class}: #{e.message.lines.first(12).join}"
  raise
end
