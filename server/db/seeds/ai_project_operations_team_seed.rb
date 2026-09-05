# frozen_string_literal: true

# APO increment `app-5` — the "Project Operations" canonical team TEMPLATE.
#
# A project (Ai::Project, APO app-4) is the durable owner of a fleet of
# missions, and it needs a team that owns it: something that watches it,
# deploys it and keeps it up. That is three seats — an OBSERVER, a DEPLOYER and
# an SRE — and all three already exist as core canonical agents, so this seed
# names them rather than inventing agents.
#
#   observer  system-health-monitor         — availability and health
#   deployer  release-manager               — walks the promotion ladder
#   SRE       infrastructure-health-monitor — owns the incident, LEADS the team
#
# WHY THE SRE LEADS. Ai::Teams::CanonicalTeamSeeder requires exactly one lead
# carrying the "manager" role, and in an operations team the incident owner is
# the one that decides and delegates. Making the observer or the deployer the
# manager would put the narrowest role at the top of the team.
#
# WHY A THIRD TEMPLATE. The two seeded canonical teams do not almost fit.
# "Platform Engineering" (db/seeds/ai_canonical_teams_seed.rb) builds the
# platform — research, specification, review, release — and is managed by the
# Platform Architect; its subject is the codebase, not a running project. The
# "System Operations" twin is an EXTENSION seed and core may not name its
# agents at all. Extending either would change what an existing team means for
# every account that already has one.
#
# TEMPLATE ONLY — NO ACCOUNT TEAM. Unlike the Platform Engineering seed, this
# file materialises nothing. The template is marked `per_project`, and
# Ai::Projects::TeamProvisioner materialises it once per project;
# Ai::Teams::CanonicalTeamReconciler.reconcile_all! skips it for that reason
# (see its .account_materialised_templates). Materialising it for the account
# would create a team and three agent clones nobody asked for, and would make
# the account team look like the project team it is not.
#
# The seats' lineage edges and the manager's delegation policy keep their own
# single writers (Ai::Agents::HierarchyWriter, through the hierarchy seeds).
# This file writes the template row and nothing else. Idempotent.

puts "\n🏗️  Seeding the Project Operations canonical team template..."

PROJECT_OPERATIONS_TEAM = {
  slug: Ai::Projects::TeamProvisioner::TEMPLATE_SLUG,
  name: "Project Operations",
  category: "operations",
  tags: %w[canonical operations project per-project],
  description: "Owns one project once it is running: observes its health, deploys its changes and " \
               "keeps it up. Materialised per Ai::Project by Ai::Projects::TeamProvisioner, never " \
               "for the account as a whole.",
  materialisation: Ai::Teams::CanonicalTeamSeeder::MATERIALISATION_PROJECT,
  members: [
    { slug: "infrastructure-health-monitor", name: "Project SRE", role: "manager", lead: true,
      description: "Owns the project's reliability: triages its signals, decides the response and " \
                   "delegates to the deployer or the observer within the project's bounds" },
    { slug: "release-manager", name: "Project Deployer", role: "executor",
      description: "Delivers changes to the project — walks the promotion ladder and verifies by digest" },
    { slug: "system-health-monitor", name: "Project Observer", role: "analyst",
      description: "Watches the project's availability and health and reports what it sees" }
  ]
}.freeze

project_operations_template = Ai::Teams::CanonicalTeamSeeder.seed!(**PROJECT_OPERATIONS_TEAM)
puts "  ✅ Template #{project_operations_template.slug} (global, per-project, " \
     "#{project_operations_template.member_definitions.size} seats) — materialised per project, not per account"
