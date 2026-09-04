# frozen_string_literal: true

require "rails_helper"

# HIER-P2B-ENG — the Engineering hierarchy as seeded data.
#
# Four NEW core canonicals (Platform Architect, Platform Developer, Release
# Manager, Documentation Specialist) plus the Knowledge Graph Curator and five
# existing canonicals (Research Analyst, Strategic Planner, PRD Generator, LLM
# Judge, System Quality Assurance) form ONE tree under Platform Architect — a
# core ROOT, the way Powernode Assistant is: the core seeds never reach for an
# extension agent, so the system extension's hierarchy seed is what hangs the
# Platform Architect under System Concierge when it is present.
#
# What this file pins, against the seed FILES it loads:
#   * the canonical rule (global, is_system, source_key) for every new agent;
#   * the routing description shape the Claude Code export reads;
#   * the `engineering` policy set — every dev.* / release.* / docs.* category
#     registered in core, the rows on their OWNING agent, the trust-conditioned
#     refine pair (auto_approve only from `trusted`, require_approval below),
#     the release verbs require_approval with no trust unlock, and the
#     account-wide release.build_dispatch floor the agent-less MCP callers need
#     (an operator's mcp_client session, a dev-cell instance principal), written
#     through Ai::Engineering::ReleaseDispatchFloorSeeder so an ESTABLISHED
#     install can land it too — db:seed is first-boot only;
#   * one approval chain per agent, bound to its require_approval rows;
#   * the lineage + delegation rows the hierarchy seed writes through the P1
#     seam (HierarchyWriter): Platform Architect moderate/depth 3 over every
#     Engineering agent type, Platform Developer conservative/depth 1 to the
#     LLM Judge's type only, Release Manager to nobody;
#   * the Claude Code allowlist consequence: the code_assistant carries
#     Edit/Write/Bash and the monitor does not;
#   * idempotency.
module EngineeringAgentSeeds
  PREREQUISITE_SEED_FILES = %w[
    claude_agents_seed.rb
    monitoring_analytics_agents_seed.rb
    ai_utility_agents_seed.rb
    ai_concierge_seed.rb
    autonomy_data_seed.rb
  ].freeze

  ENGINEERING_CHILD_SLUGS = %w[
    platform-developer
    release-manager
    documentation-specialist
    research-analyst
    strategic-planner
    prd-generator
    llm-judge
    system-quality-assurance
    knowledge-graph-curator
  ].freeze

  NEW_CANONICALS = {
    "platform-architect"       => { name: "Platform Architect",       agent_type: "assistant" },
    "platform-developer"       => { name: "Platform Developer",       agent_type: "code_assistant" },
    "release-manager"          => { name: "Release Manager",          agent_type: "monitor" },
    "documentation-specialist" => { name: "Documentation Specialist", agent_type: "content_generator" }
  }.freeze

  ENGINEERING_CATEGORIES = %w[
    dev.task_claim dev.task_complete dev.campaign_propose dev.skill_refine dev.prompt_refine
    release.build_dispatch release.promote release.rollback release.deploy_platform
    docs.update
  ].freeze
end

RSpec.describe "ai_engineering_agents_seed" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let!(:account)   { create(:account, name: "Powernode Admin") }
  let!(:user)      { create(:user, account: account, email: "admin@powernode.org") }
  let!(:anthropic) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }
  let!(:openai)    { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  let!(:ollama)    { create(:ai_provider, account: account, provider_type: "ollama", is_active: true) }
  let!(:grok)      { create(:ai_provider, account: account, provider_type: "custom", is_active: true) }
  let!(:concierge_skill) { create(:ai_skill, account: account, slug: "powernode-concierge", name: "Powernode Concierge") }

  # The slugs platform_skill_assignments_seed binds that the prerequisite
  # seeds above do NOT create (ai_utility_agents_seed creates its own
  # SPECIALIST_SKILLS — extension-developer, ai-agent-architect,
  # agent-autonomy, documentation-writer, technical-researcher — as globals).
  let(:assignment_only_slugs) do
    %w[sre-incident-response devops-engineer security-analyst
       knowledge-system-curator data skill-management business-search
       productivity product-management powernode-dev api-design
       design-skill-from-intent design-agent-team-from-intent
       marketing legal bio-research finance sales customer-support]
  end

  def seed_global_skills!
    assignment_only_slugs.each do |slug|
      next if Ai::Skill.global.exists?(slug: slug)

      create(:ai_skill, account: nil, slug: slug, status: "active",
             name: slug.tr("-", " ").capitalize, category: "productivity")
    end
  end

  def seed_engineering!
    EngineeringAgentSeeds::PREREQUISITE_SEED_FILES.each { |f| load_seed!(f) }
    load_seed!("ai_engineering_agents_seed.rb")
  end

  def seed_all!
    seed_engineering!
    seed_global_skills!
    load_seed!("platform_skill_assignments_seed.rb")
    load_seed!("ai_agent_hierarchy_seed.rb")
  end

  def canonical(slug)
    Ai::Agent.global.find_by(slug: slug)
  end

  def policy_rows(agent, category)
    Ai::InterventionPolicy.where(account: account, ai_agent_id: agent.id, action_category: category, scope: "agent")
  end

  def resolved(agent, category)
    Ai::InterventionPolicyService.new(account: account).resolve(action_category: category, agent: agent)[:policy]
  end

  describe "the canonical rule" do
    before { seed_engineering! }

    it "seeds the four new Engineering agents as GLOBAL, is_system, source_key-managed canonicals" do
      EngineeringAgentSeeds::NEW_CANONICALS.each do |slug, identity|
        agent = canonical(slug)
        expect(agent).to be_present, "#{slug} not seeded as a global canonical"
        aggregate_failures(slug) do
          expect(agent.name).to eq(identity[:name])
          expect(agent.agent_type).to eq(identity[:agent_type])
          expect(agent.is_system).to be(true)
          expect(agent.source_key).to eq(slug)
          expect(agent.status).to eq("active")
          expect(agent.system_prompt).to be_present
          expect(agent.mcp_metadata.dig("model_config", "model_requirements", "tier")).to be_present
        end
      end
    end

    it "marks the Platform Architect as the governance agent of the Engineering team" do
      expect(canonical("platform-architect").is_governance).to be(true)
      expect(canonical("platform-developer").is_governance).to be(false)
    end

    it "keeps the Knowledge Graph Curator a global canonical" do
      expect(canonical("knowledge-graph-curator")).to be_present
    end

    it "writes a routing description the Claude Code export can pin: a 'Use when' trigger, a 'Do not use for' sibling, ≤ 400 chars" do
      EngineeringAgentSeeds::NEW_CANONICALS.each_key do |slug|
        description = canonical(slug).description.to_s
        aggregate_failures(slug) do
          expect(description.length).to be <= Ai::ClaudeExport::RoutingDescription::MAX_CHARS
          expect(description).to match(/Use when\b/)
          expect(description).to match(/Do not use for\b/)
        end
      end
    end

    it "scopes each agent's tool access to REGISTERED action names only" do
      registered = Ai::Tools::PlatformApiToolRegistry.all_tools.keys.map(&:to_s)
      EngineeringAgentSeeds::NEW_CANONICALS.each_key do |slug|
        families = canonical(slug).mcp_metadata.dig("tool_access", "tool_families")
        expect(families).to be_present, "#{slug} declares no tool_families"
        unknown = families.reject { |name| registered.any? { |r| r == name || r.start_with?("#{name}_") } }
        expect(unknown).to be_empty, "#{slug} names tool families matching nothing in the registry: #{unknown.inspect}"
      end
    end

    it "gives the Platform Developer the dev-loop, campaign, code-intelligence and gitea verbs and the Release Manager the build/promote/publish verbs" do
      developer = canonical("platform-developer").mcp_metadata.dig("tool_access", "tool_families")
      expect(developer).to include("dev_next_task", "dev_complete_task", "campaign", "code", "list_gitea_workflows")

      release = canonical("release-manager").mcp_metadata.dig("tool_access", "tool_families")
      expect(release).to include(
        "system_dispatch_module_build_batch", "system_cancel_module_build_batch",
        "system_promote_module_version", "system_rollback_module_version",
        "system_module_mark_canary", "system_unmark_module_canary",
        "system_list_disk_image_publications", "system_set_default_disk_image_publication",
        "system_revert_disk_image", "system_set_disk_image_retention",
        "system_module_publication_integrity", "system_drift_report", "system_list_module_versions"
      )
      expect(release).not_to include("dev_next_task")
    end

    it "bootstraps a trust score BELOW trusted for every new agent (refinements stay gated until earned)" do
      EngineeringAgentSeeds::NEW_CANONICALS.each_key do |slug|
        score = Ai::AgentTrustScore.find_by(agent_id: canonical(slug).id)
        expect(score).to be_present, "#{slug} has no trust score"
        expect(%w[supervised monitored]).to include(score.tier)
      end
    end
  end

  describe "the engineering policy set" do
    it "registers every dev.* / release.* / docs.* category in core (where ai.delegation_policy.update registers)" do
      EngineeringAgentSeeds::ENGINEERING_CATEGORIES.each do |category|
        expect(Ai::InterventionPolicy.category_registered?(category)).to be(true), "#{category} is not a registered category"
        expect(Ai::InterventionPolicy::STATIC_CATEGORIES).to include(category)
      end
    end

    context "after seeding" do
      before { seed_engineering! }

      let(:developer)  { canonical("platform-developer") }
      let(:architect)  { canonical("platform-architect") }
      let(:release)    { canonical("release-manager") }
      let(:documenter) { canonical("documentation-specialist") }

      it "auto-approves the Platform Developer's claim, completion and campaign proposals" do
        %w[dev.task_claim dev.task_complete dev.campaign_propose].each do |category|
          rows = policy_rows(developer, category)
          expect(rows.count).to eq(1), "#{category}: expected one row, got #{rows.count}"
          expect(rows.first.policy).to eq("auto_approve")
          expect(rows.first.is_active).to be(true)
          expect(resolved(developer, category)).to eq("auto_approve")
        end
      end

      it "writes the trust-conditioned refine pair on the Platform Developer AND the Platform Architect" do
        [ developer, architect ].each do |agent|
          %w[dev.skill_refine dev.prompt_refine].each do |category|
            rows = policy_rows(agent, category).order(priority: :desc)
            expect(rows.map(&:policy)).to eq(%w[auto_approve require_approval]),
                                          "#{agent.slug} #{category}: #{rows.map(&:policy).inspect}"
            expect(rows.first.conditions).to eq({ "trust_tier_minimum" => "trusted" })
            expect(rows.last.conditions).to eq({})
            expect(rows.first.priority).to be > rows.last.priority
          end
        end
      end

      it "resolves a refine to require_approval below trusted and to auto_approve from trusted (existing conditions mechanism)" do
        score = Ai::AgentTrustScore.find_by(agent_id: developer.id)
        expect(score.tier).not_to eq("trusted")
        expect(resolved(developer, "dev.skill_refine")).to eq("require_approval")
        expect(resolved(developer, "dev.prompt_refine")).to eq("require_approval")

        score.update!(tier: "trusted", overall_score: 0.75)
        expect(resolved(developer, "dev.skill_refine")).to eq("auto_approve")
        expect(resolved(developer, "dev.prompt_refine")).to eq("auto_approve")
      end

      it "auto-approves the Platform Architect's campaign proposals (proposals are the gate)" do
        expect(policy_rows(architect, "dev.campaign_propose").pick(:policy)).to eq("auto_approve")
      end

      it "gates every release promote/rollback/deploy behind approval — with NO trust unlock, even at autonomous" do
        %w[release.promote release.rollback release.deploy_platform].each do |category|
          rows = policy_rows(release, category)
          expect(rows.count).to eq(1)
          expect(rows.first.policy).to eq("require_approval")
          expect(rows.first.conditions).to eq({})
          expect(rows.first.approval_chain).to be_present
        end

        Ai::AgentTrustScore.find_by(agent_id: release.id).update!(tier: "autonomous", overall_score: 0.95)
        expect(resolved(release, "release.deploy_platform")).to eq("require_approval")
        expect(resolved(release, "release.promote")).to eq("require_approval")
        expect(resolved(release, "release.rollback")).to eq("require_approval")
      end

      it "auto-approves build dispatch on the Release Manager AND as an account-wide floor (MCP callers are agent-less)" do
        expect(policy_rows(release, "release.build_dispatch").pick(:policy)).to eq("auto_approve")

        floor = Ai::InterventionPolicy.where(account: account, action_category: "release.build_dispatch", scope: "global", ai_agent_id: nil)
        expect(floor.count).to eq(1)
        expect(floor.first.policy).to eq("auto_approve")
        # An agent-less caller — an operator's mcp_client session, a dev-cell
        # instance principal — resolves the floor; the Release Manager resolves
        # its own row.
        expect(Ai::InterventionPolicyService.new(account: account).resolve(action_category: "release.build_dispatch")[:policy]).to eq("auto_approve")
        expect(resolved(release, "release.build_dispatch")).to eq("auto_approve")
      end

      it "auto-approves the Documentation Specialist's docs.update" do
        expect(policy_rows(documenter, "docs.update").pick(:policy)).to eq("auto_approve")
      end

      it "writes one active autonomy_action approval chain per Engineering agent" do
        [ architect, developer, release, documenter ].each do |agent|
          chain = Ai::ApprovalChain.find_by(account: account, name: "#{agent.name} Actions")
          expect(chain).to be_present, "no chain for #{agent.name}"
          expect(chain.trigger_type).to eq("autonomy_action")
          expect(chain.status).to eq("active")
          expect(chain.steps.first["approvers"]).to be_present
        end
      end

      it "never writes an engineering row on an agent that does not own the category" do
        expect(policy_rows(release, "dev.task_claim")).to be_empty
        expect(policy_rows(developer, "release.promote")).to be_empty
        expect(policy_rows(documenter, "dev.skill_refine")).to be_empty
        expect(policy_rows(architect, "dev.task_claim")).to be_empty
      end
    end
  end

  describe "skill bindings through platform_skill_assignments_seed" do
    before { seed_all! }

    it "binds the Platform Architect to the four design skills" do
      slugs = canonical("platform-architect").skills.pluck(:slug)
      expect(slugs).to include("ai-agent-architect", "design-agent-team-from-intent", "skill-management", "agent-autonomy")
    end

    it "binds the Platform Developer to Extension Developer and the Documentation Specialist to the documentation skills" do
      expect(canonical("platform-developer").skills.pluck(:slug)).to include("extension-developer")
      # api-design included: the promoted canonical keeps ALL FOUR bindings the
      # demo dev-team seed gave it, not three of them.
      expect(canonical("documentation-specialist").skills.pluck(:slug))
        .to include("documentation-writer", "knowledge-system-curator", "product-management", "api-design")
    end
  end

  describe "the Engineering lineage (ai_agent_hierarchy_seed)" do
    before { seed_all! }

    let(:architect) { canonical("platform-architect") }
    let(:assistant) { canonical("powernode-assistant") }

    it "makes the Platform Architect a core ROOT (the extension attaches it under System Concierge, never the core seed)" do
      expect(Ai::AgentLineage.for_child(architect.id).active).to be_empty
      expect(architect.parent_agent_id).to be_nil
    end

    it "attaches every Engineering agent under the Platform Architect with exactly one active seed edge" do
      EngineeringAgentSeeds::ENGINEERING_CHILD_SLUGS.each do |slug|
        child = canonical(slug)
        expect(child).to be_present, "#{slug} missing"
        edges = Ai::AgentLineage.for_child(child.id).active
        aggregate_failures(slug) do
          expect(edges.count).to eq(1)
          expect(edges.first.parent_agent_id).to eq(architect.id)
          expect(edges.first.spawn_reason).to eq("seed")
          expect(child.reload.parent_agent_id).to eq(architect.id)
        end
      end
    end

    it "re-parents the six existing canonicals off Powernode Assistant (one active parent per child)" do
      %w[research-analyst strategic-planner prd-generator llm-judge system-quality-assurance knowledge-graph-curator].each do |slug|
        child = canonical(slug)
        expect(Ai::AgentLineage.for_child(child.id).active.where(parent_agent_id: assistant.id)).to be_empty, "#{slug} still hangs under Powernode Assistant"
      end
    end

    it "keeps the rest of the core forest under Powernode Assistant" do
      %w[system-performance-monitor intent-classifier rag-reranker].each do |slug|
        child = canonical(slug)
        expect(Ai::AgentLineage.for_child(child.id).active.pluck(:parent_agent_id)).to eq([ assistant.id ])
      end
    end

    it "gives the Platform Architect a moderate, depth-3 policy that may delegate to every Engineering agent type" do
      policy = Ai::DelegationPolicy.resolve_for(agent_id: architect.id, account_id: account.id)
      expect(policy.inheritance_policy).to eq("moderate")
      expect(policy.max_depth).to eq(3)
      child_types = EngineeringAgentSeeds::ENGINEERING_CHILD_SLUGS.map { |s| canonical(s).agent_type }.uniq.sort
      expect(policy.allowed_delegate_types.sort).to eq(child_types)
      child_types.each { |type| expect(policy.allows_delegate_type?(type)).to be(true) }
    end

    it "lets the Platform Developer delegate review to the LLM Judge's type only, depth 1, conservative" do
      policy = Ai::DelegationPolicy.resolve_for(agent_id: canonical("platform-developer").id, account_id: account.id)
      expect(policy.inheritance_policy).to eq("conservative")
      expect(policy.max_depth).to eq(1)
      expect(policy.allowed_delegate_types).to eq([ canonical("llm-judge").agent_type ])
      expect(policy.allows_delegate_type?("code_assistant")).to be(false)
    end

    it "lets the Release Manager delegate to nobody" do
      policy = Ai::DelegationPolicy.resolve_for(agent_id: canonical("release-manager").id, account_id: account.id)
      expect(policy.inheritance_policy).to eq("conservative")
      Ai::Agent.global.pluck(:agent_type).uniq.each do |type|
        expect(policy.allows_delegate_type?(type)).to be(false), "Release Manager may delegate to #{type}"
      end
    end

    it "leaves the other Engineering children on the P1 leaf policy" do
      %w[documentation-specialist research-analyst llm-judge].each do |slug|
        policy = Ai::DelegationPolicy.resolve_for(agent_id: canonical(slug).id, account_id: account.id)
        expect(policy.inheritance_policy).to eq("conservative")
        expect(policy.max_depth).to eq(1)
      end
    end
  end

  describe "the Claude Code export consequence" do
    before { seed_engineering! }

    it "hands the code_assistant Edit/Write/Bash and withholds them from the monitor" do
      registry = Ai::ClaudeExport::ToolAllowlist::Registry.snapshot
      developer_tools = Ai::ClaudeExport::ToolAllowlist.for(canonical("platform-developer"), registry: registry)
      release_tools   = Ai::ClaudeExport::ToolAllowlist.for(canonical("release-manager"), registry: registry)

      expect(developer_tools).to include("Edit", "Write", "Bash")
      expect(release_tools).not_to include("Edit", "Write", "Bash")
      expect(release_tools).to include("Read", "Grep", "Glob")
    end
  end

  it "is idempotent: a re-run adds no agent, policy, chain, trust score, edge or delegation row" do
    seed_all!
    counts = -> {
      [ Ai::Agent.count, Ai::InterventionPolicy.count, Ai::ApprovalChain.count, Ai::AgentTrustScore.count,
        Ai::AgentLineage.count, Ai::DelegationPolicy.count, Ai::AgentSkill.count ]
    }
    before = counts.call

    load_seed!("ai_engineering_agents_seed.rb")
    load_seed!("platform_skill_assignments_seed.rb")
    load_seed!("ai_agent_hierarchy_seed.rb")

    expect(counts.call).to eq(before)
  end

  # IMP-6cda93db7f31: a canonical row needs no account (creator and provider
  # are optional on a global row), so before setup the four canonicals ARE
  # written; only the account-keyed rows (trust score, approval chain, policy
  # rows) wait. spec/db/seeds/core_canonicals_without_users_spec.rb pins the
  # same on a database with no user at all.
  it "seeds the canonicals before setup (no admin account yet) and defers the account-keyed rows" do
    allow(Account).to receive(:find_by).and_call_original
    allow(Account).to receive(:find_by).with(name: "Powernode Admin").and_return(nil)

    expect { load_seed!("ai_engineering_agents_seed.rb") }.not_to raise_error

    architect = Ai::Agent.global.find_by(slug: "platform-architect")
    expect(architect).to be_present
    # No admin account ⇒ no admin user to be the creator; the provider is
    # whichever exists (here the let! providers) and is optional either way.
    expect(architect.creator).to be_nil
    expect(Ai::AgentTrustScore.where(agent_id: architect.id)).to be_empty
    expect(Ai::ApprovalChain.where(name: "Platform Architect Actions")).to be_empty
    expect(Ai::InterventionPolicy.where(ai_agent_id: architect.id)).to be_empty
  end
end
