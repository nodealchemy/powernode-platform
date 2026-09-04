# frozen_string_literal: true

# Canonical teams (HIER-P4, operator rulings 2026-09-03): the "Platform
# Engineering" team as SEEDED DATA — a global, is_system, source_key-managed
# Ai::TeamTemplate (nodes + roles) materialised for the admin account as a
# hierarchical / manager_led / hub_spoke Ai::AgentTeam whose manager is the
# Platform Architect and whose members are the Engineering agents
# ai_agent_hierarchy_seed.rb hangs under it. ONE STRUCTURE, THREE VIEWS: the
# template, the lineage forest and the delegation graph describe the same
# organisation, and Ai::Teams::CanonicalTeamReconciler reports where they
# disagree (`drift`) and repairs membership (`reconcile!`, also run by
# `rails system:governance:reconcile` in the system extension). A graph is a
# TeamTemplate + delegation policies + the execution row its strategy writes
# when run (an Ai::TeamExecution; proposal §2 Phase 4 says "DagExecution", but
# the only writer of Ai::DagExecution is Ai::A2a::DagExecutor and nothing on
# the team path calls it) — no new model.
#
# WHO SITS IN THE TEAM. The account's EXECUTING PRINCIPALS for the canonical
# agents — the clones Ai::Agents::AccountPrincipalResolver mints — never the
# canonicals themselves (§5 ruling 8: a global canonical never executes, so a
# team it sat in could never run). The template is the canonical; the team is
# the account's materialisation, flagged `canonical` in team_config and
# read-only through the MCP verbs (clone the template to customise).
#
# WHAT THIS FILE WRITES: the template row (through the one seam
# Ai::Teams::CanonicalTeamSeeder, shared with the system extension's "System
# Operations" seed) and the admin account's team, members and backing
# Ai::TeamRoles. It CREATES no lineage edge, no delegation row and no policy
# row — those keep their single writers (ruling 7; the hierarchy seeds and
# PolicyReconciler). The principal seam it mints seats through may RE-HOME an
# existing intervention-policy row from a canonical onto that account's clone
# (Ai::Agents::AccountPrincipalResolver#rehome_intervention_policies!); that
# moves an already-declared row, it never declares one.
#
# Runs LAST in the baseline agent block of db/seeds.rb, after
# ai_agent_hierarchy_seed.rb, so every canonical and every edge it verifies
# against already exists. Idempotent: a re-run changes nothing. Without an
# account only the template is written (the team waits for the admin account,
# like every other account-scoped follow-on row).
#
# The "System Operations" twin (manager System Concierge, members the eleven
# domain agents) is an EXTENSION seed — extensions/system/server/db/seeds/
# system_operations_team_seed.rb — because core never names an extension agent.

puts "\n👥 Seeding canonical team templates (Platform Engineering)..."

PLATFORM_ENGINEERING_TEAM = {
  slug: "platform-engineering",
  name: "Platform Engineering",
  category: "engineering",
  tags: %w[canonical engineering hierarchical],
  description: "Builds the platform: research, specification, architecture, development, review, release, " \
               "documentation and knowledge — managed by the Platform Architect under the delegation policies " \
               "ai_agent_hierarchy_seed.rb writes. The manager_led strategy delegates only to members the " \
               "Architect's policy admits.",
  members: [
    { slug: "platform-architect",       name: "Platform Architect",       role: "manager",    lead: true,
      description: "Designs agents, teams, skills and prompts; decomposes the objective and synthesises the result" },
    { slug: "platform-developer",       name: "Platform Developer",       role: "executor",
      description: "Drains dev-improve as the platform_agent driver; implements under the loop guardrails" },
    { slug: "release-manager",          name: "Release Manager",          role: "executor",
      description: "Builds on a merged develop, walks the promotion ladder, verifies by digest, holds on skew" },
    { slug: "research-analyst",         name: "Research Analyst",         role: "researcher",
      description: "Web and knowledge research, tech-radar sweeps, capability-gap offers" },
    { slug: "strategic-planner",        name: "Strategic Planner",        role: "researcher",
      description: "Long-horizon planning and prioritisation" },
    { slug: "prd-generator",            name: "PRD Generator",            role: "writer",
      description: "Turns an approved offer into a spec-driven campaign proposal with increments" },
    { slug: "llm-judge",                name: "LLM Judge",                role: "reviewer",
      description: "Independent review of every drained task before it is reported complete" },
    { slug: "system-quality-assurance", name: "System Quality Assurance", role: "reviewer",
      description: "Test-gap analysis and verification" },
    { slug: "documentation-specialist", name: "Documentation Specialist", role: "writer",
      description: "Keeps docs, the sensor reference and the MCP catalog truthful after every landed change" },
    { slug: "knowledge-graph-curator",  name: "Knowledge Graph Curator",  role: "analyst",
      description: "Consolidates learnings from every lane into platform knowledge" }
  ]
}.freeze

platform_engineering_template = Ai::Teams::CanonicalTeamSeeder.seed!(**PLATFORM_ENGINEERING_TEAM)
puts "  ✅ Template #{platform_engineering_template.slug} (global, #{platform_engineering_template.member_definitions.size} seats)"

canonical_teams_account = Account.find_by(name: "Powernode Admin") || Account.first
if canonical_teams_account.nil?
  puts "  ⚠️  No account exists to materialise the team in — template seeded only (re-run after setup)"
else
  result = Ai::Teams::CanonicalTeamReconciler.new(account: canonical_teams_account,
                                                   template: platform_engineering_template).reconcile!
  if result.team
    puts "  ✅ #{result.team.name} #{result.created ? 'materialised' : 'present'} in #{canonical_teams_account.name}: " \
         "+#{result.members_added} -#{result.members_removed} ~#{result.members_updated} member(s), " \
         "#{result.team.members.count} seated"
  end
  puts "  ⚠️  Skipped (seat not filled — drift until seeded): #{result.skipped.join(', ')}" if result.skipped.any?
end
