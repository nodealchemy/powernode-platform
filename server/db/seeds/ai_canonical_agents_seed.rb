# frozen_string_literal: true

# Core's canonical agents (skills-first agents, PRE-2): Powernode Concierge,
# Platform Engineer and Platform Reviewer — whatever core declared in
# Ai::Agents::CanonicalRoster. An extension's agents are that extension's own
# seed, through the same registry and the same seeder; core never names them. WHO each agent is (slug, name, type,
# tier, domains, routing description, assembly prompt, posture) is the roster
# spec, shared with the Claude Code export and the assembler.
#
# SHADOW MODE — seeded INACTIVE beside the legacy canonicals they will absorb,
# which keep running the platform; no intervention-policy row, no concierge
# flag, trust and chains create-only. The mechanics and their reasons are in
# db/seeds/concerns/canonical_roster_seeder.rb.

puts "\n🧭 Seeding core's canonical agents (shadow mode: inactive, no policy rows)..."

require_relative "concerns/canonical_roster_seeder"

CoreSeeds::CanonicalRosterSeeder.seed!(owner: Ai::Agents::CanonicalRoster::CORE_OWNER)
