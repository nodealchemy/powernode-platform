# frozen_string_literal: true

require "rails_helper"

# Frontmatter `description` is YAML-dumped (Psych folds/quotes long plain scalars
# across multiple physical lines), so multi-word assertions against it go through
# #frontmatter_of (parses the block, reconstructing the original unwrapped string)
# rather than a raw substring match against the file. The BODY is plain
# interpolated text (never YAML-dumped) so raw substring/include? checks against it
# are safe.
RSpec.describe Ai::ClaudeExport::AgentSkeletonSync, type: :service do
  let(:account) { create(:account) }
  let(:target_dir) { Dir.mktmpdir("claude-agent-sync-spec") }
  subject(:service) { described_class.new(account: account, target_dir: target_dir) }

  after { FileUtils.remove_entry(target_dir) if File.exist?(target_dir) }

  def build_agent(name:, resolved_model:, description: "Does helpful things.", skills: [], **attrs)
    agent = create(:ai_agent, account: account, name: name, description: description, **attrs)
    allow(agent).to receive(:resolved_model).and_return(resolved_model)
    skills.each do |slug|
      skill = create(:ai_skill, account: account, slug: slug)
      create(:ai_agent_skill, agent: agent, skill: skill, is_active: true)
    end
    agent
  end

  def build_canonical(name:, **attrs)
    create(:ai_agent, :global, name: name, is_system: true, **attrs)
  end

  def stub_syncable(agents)
    allow(service).to receive(:syncable_agents).and_return(agents)
  end

  # No factory exists for Ai::InterventionPolicy; the row shape mirrors the
  # extension seeds' agent-scoped policies (scope "agent", one action_category).
  def policy_for(agent, category)
    Ai::InterventionPolicy.create!(account: account, agent: agent, scope: "agent",
                                   action_category: category, policy: "require_approval", priority: 10)
  end

  def path_for(agent)
    File.join(target_dir, "#{agent.slug}.md")
  end

  def content_for(agent)
    File.read(path_for(agent))
  end

  def frontmatter_of(content)
    _, fm, = content.split(/^---$/, 3)
    YAML.safe_load(fm)
  end

  # The bootstrap verbs (get_agent / get_skill_context) are ALWAYS in the
  # `tools:` frontmatter; the body-shape examples ask about the numbered STEP.
  def body_of(content)
    content.split(/^---$/, 3).last
  end

  # Canonical rule (HIER-P1B, operator direction 2026-09-03): official agents are
  # GLOBAL seeded canonicals and the platform is the source of truth. The
  # committed export is the canonical set ONLY; an account's own rows (clones,
  # own agents) are exported only on explicit request, into a separate ignored
  # directory, so a committed file is never wrong on another install.
  describe "#syncable_agents" do
    context "canonical scope (no account — the committed set)" do
      subject(:service) { described_class.new(target_dir: target_dir) }

      it "includes GLOBAL is_system agents only" do
        canonical = build_canonical(name: "Canonical Helper")
        own_agent = create(:ai_agent, account: account, name: "My Own Agent")
        non_system_global = create(:ai_agent, :global, name: "Ad-hoc Global", is_system: false)

        slugs = service.send(:syncable_agents).map(&:slug)

        expect(slugs).to include(canonical.slug)
        expect(slugs).not_to include(own_agent.slug)
        expect(slugs).not_to include(non_system_global.slug)
      end

      it "excludes inactive canonicals" do
        inactive = build_canonical(name: "Paused Canonical", status: "inactive")

        expect(service.send(:syncable_agents).map(&:slug)).not_to include(inactive.slug)
      end

      it "excludes mcp_client agents (ephemeral CC-session identities, not executable platform agents — " \
         "AgentToolBridgeService#tools_enabled? draws the same line)" do
        mcp_client_agent = create(:ai_agent, :global, :mcp_client, is_system: true)

        expect(service.send(:syncable_agents).map(&:slug)).not_to include(mcp_client_agent.slug)
      end

      it "targets .claude/agents/powernode by default" do
        expect(described_class.new.send(:default_target_dir).to_s).to end_with("/.claude/agents/powernode")
      end
    end

    context "account scope (explicit ACCOUNT_ID — the local, ignored set)" do
      it "includes the account's own active agents and never the canonicals" do
        canonical = build_canonical(name: "Canonical Helper")
        own_agent = create(:ai_agent, account: account, name: "My Own Agent")

        slugs = service.send(:syncable_agents).map(&:slug)

        expect(slugs).to include(own_agent.slug)
        expect(slugs).not_to include(canonical.slug)
      end

      it "excludes inactive and other accounts' agents" do
        inactive_own = create(:ai_agent, :inactive, account: account, name: "Paused Agent")
        other_agent = create(:ai_agent, account: create(:account), name: "Someone Else's Agent")

        slugs = service.send(:syncable_agents).map(&:slug)

        expect(slugs).not_to include(inactive_own.slug, other_agent.slug)
      end

      it "exports an account clone of a canonical (same slug) as the account's row" do
        canonical = build_canonical(name: "Code Reviewer", description: "Global default.")
        override = create(:ai_agent, account: account, name: "Code Reviewer", description: "Account override.")
        expect(override.slug).to eq(canonical.slug) # sanity: same name -> same slug across scope partitions

        matches = service.send(:syncable_agents).select { |a| a.slug == override.slug }

        expect(matches.map(&:id)).to eq([ override.id ])
      end

      it "targets .claude/agents/powernode-local by default" do
        expect(described_class.new(account: account).send(:default_target_dir).to_s)
          .to end_with("/.claude/agents/powernode-local")
      end
    end
  end

  describe "frontmatter model mapping" do
    {
      light: %w[claude-haiku-4-5-20251001 haiku],
      standard: %w[claude-sonnet-4-6 sonnet],
      reasoning: %w[claude-opus-4-8 opus],
      frontier: %w[claude-fable-5 fable]
    }.each do |tier, (model_id, cc_model)|
      it "maps #{tier}-tier resolved_model (#{model_id}) to CC frontmatter model \"#{cc_model}\"" do
        agent = build_agent(name: "Tier #{tier} Agent", resolved_model: model_id)
        stub_syncable([ agent ])

        service.sync!

        expect(frontmatter_of(content_for(agent))["model"]).to eq(cc_model)
      end
    end

    # Item 1 (environment independence): a COMMITTED canonical file must render
    # the same on every install, so in canonical scope the tier comes from the
    # agent's DECLARED requirement (what the seed states) or its pinned model —
    # never from resolved_model, which depends on THIS install's providers.
    it "derives the canonical-scope tier from the declared model_requirements, never from resolved_model" do
      declared = build_canonical(name: "Declared Reasoner",
                                 mcp_metadata: { "model_config" => { "model_requirements" => { "tier" => "reasoning" } } })
      # update_columns: Ai::Agent's auto_resolve_provider_from_model callback
      # resolves a pinned model through the owning ACCOUNT's providers, which a
      # global row has none of — the pin is a seed-time fact, not under test here.
      pinned = build_canonical(name: "Pinned Light")
      pinned.update_columns(mcp_metadata: { "model_config" => { "model" => "claude-haiku-4-5-20251001" } })
      bare = build_canonical(name: "Bare Canonical")
      [ declared, pinned, bare ].each { |a| allow(a).to receive(:resolved_model).and_return("claude-fable-5") }
      canonical_service = described_class.new(target_dir: target_dir)
      allow(canonical_service).to receive(:syncable_agents).and_return([ declared, pinned, bare ])

      canonical_service.sync!

      expect(frontmatter_of(content_for(declared))["model"]).to eq("opus")
      expect(frontmatter_of(content_for(pinned))["model"]).to eq("haiku")
      expect(frontmatter_of(content_for(bare))["model"]).to eq("sonnet")
      [ declared, pinned, bare ].each { |a| expect(a).not_to have_received(:resolved_model) }
    end

    it "maps frontier UNCONDITIONALLY to fable even when the platform Fable gate is OFF " \
       "(campaign 019f2163 inc5 directive — CC-side Fable rides the CC entitlement, " \
       "independent of Ai::FableRouting)" do
      allow(Ai::FableRouting).to receive(:enabled_for?).and_return(false)
      allow(Ai::FableRouting).to receive(:fable_model?).and_call_original

      agent = build_agent(name: "Frontier Agent", resolved_model: "claude-fable-5")
      stub_syncable([ agent ])

      service.sync!

      expect(frontmatter_of(content_for(agent))["model"]).to eq("fable")
      expect(Ai::FableRouting).not_to have_received(:enabled_for?)
    end
  end

  # Claude Code's Agent tool picks a subagent_type from each definition's
  # `description`, so the exported description MUST be a routing description
  # (trigger + exclusion), not a blurb — item 9 of HIER-P1B.
  describe "routing description" do
    it "renders a 'Use this agent when …' trigger and a 'Do not use for …' exclusion" do
      agent = build_agent(name: "Router Target", resolved_model: "claude-sonnet-4-6",
                          description: "Reconciles fleet drift and rotates certificates.")
      stub_syncable([ agent ])

      service.sync!
      description = frontmatter_of(content_for(agent))["description"]

      expect(description).to start_with("Use this agent when")
      expect(description).to include("Do not use for")
    end

    it "names the sibling that owns the adjacent domain in the exclusion" do
      sdwan = build_agent(name: "SDWAN Manager", resolved_model: "claude-sonnet-4-6",
                          description: "Manages SD-WAN peers and route policies.")
      fleet = build_agent(name: "Fleet Autonomy", resolved_model: "claude-sonnet-4-6",
                          description: "Reconciles node and module drift.")
      policy_for(sdwan, "system.sdwan_create_peer")
      policy_for(fleet, "system.module_drift_remediate")
      stub_syncable([ sdwan, fleet ])

      service.sync!

      expect(frontmatter_of(content_for(sdwan))["description"]).to include("`#{fleet.slug}`")
      expect(frontmatter_of(content_for(fleet))["description"]).to include("`#{sdwan.slug}`")
    end
  end

  describe "when-to-spawn description guidance" do
    it "articulates when to spawn vs a cheaper agent for reasoning-tier" do
      agent = build_agent(name: "Reasoner", resolved_model: "claude-opus-4-8")
      stub_syncable([ agent ])

      service.sync!
      description = frontmatter_of(content_for(agent))["description"]

      expect(description).to include("REASONING-tier")
      expect(description).to include("prefer a cheaper agent")
    end

    it "articulates when to spawn vs a cheaper agent, more strictly, for frontier-tier" do
      agent = build_agent(name: "Frontiersman", resolved_model: "claude-fable-5")
      stub_syncable([ agent ])

      service.sync!
      description = frontmatter_of(content_for(agent))["description"]

      expect(description).to include("FRONTIER-tier")
      expect(description).to include("exception, not the default")
    end

    it "does not add spawn-threshold guidance for light/standard tiers" do
      agent = build_agent(name: "Light Helper", resolved_model: "claude-haiku-4-5-20251001")
      stub_syncable([ agent ])

      service.sync!
      description = frontmatter_of(content_for(agent))["description"]

      expect(description).to start_with("Use this agent when")
      expect(description).not_to include("-tier (")
    end
  end

  # Item 3: the `tools:` allowlist is derived from the agent's tool access by
  # Ai::ClaudeExport::ToolAllowlist (one place); CC's frontmatter form is a
  # comma-separated string.
  describe "tools frontmatter" do
    def tools_of(agent)
      frontmatter_of(content_for(agent))["tools"].to_s.split(",").map(&:strip)
    end

    it "carries the read-only built-ins, the bootstrap verbs and the platform read verbs for a scope-less assistant" do
      agent = build_agent(name: "Scopeless Assistant", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      tools = tools_of(agent)

      expect(tools).to include("Read", "Grep", "Glob")
      expect(tools).not_to include("Edit", "Write", "Bash")
      expect(tools).to include("mcp__powernode__platform_get_agent", "mcp__powernode__platform_get_skill_context")
      expect(tools).to include("mcp__powernode__platform_list_agents")
      expect(tools).not_to include("mcp__powernode__platform_delete_agent")
    end

    it "adds Edit/Write/Bash only for code_assistant agents" do
      agent = build_agent(name: "Coder", resolved_model: "claude-sonnet-4-6", agent_type: "code_assistant")
      stub_syncable([ agent ])

      service.sync!

      expect(tools_of(agent)).to include("Edit", "Write", "Bash")
    end

    it "omits `tools:` (inherit everything) for a full_registry agent" do
      agent = build_agent(name: "Orchestrator", resolved_model: "claude-sonnet-4-6",
                          mcp_metadata: { "tool_access" => { "full_registry" => true } })
      stub_syncable([ agent ])

      service.sync!

      expect(frontmatter_of(content_for(agent))).not_to have_key("tools")
    end
  end

  describe "body shape" do
    it "bootstraps by SLUG (stable across installs), never by the per-install UUID" do
      agent = build_agent(name: "Bootstrapped Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      content = content_for(agent)

      expect(content).to include("mcp__powernode__platform_get_agent")
      expect(content).to include(%(slug: "#{agent.slug}"))
      expect(content).not_to include(agent.id)
      expect(content).to include("source of truth")
    end

    it "references get_skill_context with attached skill slugs, keyed on the id returned by get_agent" do
      agent = build_agent(name: "Skilled Agent", resolved_model: "claude-sonnet-4-6",
                           skills: %w[skill-alpha skill-beta])
      stub_syncable([ agent ])

      service.sync!
      content = content_for(agent)

      expect(content).to include("mcp__powernode__platform_get_skill_context")
      expect(content).not_to include(agent.id)
      expect(content).to include("skill-alpha")
      expect(content).to include("skill-beta")
    end

    it "omits the get_skill_context step when the agent has no active skills" do
      agent = build_agent(name: "Skill-less Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!

      expect(body_of(content_for(agent))).not_to include("mcp__powernode__platform_get_skill_context")
    end

    it "ignores an inactive skill attachment (not listed, get_skill_context step omitted)" do
      agent = build_agent(name: "Half-Skilled Agent", resolved_model: "claude-sonnet-4-6")
      skill = create(:ai_skill, account: account, slug: "skill-gamma", status: "active")
      create(:ai_agent_skill, agent: agent, skill: skill, is_active: false)
      stub_syncable([ agent ])

      service.sync!
      content = body_of(content_for(agent))

      expect(content).not_to include("skill-gamma")
      expect(content).not_to include("mcp__powernode__platform_get_skill_context")
    end

    it "carries the state-why-frontier-is-needed governance line ONLY in fable bodies" do
      fable_agent = build_agent(name: "Fable Agent", resolved_model: "claude-fable-5")
      sonnet_agent = build_agent(name: "Sonnet Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ fable_agent, sonnet_agent ])

      service.sync!

      fable_content = content_for(fable_agent)
      sonnet_content = content_for(sonnet_agent)

      expect(fable_content).to include("state in one sentence why frontier capability is required")
      expect(fable_content).to include("do not refuse")
      expect(sonnet_content).not_to include("state in one sentence why frontier capability is required")
    end

    # Item 4: Ai::Agent::BASE_GUARDRAILS is the always-on floor. The fetched
    # prompt already prepends it natively (Ai::Agent#system_prompt), so the body
    # says so rather than reading as duplication.
    it "carries BASE_GUARDRAILS verbatim, noting the fetched prompt already prepends them" do
      agent = build_agent(name: "Guarded Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      content = content_for(agent)

      expect(content).to include(Ai::Agent::BASE_GUARDRAILS)
      expect(content).to include("already")
    end

    # HIER-P1C item 4(b): the self-report is the fallback when the SubagentStop
    # hook is disabled. It names the verb, the slug, and the run_key contract
    # the hook reuses (the hook copies a self-report's run_key out of the
    # transcript), so the platform sees ONE row either way.
    it "ends with the record_agent_execution self-report instruction, before returning, keyed on the slug" do
      agent = build_agent(name: "Reporting Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      body = body_of(content_for(agent))

      expect(body).to include("mcp__powernode__platform_record_agent_execution")
      expect(body).to include(%(agent_slug: "#{agent.slug}"))
      expect(body).to include("run_key")
      expect(body).to include("CLAUDE_CODE_SESSION_ID")
      expect(body).to match(/before returning/i)
      expect(body.index("record_agent_execution")).to be > body.index("source of truth")
      # It is the last numbered step: after it comes the guardrails floor only.
      expect(body.index("record_agent_execution")).to be < body.index("## Baseline guardrails")
    end

    it "allows the self-report verb in the tools frontmatter" do
      agent = build_agent(name: "Allowed Reporter", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      expect(frontmatter_of(content_for(agent))["tools"]).to include("mcp__powernode__platform_record_agent_execution")
    end
  end

  # Item 4: delegation authority (Ai::DelegationPolicy, seeded by HIER-P1) and
  # the lineage parent, so a CC subagent knows whom it reports to and whom it may
  # delegate to. Rendered only when something exists.
  describe "delegation section" do
    it "renders the delegation policy: delegate types, max depth, inheritance" do
      agent = build_agent(name: "Delegator", resolved_model: "claude-sonnet-4-6")
      create(:ai_delegation_policy, account: account, agent: agent, max_depth: 2,
             allowed_delegate_types: %w[assistant monitor], inheritance_policy: "moderate")
      stub_syncable([ agent ])

      service.sync!
      content = content_for(agent)

      expect(content).to include("## Delegation")
      expect(content).to include("May delegate to: assistant, monitor")
      expect(content).to include("Max delegation depth: 2")
      expect(content).to include("Inheritance: moderate")
    end

    it "renders 'any agent type' when the policy lists no delegate types" do
      agent = build_agent(name: "Open Delegator", resolved_model: "claude-sonnet-4-6")
      create(:ai_delegation_policy, account: account, agent: agent, allowed_delegate_types: [])
      stub_syncable([ agent ])

      service.sync!

      expect(content_for(agent)).to include("May delegate to: any agent type")
    end

    it "renders the lineage parent as 'Reports to' (parent_agent column or an active AgentLineage)" do
      parent = build_agent(name: "Parent Agent", resolved_model: "claude-sonnet-4-6")
      via_column = build_agent(name: "Child By Column", resolved_model: "claude-sonnet-4-6", parent_agent: parent)
      via_lineage = build_agent(name: "Child By Lineage", resolved_model: "claude-sonnet-4-6")
      Ai::AgentLineage.create!(account: account, parent_agent: parent, child_agent: via_lineage, spawned_at: Time.current)
      stub_syncable([ via_column, via_lineage ])

      service.sync!

      expect(content_for(via_column)).to include("Reports to: `#{parent.slug}`")
      expect(content_for(via_lineage)).to include("Reports to: `#{parent.slug}`")
    end

    it "renders no Delegation section when the agent has neither a policy nor a parent" do
      agent = build_agent(name: "Lone Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!

      expect(content_for(agent)).not_to include("## Delegation")
    end
  end

  describe "file hygiene" do
    it "prefixes the body with the generated-file header" do
      agent = build_agent(name: "Headered Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!

      expect(content_for(agent)).to include(
        "<!-- generated by claude:sync_agents — do not edit; regenerate instead -->"
      )
    end
  end

  describe "idempotency" do
    it "writes zero files on a second run over unchanged agents" do
      agent = build_agent(name: "Stable Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      first = service.sync!
      expect(first.written).to eq([ agent.slug ])
      expect(first.unchanged).to eq([])

      second = service.sync!
      expect(second.written).to eq([])
      expect(second.unchanged).to eq([ agent.slug ])
    end

    it "rewrites only the file whose content actually changed" do
      stable = build_agent(name: "Stable Agent", resolved_model: "claude-sonnet-4-6")
      changing = build_agent(name: "Changing Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ stable, changing ])
      service.sync!

      allow(changing).to receive(:description).and_return("A brand new description about wholly different work.")
      second = service.sync!

      expect(second.written).to eq([ changing.slug ])
      expect(second.unchanged).to eq([ stable.slug ])
    end
  end

  # The COMMITTED canonical files are diffed byte-for-byte by
  # scripts/check-claude-agents-fresh.sh, so nothing account-scoped may reach
  # them: ai_delegation_policies / ai_intervention_policies / ai_agent_lineages
  # all carry a NOT NULL account_id, and the seeds key them on the platform
  # admin account. A canonical render that read them would publish one tenant's
  # governance configuration and fail the gate on any install with a second
  # account.
  describe "canonical scope reads only globally-scoped rows" do
    subject(:canonical_service) { described_class.new(target_dir: target_dir) }

    let(:other_account) { create(:account) }

    def stub_canonical(agents)
      allow(canonical_service).to receive(:syncable_agents).and_return(agents)
    end

    it "renders no delegation policy, whichever account holds one" do
      agent = build_canonical(name: "Canonical Delegator")
      create(:ai_delegation_policy, account: account, agent: agent, max_depth: 2,
             allowed_delegate_types: %w[assistant], inheritance_policy: "moderate")
      create(:ai_delegation_policy, account: other_account, agent: agent, max_depth: 9,
             allowed_delegate_types: %w[monitor], inheritance_policy: "permissive")
      stub_canonical([ agent ])

      canonical_service.sync!
      content = content_for(agent)

      expect(content).not_to include("May delegate to")
      expect(content).not_to include("Max delegation depth")
      expect(content).not_to include("Inheritance:")
    end

    it "renders no intervention-policy domain in the description" do
      agent = build_canonical(name: "Canonical Domained", description: "Handles storage.")
      Ai::InterventionPolicy.create!(account: other_account, agent: agent, scope: "agent",
                                     action_category: "system.sdwan_create_peer",
                                     policy: "require_approval", priority: 10)
      stub_canonical([ agent ])

      canonical_service.sync!

      expect(frontmatter_of(content_for(agent))["description"]).not_to include("sdwan")
    end

    it "reports to the parent_agent column but never to an account's lineage edge" do
      parent = build_canonical(name: "Canonical Parent")
      via_column = build_canonical(name: "Canonical Child By Column", parent_agent: parent)
      via_lineage = build_canonical(name: "Canonical Child By Lineage")
      Ai::AgentLineage.create!(account: other_account, parent_agent: parent,
                               child_agent: via_lineage, spawned_at: Time.current)
      stub_canonical([ parent, via_column, via_lineage ])

      canonical_service.sync!

      expect(content_for(via_column)).to include("Reports to: `#{parent.slug}`")
      expect(content_for(via_lineage)).not_to include("Reports to")
    end

    it "ignores an account's own skill bound to a canonical agent" do
      agent = build_canonical(name: "Canonical Skilled")
      global_skill = create(:ai_skill, account: nil, slug: "global-capability", name: "Global Capability")
      local_skill = create(:ai_skill, account: other_account, slug: "tenant-capability", name: "Tenant Capability")
      create(:ai_agent_skill, agent: agent, skill: global_skill, is_active: true)
      create(:ai_agent_skill, agent: agent, skill: local_skill, is_active: true)
      stub_canonical([ agent ])

      canonical_service.sync!
      content = content_for(agent)

      expect(content).to include("global-capability")
      expect(content).not_to include("tenant-capability")
    end
  end

  # allowed_delegate_types is matched against Ai::Agent#agent_type by every
  # reader (Ai::DelegationPolicy#allows_delegate_type?, and the router's pool
  # filter). A row naming skill slugs does not narrow delegation, it refuses all
  # of it — the file has to say so rather than advertise a surface that cannot
  # fire.
  describe "delegate types that are not agent types" do
    it "names them and states what the policy actually allows" do
      agent = build_agent(name: "Skill Slug Delegator", resolved_model: "claude-sonnet-4-6")
      create(:ai_delegation_policy, account: account, agent: agent,
             allowed_delegate_types: %w[system-federation-manager assistant])
      stub_syncable([ agent ])

      service.sync!
      content = content_for(agent)

      expect(content).to include("May delegate to: system-federation-manager, assistant")
      expect(content).to include("system-federation-manager is not an agent type")
      expect(content).to include("allows only assistant")
    end

    it "says NO agent type at all when every entry is unknown" do
      agent = build_agent(name: "Broken Delegator", resolved_model: "claude-sonnet-4-6")
      create(:ai_delegation_policy, account: account, agent: agent,
             allowed_delegate_types: %w[system-sdwan-failover system-federation-acceptance])
      stub_syncable([ agent ])

      service.sync!

      expect(content_for(agent)).to include("allows NO agent type at all")
    end

    it "stays silent for a policy whose entries are all real agent types" do
      agent = build_agent(name: "Sound Delegator", resolved_model: "claude-sonnet-4-6")
      create(:ai_delegation_policy, account: account, agent: agent,
             allowed_delegate_types: %w[assistant monitor])
      stub_syncable([ agent ])

      service.sync!

      expect(content_for(agent)).not_to include("is not an agent type")
    end
  end

  describe "stale cleanup" do
    it "removes a generated-header file for an agent no longer syncable" do
      agent = build_agent(name: "Going Away", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])
      service.sync!
      expect(File.exist?(path_for(agent))).to be true

      stub_syncable([])
      result = service.sync!

      expect(File.exist?(path_for(agent))).to be false
      expect(result.removed).to eq([ agent.slug ])
    end

    it "never deletes a file without the generated header" do
      hand_authored = File.join(target_dir, "hand-authored.md")
      File.write(hand_authored, "---\nname: hand-authored\ndescription: manual\nmodel: sonnet\n---\n\nHand-written.\n")
      stub_syncable([])

      service.sync!

      expect(File.exist?(hand_authored)).to be true
    end
  end
end
