# frozen_string_literal: true

# Minimal production seed data
# This file contains only essential data needed for all environments

puts "🌱 Seeding Powernode platform..."

# Three-tier seed gating (demo ⊇ baseline ⊇ core):
#   CORE     — always. Account-independent platform reference (permissions, roles,
#              plans, settings, KB categories, system worker).
#   BASELINE — Powernode::Seeds.baseline? (POWERNODE_SEED_BASELINE, default ON).
#              Foundational product content seeded as GLOBAL (account_id nil,
#              read-only, upserted by source_key): skills, prompt templates, KB
#              documentation, default knowledge bases, agent/team/mission templates.
#              Needs NO account (global content), so it seeds in core/prod too.
#              ONE EXCEPTION (IMP-e8513b30152d): ai_claude_code_provider_seed.rb
#              is baseline but PER-ACCOUNT — it no-ops when no account exists and
#              is re-run for later accounts through its own seam. See its header.
#   DEMO     — Powernode::Seeds.demo? (POWERNODE_SEED_DEMO=true / SEED_ADMIN_USERS).
#              OFF by default in all envs — opt in explicitly.
#              Account-scoped samples: test accounts/users, sample agents, showcase pages.
# Module methods (not locals) so files pulled in via `load` can call them.
module Powernode
  module Seeds
    def self.demo?
      return true if ENV["SEED_ADMIN_USERS"] == "true"

      # Demo is OFF by default in every environment — opt in explicitly with
      # POWERNODE_SEED_DEMO=true. (Previously dev/test defaulted ON, which
      # silently seeded sample accounts/agents on a plain `rails db:seed`.)
      ENV.fetch("POWERNODE_SEED_DEMO", "false").to_s == "true"
    end

    # Foundational product content (global, read-only). On by default everywhere;
    # opt out with POWERNODE_SEED_BASELINE=false. demo? implies baseline.
    def self.baseline?
      return true if demo?

      ENV.fetch("POWERNODE_SEED_BASELINE", "true").to_s != "false"
    end

    # Create/refresh the System Worker (required for worker↔backend comms).
    # Workers must belong to an account, so this is a no-op until at least one
    # account exists: on a fresh core/prod build no account is present at seed
    # time (the setup wizard creates the first account later), so we skip
    # gracefully with an informative message and NO error. In demo mode this
    # is invoked again AFTER the demo accounts are seeded. Idempotent — safe to
    # call multiple times.
    # The system Worker is a bootstrap invariant (it authenticates worker→backend
    # API calls), so the real creation lives in the core service
    # Workers::EnsureSystemWorker — invoked here for demo/re-seed and from
    # Setup::FirstAdminService on first-account bootstrap (core/prod). No account
    # yet ⇒ harmless no-op; the wizard creates the worker with the account.
    def self.ensure_system_worker!
      account = Account.first
      unless account
        puts "⏭️  No account yet — System Worker is created at first-account bootstrap."
        return
      end

      worker = ::Workers::EnsureSystemWorker.call(account: account)
      if worker
        puts "🔧 System worker ensured — #{worker.masked_token} (roles: #{worker.role_names.join(', ')})"
      else
        puts "⚠️  System worker could not be ensured (see logs)."
      end
    end
  end
end
puts("   mode: CORE#{Powernode::Seeds.baseline? ? ' + BASELINE' : ''}#{Powernode::Seeds.demo? ? ' + DEMO' : ''} data")

# Resilient seed load: one broken/duplicate content row (e.g. a pre-existing
# account-scoped row shadowing a global slug) must NEVER abort the whole seed
# run — that previously froze ALL downstream agent + extension seeding. Mirrors
# the per-extension rescue used for extension seeds.
def safe_load(seed_file)
  load Rails.root.join('db', 'seeds', seed_file)
rescue StandardError => e
  Rails.logger.error("[seeds] #{seed_file} failed: #{e.class}: #{e.message}")
  puts "  ⚠️  #{seed_file} failed (#{e.class}: #{e.message}) — continuing"
end

# Permissions are code-defined (the Permissions catalog is the source of truth);
# there is no permissions table to seed. Roles + their grants are seeded from the
# catalog. Global roles only — account-scoped roles are created at runtime.
puts "📝 Seeding global roles from the permission catalog..."
puts "✅ Catalog defines #{Permissions.all_permissions.size} permissions"

Role.sync_from_config!
puts "✅ Created #{Role.count} roles"

# Validate permission system integrity
puts "\n🔍 Validating permission system integrity..."
validation_issues = []

# Check for super_admin role
super_admin_role = Role.find_by(name: 'super_admin')
if super_admin_role.nil?
  validation_issues << "Critical: super_admin role not found!"
else
  # Verify super_admin has system.admin permission
  unless super_admin_role.has_permission?('system.admin')
    validation_issues << "Critical: super_admin role missing system.admin permission!"
  end
end

# Check for system.admin permission in the catalog
unless Permissions.permission_exists?('system.admin')
  validation_issues << "Critical: system.admin permission not defined in catalog!"
end

# Check permission categories
permission_categories = Permissions.all_permissions.keys.map { |name| name.split('.').first }.uniq
expected_categories = [ 'users', 'admin', 'billing', 'system', 'analytics', 'pages', 'storage' ]
missing_categories = expected_categories - permission_categories

if missing_categories.any?
  validation_issues << "Warning: Missing permission categories: #{missing_categories.join(', ')}"
end

# Report validation results
if validation_issues.empty?
  puts "✅ Permission system validation passed"
  puts "   Total Permissions: #{Permissions.all_permissions.size}"
  puts "   Total Roles: #{Role.count}"
  puts "   Permission Categories: #{permission_categories.count} (#{permission_categories.join(', ')})"
else
  puts "⚠️  Permission system validation found #{validation_issues.count} issues:"
  validation_issues.each { |issue| puts "   - #{issue}" }
  if validation_issues.any? { |i| i.start_with?('Critical:') }
    puts "\n❌ Critical validation errors found. Please check permissions.rb configuration!"
  end
end

# Plans are seeded by the business extension (extensions/business/server/db/seeds/saas_plans_seed.rb)
# In core-only mode, no Plan model exists — all features are unlocked via FeatureGateService.

# Create system worker (required for worker-backend communication).
# Runs only when an account already exists (e.g. re-seed, or core/prod after the
# setup wizard). On a fresh build with no account yet it skips gracefully — demo
# mode invokes it again after the demo accounts are seeded (see below).
Powernode::Seeds.ensure_system_worker!

# Demo: test/dev accounts + users (core/prod gets the first account from the wizard).
if Powernode::Seeds.demo?
  puts "\n🏢 Creating development/test accounts and users..."

  # Load the unified test user seed which handles all user creation
  # and writes credentials to test-credentials.json
  safe_load('cypress_test_users.rb')

  # Now that demo accounts exist, (re)create the System Worker bound to the
  # admin account. No-op/refresh if the early call above already created it.
  Powernode::Seeds.ensure_system_worker!
end

# AI providers (account-scoped) — seeded BEFORE the baseline section because
# baseline's fundamental global agents AND the AI Example showcase data
# (ai_example_templates_seed) gate on providers being present. Seeding
# providers here lets a SINGLE db:seed produce the full set instead of needing
# a second pass. Not demo-gated: the seed guards itself (skips when the admin
# account doesn't exist yet), so in core mode it no-ops on a genuinely fresh
# DB and seeds the provider catalog once the admin account exists (hub
# first-boot bootstraps the admin before db:seed; wizard installs re-seed).
puts "\n🤖 Loading Comprehensive AI Providers (OpenAI, Grok, Ollama, Claude)..."
safe_load('comprehensive_ai_providers_seed.rb')

# 📄 Create public pages — demo/account-scoped (need an admin author). Gated by
# Powernode::Seeds.demo?; in core/prod the setup wizard seeds account pages.
if Powernode::Seeds.demo?
  safe_load('public_pages_seed.rb')
end

# Load Knowledge Base data (KB permissions are code-defined in the catalog now).
# Resilient: a single broken/duplicate content article must NOT abort the whole
# seed run (it previously aborted before the agent + extension seeds ever ran).
puts "\n📚 Loading Knowledge Base content..."
safe_load('knowledge_base_articles.rb')

# Marketing permissions loaded via extension seeds (extensions/marketing/)

# ---------------------------------------------------------------------------
# BASELINE: foundational GLOBAL content (account_id nil, upserted by source_key).
# Seeds in core/prod too — no account required. Each of these files seeds its
# content rows globally and demo-gates any instance creation internally, EXCEPT
# the first member below, which is per-account by nature (IMP-e8513b30152d).
# ---------------------------------------------------------------------------
if Powernode::Seeds.baseline?
  # Per-ACCOUNT (not global) but baseline: the inactive `claude-code` provider
  # scope Claude Code runs are recorded under (IMP-e8513b30152d). Runs after
  # the provider catalog above; no account yet ⇒ the seed no-ops (the account a
  # wizard install creates later is covered by Setup::FirstAdminService, and an
  # established install by `rails db:seed:claude_code_provider_scopes`).
  puts "\n🧾 Loading the Claude Code provider scope..."
  safe_load('ai_claude_code_provider_seed.rb')

  puts "\n🧩 Loading AI Skills..."
  safe_load('ai_skills_seed.rb')

  puts "\n📋 Loading AI Example Templates..."
  safe_load('ai_example_templates_seed.rb')

  puts "\n🎯 Loading AI Mission Templates..."
  safe_load('ai_mission_templates.rb')

  puts "\n📝 Loading AI System Prompt Templates..."
  safe_load('ai_system_prompt_templates_seed.rb')

  puts "\n📚 Loading RAG Knowledge Base seed..."
  safe_load('ai_knowledge_base_seed.rb')

  puts "\n🔧 Loading AI DevOps Templates..."
  safe_load('ai_devops_templates_seed.rb')

  puts "\n📦 Loading DevOps Container Templates..."
  safe_load('devops_container_templates.rb')

  puts "\n🔌 Loading MCP Server Container Templates..."
  safe_load('mcp_container_templates_seed.rb')

  # Seed AI model pricing from hardcoded constant (account-independent reference
  # the cost-aware model selector needs — baseline, not demo).
  if defined?(Ai::ProviderManagementService::MODEL_PRICING) && Ai::ModelPricing.count == 0
    puts "\n💰 Seeding AI model pricing..."
    Ai::ProviderManagementService::MODEL_PRICING.each do |model_id, pricing|
      provider_type = case model_id
                      when /^gpt-|^o[34]/ then "openai"
                      when /^claude/ then "anthropic"
                      when /^gemini/ then "google"
                      when /^grok/ then "xai"
                      when /^llama|^mixtral/ then "groq"
                      when /^mistral|^codestral/ then "mistral"
                      when /^command/ then "cohere"
                      else "unknown"
                      end

      Ai::ModelPricing.find_or_create_by!(model_id: model_id, provider_type: provider_type) do |mp|
        mp.input_per_1k = pricing["input"]
        mp.output_per_1k = pricing["output"]
        mp.cached_input_per_1k = pricing["cached_input"] || 0
        mp.tier = Ai::ModelTiers.to_label(Ai::ModelTiers.tier_for_price(pricing["input"]))
        mp.source = "constant_fallback"
        mp.last_synced_at = Time.current
        mp.metadata = {}
      end
    end
    puts "✅ Seeded #{Ai::ModelPricing.count} model pricings"
  end

  # Fundamental GLOBAL platform agents — the platform's canonical agent roster
  # (account_id nil; accounts clone to customize). BASELINE, not demo: they are
  # core platform resources, no longer gated behind demo. A canonical row needs
  # NO account, user or provider (IMP-6cda93db7f31: creator and provider are
  # optional on a global row), so every canonical seeds on a fresh core/prod DB
  # before setup; only the account-scoped follow-on rows the seeds write (trust
  # scores, approval chains, policy rows, budgets, lineage, the demo agents)
  # wait for the admin account, and the canonicals' own creator/provider
  # columns fill in on that same re-seed (db/seeds/concerns/canonical_agent_owner.rb).
  # Per-seed rescue so one failure never aborts the rest of platform seeding
  # (the agent seeds that ship with extensions run via the extension
  # orchestrator below, also baseline; those still require an account, a user
  # and a provider, which is why Ai::ClaudeExport::AgentSkeletonSync refuses to
  # sync at all until all three exist — a partial roster is not a roster).
  # `ai_engineering_agents_seed` (HIER-P2B-ENG) adds the Engineering
  # hierarchy's canonicals (Platform Architect, Platform Developer, Release
  # Manager, Documentation Specialist) with their policy rows and chains;
  # `platform_skill_assignments_seed` then binds skills to every canonical.
  # `ai_agent_hierarchy_seed` runs after them: it attaches every canonical the
  # seeds above created — the core forest under the core concierge and the
  # Engineering agents under the Platform Architect — and writes their
  # delegation policies (HIER-P1), so it must see all of them.
  # `ai_canonical_teams_seed` (HIER-P4) runs LAST: the "Platform Engineering"
  # canonical Ai::TeamTemplate is materialised for the admin account on top of
  # those lineage edges and delegation rows, so it must see them too.
  puts "\n🤖 Loading fundamental global platform agents (baseline, canonical)..."
  %w[
    claude_agents_seed
    monitoring_analytics_agents_seed
    ai_utility_agents_seed
    ai_concierge_seed
    autonomy_data_seed
    ai_engineering_agents_seed
    platform_skill_assignments_seed
    ai_agent_hierarchy_seed
    ai_canonical_teams_seed
  ].each { |seed_file| safe_load("#{seed_file}.rb") }
end

# ---------------------------------------------------------------------------
# DEMO: account-scoped INSTANCE data (providers, agents, teams, configs).
# Requires at least one account — never runs in baseline-only mode.
# ---------------------------------------------------------------------------
if Powernode::Seeds.demo?
  # NOTE: the fundamental GLOBAL agents (claude_agents / monitoring_analytics /
  # ai_utility_agents / ai_concierge / autonomy_data / platform_skill_assignments)
  # moved to the BASELINE block above — they are canonical platform resources,
  # not demo data. This block keeps DEMO-only instance data + example teams.
  puts "\n🔌 Loading MCP Servers..."
  safe_load('mcp_servers_seeds.rb')

  puts "\n🗄️  Loading File Storage configurations..."
  safe_load('file_storage_seeds.rb')

  puts "\n🔧 Loading AI DevOps Configs (Template Installations + AI Configs)..."
  safe_load('ai_devops_configs_seed.rb')

  puts "\n👥 Loading AI Agent Teams..."
  safe_load('ai_teams_seed.rb')

  puts "\n📋 Loading AI Todo App Team..."
  safe_load('ai_todo_team_seed.rb')

  puts "\n🔧 Loading Powernode Development Team..."
  safe_load('ai_dev_team_seed.rb')

  # Platform-wide skill assignments — re-run here so the DEMO-only agents (dev
  # team, todo team) get their skills too; idempotent with the baseline run above
  # (which assigned the fundamental global agents' skills).
  safe_load('platform_skill_assignments_seed.rb')

  puts "\n🧠 Loading AI Memory Pools..."
  safe_load('ai_memory_pools_seed.rb')

  puts "\n🌐 Loading AI Data Sources..."
  safe_load('ai_data_sources_seed.rb')

  puts "\n🛡️ Loading AI Governance (compliance policies + approval chains)..."
  safe_load('ai_governance_seed.rb')
end

# Extension seeds (dynamically discovered from registered extensions).
# Each extension can opt-in to selective seeding by providing a
# `db/seeds.rb` orchestrator that explicitly lists the files to load.
# This is the preferred pattern — globbing `db/seeds/*.rb` blindly
# inevitably picks up smoke_test_*.rb / example_*.rb files that aren't
# safe to run on every seed cycle (they create resources, hit external
# services, or break with FK violations on teardown).
#
# If no orchestrator is present, fall back to the legacy glob pattern
# for backwards compatibility (extensions that haven't migrated yet).
Powernode::ExtensionRegistry.each do |slug, ext|
  engine_root = ext[:engine].root
  orchestrator = engine_root.join("db", "seeds.rb")
  seeds_dir    = engine_root.join("db", "seeds")

  if File.exist?(orchestrator)
    puts "\n📦 Loading #{slug} extension seeds (via orchestrator)…"
    begin
      load orchestrator
    rescue StandardError => e
      Rails.logger.error("[seeds] #{slug} orchestrator failed: #{e.class}: #{e.message}")
      puts "  ❌ #{slug} orchestrator failed: #{e.message}"
    end
    puts "✅ #{slug.capitalize} extension seeds loaded"
  elsif Dir.exist?(seeds_dir)
    puts "\n📦 Loading #{slug} extension seeds (globbing)…"
    Dir[seeds_dir.join("*.rb")].sort.each do |f|
      load f
    rescue StandardError => e
      Rails.logger.error("[seeds] #{slug}/#{File.basename(f)} failed: #{e.class}: #{e.message}")
      puts "  ⚠️  #{File.basename(f)} failed: #{e.message}"
    end
    puts "✅ #{slug.capitalize} extension seeds loaded"
  end
end

puts "\n🎉 Seeding complete!"
puts "   Permissions: #{Permissions.all_permissions.size}"
puts "   Roles: #{Role.count}"
plan_class = defined?(Billing::Plan) ? Billing::Plan : (defined?(Plan) ? Plan : nil)
puts "   Plans: #{plan_class&.count || 0}"
puts "   Workers: #{Worker.count}"
puts "   Public Pages: #{Page.count}"
puts "   KB Categories: #{KnowledgeBase::Category.count}"
puts "   KB Articles: #{KnowledgeBase::Article.count}"

if Powernode::Seeds.demo?
  puts "   AI Providers: #{Ai::Provider.count}"
  puts "   AI Agents: #{Ai::Agent.count}"
  puts "   DevOps Container Templates: #{Devops::ContainerTemplate.count}"
  puts "   AI DevOps Templates: #{Ai::DevopsTemplate.count}"
  puts "   AI Skills: #{Ai::Skill.count}"
  puts "   AI Agent Templates: #{Ai::AgentTemplate.count}"
  puts "   AI Agent Teams: #{Ai::AgentTeam.count}"
  puts "   AI Memory Pools: #{Ai::MemoryPool.count}"
  puts "   AI Data Sources: #{Ai::DataSource.count}"
end

# 🔧 Create default site settings — resilient like safe_load: one invalid
# setting must never abort the whole seed run (a blank contact_email
# previously raised RecordInvalid here and crash-looped fresh hub installs).
puts "\n🔧 Creating default site settings..."

begin
  # Site information
  SiteSetting.set('site_name', 'Powernode', description: 'Name of the site', setting_type: 'string', is_public: true)
  SiteSetting.set('footer_description', 'Powerful AI management platform for orchestrating production agent fleets. Built for teams shipping with AI.', description: 'Footer description text', setting_type: 'text', is_public: true)

  # Copyright information
  SiteSetting.set('copyright_text', 'Everett C. Haimes III', description: 'Copyright text displayed in footer', setting_type: 'string', is_public: true)
  SiteSetting.set('copyright_year', Date.current.year.to_s, description: 'Copyright year', setting_type: 'string', is_public: true)

  # Contact information
  SiteSetting.set('contact_email', '', description: 'Main contact email (empty — community contact is via GitHub: see footer Contact page)', setting_type: 'string', is_public: true)
  SiteSetting.set('contact_phone', '+1 (555) 123-4567', description: 'Contact phone number', setting_type: 'string', is_public: true)
  SiteSetting.set('company_address', '123 Innovation Drive, Tech City, TC 12345', description: 'Company address', setting_type: 'string', is_public: true)

  # Social media links
  SiteSetting.set('social_twitter', '', description: 'Twitter/X profile URL', setting_type: 'string', is_public: true)
  SiteSetting.set('social_linkedin', '', description: 'LinkedIn profile URL', setting_type: 'string', is_public: true)
  SiteSetting.set('social_facebook', '', description: 'Facebook page URL', setting_type: 'string', is_public: true)
  SiteSetting.set('social_instagram', '', description: 'Instagram profile URL', setting_type: 'string', is_public: true)
  SiteSetting.set('social_youtube', '', description: 'YouTube channel URL', setting_type: 'string', is_public: true)

  # Admin-only settings
  SiteSetting.set('maintenance_mode', 'false', description: 'Enable maintenance mode', setting_type: 'boolean', is_public: false)
  SiteSetting.set('analytics_tracking_id', '', description: 'Google Analytics tracking ID', setting_type: 'string', is_public: false)
  SiteSetting.set('seo_default_title', 'Powernode - AI Management Platform', description: 'Default SEO title', setting_type: 'string', is_public: false)
  SiteSetting.set('seo_default_description', 'Manage production AI agent fleets — knowledge graph, governance, swarm coordination, and an MCP-native runtime.', description: 'Default SEO description', setting_type: 'text', is_public: false)

  # Footer caching
  SiteSetting.set('footer_cache_enabled', 'true', description: 'Enable caching for footer data to improve performance', setting_type: 'boolean', is_public: false)

  puts "✅ Created #{SiteSetting.count} site settings"
rescue StandardError => e
  Rails.logger.error("[seeds] site settings failed: #{e.class}: #{e.message}")
  puts "  ⚠️  site settings failed (#{e.class}: #{e.message}) — continuing"
end


if Powernode::Seeds.demo?
  puts "   Accounts: #{Account.count}"
  puts "   Users: #{User.count}"
  puts "   Site Settings: #{SiteSetting.count}"
end
