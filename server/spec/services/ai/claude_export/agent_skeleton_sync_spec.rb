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
    # Streamlining campaign C4: the committed set is the four thin loaders of
    # Ai::Agents::CanonicalRoster (Ai::ClaudeExport::ThinLoader), whatever the
    # database holds — no row, skill or registered tool reaches those files, so
    # the export needs no seeded database and no Claude Code restart follows a
    # platform edit. The account scope below is unchanged.
    context "canonical scope (no account — the committed thin loaders)" do
      subject(:service) { described_class.new(target_dir: target_dir) }

      let(:roster) { Ai::Agents::CanonicalRoster::SLUGS }

      def written_slugs
        Dir[File.join(target_dir, "*.md")].map { |path| File.basename(path, ".md") }
      end

      def committed(slug)
        File.read(File.join(target_dir, "#{slug}.md"))
      end

      it "writes exactly the roster's slugs, each as ThinLoader renders it" do
        result = service.sync!

        expect(result.written).to match_array(roster)
        expect(result.total).to eq(roster.size)
        expect(written_slugs).to match_array(roster)
        roster.each { |slug| expect(committed(slug)).to eq(Ai::ClaudeExport::ThinLoader.render(slug)) }
      end

      it "ignores every database canonical outside the roster — the legacy ones included" do
        legacy = build_canonical(name: "Platform Developer", slug: "platform-developer", agent_type: "code_assistant")
        build_canonical(name: "Opted In", mcp_metadata: { "claude_code_export" => true })

        service.sync!

        expect(written_slugs).to match_array(roster)
        expect(written_slugs).not_to include(legacy.slug)
      end

      it "removes the legacy generated skeletons as stale, and never a hand-authored file" do
        legacy = File.join(target_dir, "platform-developer.md")
        File.write(legacy, "---\nname: platform-developer\n---\n#{described_class::GENERATED_HEADER}\n")
        hand_authored = File.join(target_dir, "hand-authored.md")
        File.write(hand_authored, "---\nname: hand-authored\n---\n\nHand-written.\n")

        result = service.sync!

        expect(result.removed).to eq([ "platform-developer" ])
        expect(File.exist?(legacy)).to be(false)
        expect(File.exist?(hand_authored)).to be(true)
      end

      # The old guard refused an empty or partial database because the files
      # were rendered from its rows; the thin loaders are not, so there is
      # nothing to protect and an unseeded checkout regenerates the same set.
      it "writes the same set on a database with no agent and no account with a user" do
        Ai::Agent.delete_all
        expect(Account.joins(:users).exists?).to be(false)

        expect(service.sync!.written).to match_array(roster)
      end

      it "is idempotent, and INVARIANT when a skill, a prompt or a tool is added (the restart contract)" do
        service.sync!
        snapshot = roster.to_h { |slug| [ slug, committed(slug) ] }

        engineer = build_canonical(name: "Platform Engineer", slug: "platform-engineer", agent_type: "code_assistant")
        create(:ai_agent_skill, agent: engineer, skill: create(:ai_skill, :global, slug: "engineer-develop"), is_active: true)
        engineer.update!(system_prompt: "a new charter")
        allow(Ai::Tools::PlatformApiToolRegistry).to receive(:all_tools)
          .and_return(Ai::Tools::PlatformApiToolRegistry.all_tools.merge("brand_new_verb" => "Ai::Tools::ToolCatalogTool"))

        second = service.sync!

        expect(second.written).to eq([])
        expect(second.unchanged).to match_array(roster)
        expect(roster.to_h { |slug| [ slug, committed(slug) ] }).to eq(snapshot)
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

      # Operator decision (2026-09-25): an agent called only by services (the
      # JSON pipeline workers) carries mcp_metadata["claude_code_export"] = false.
      # Moved here from the canonical scope, which no longer reads agent rows.
      it "excludes an agent whose claude_code_export flag is false, and keeps one without the flag" do
        worker = create(:ai_agent, account: account, name: "Pipeline Worker", mcp_metadata: { "claude_code_export" => false })
        plain = create(:ai_agent, account: account, name: "Plain Agent")

        slugs = service.send(:syncable_agents).map(&:slug)

        expect(slugs).not_to include(worker.slug)
        expect(slugs).to include(plain.slug)
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

    # IMP-777f59d4cc1e: `tools:` stays the resolved exact names — the only form
    # Claude Code resolves — and the body renders the families it came from.
    it "renders the agent's tool families in the body" do
      agent = build_agent(name: "Scoped Monitor", resolved_model: "claude-sonnet-4-6",
                          mcp_metadata: { "tool_access" => { "tool_families" => %w[get_system_health list_component_status] } })
      stub_syncable([ agent ])

      service.sync!
      body = body_of(content_for(agent))

      expect(body).to include("## Tool families\n\n")
      expect(body).to include("`get_system_health`, `list_component_status`")
      expect(tools_of(agent)).to include("mcp__powernode__platform_get_system_health")
    end

    it "renders no tool families section when access is not family-scoped" do
      scopeless = build_agent(name: "Scopeless", resolved_model: "claude-sonnet-4-6")
      listed = build_agent(name: "Listed", resolved_model: "claude-sonnet-4-6",
                           mcp_metadata: { "tool_access" => { "allowed_tools" => %w[list_agents],
                                                              "tool_families" => %w[get_system_health] } })
      stub_syncable([ scopeless, listed ])

      service.sync!

      expect(body_of(content_for(scopeless))).not_to include("## Tool families")
      expect(body_of(content_for(listed))).not_to include("## Tool families")
    end
  end

  describe "body shape" do
    # IMP-9fc894cf80e6: step 1's verb (get_agent) is a BootstrapVerbs member
    # every skeleton's own `tools:` line names, but a narrower instance grant
    # can still omit it at runtime — the grant is instance-local state the
    # canonical exporter structurally cannot see (Mcp::Principal.tool_grant_resolver
    # is an extension-injected, per-instance lambda), so the committed file
    # cannot be made grant-aware without breaking byte-identical-per-install.
    # The fix is legibility, not recovery: an executor without get_agent must
    # STOP and say so, never proceed under a generic identity with no
    # specialist system_prompt (the file already says the platform record —
    # fetched only by that verb — is the sole source of truth).
    # B5: the fetched prompt is the operating instructions, but the delegating
    # prompt defines the deliverable, so a persona's fixed response format does
    # not override what the caller asked for. No "strictly".
    it "lets the delegating prompt define the task and what to return" do
      agent = build_agent(name: "Operating Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      body = body_of(content_for(agent))

      expect(body).to include("the delegating prompt defines the task and what to return")
      expect(body).not_to include("Operate strictly")
    end

    it "tells the executor not to proceed to the skill-context/operate steps when get_agent is unavailable, " \
       "without foreclosing the self-report exception" do
      agent = build_agent(name: "Bootstrapped Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      body = body_of(content_for(agent))

      expect(body).to include("If `get_agent` is not in your available tool list")
      expect(body).to include("do not proceed under a generic identity")
      expect(body).to include("do not attempt the fetch-skill-context or operate-under-the-prompt steps below")
      expect(body).to include("this run did not execute")
      # The old wording ("do not attempt step 2 onward") numerically swept in the
      # self-report step too, since it is itself one of the later numbered steps —
      # a careless reading forecloses the exact reporting the next example
      # requires. That phrasing must be gone, not just superseded.
      expect(body).not_to include("do not attempt step 2 onward")
    end

    # A stop that never reports leaves the platform's statistics blind: an
    # agent that never ran looks identical to one that was never spawned.
    # record_agent_execution IS served to a default-deny instance principal
    # (unlike get_agent), so the stop path must still call it — outcome
    # "failed", task_digest naming the unavailable verb — before it stops.
    # Asserted separately from the "does not proceed" example above: a single
    # assertion spanning both halves would stay green if this exception were
    # dropped from the wording later.
    it "still self-reports a failed run on the stop path, naming get_agent in the digest" do
      agent = build_agent(name: "Bootstrapped Agent", resolved_model: "claude-sonnet-4-6")
      stub_syncable([ agent ])

      service.sync!
      body = body_of(content_for(agent))

      expect(body).to include("but DO still call")
      expect(body).to include("`mcp__powernode__platform_record_agent_execution` (the self-report step below)")
      expect(body).to include(%(outcome: "failed"))
      expect(body).to include("task_digest` naming `get_agent`")
      expect(body.index("outcome: \"failed\"")).to be < body.index("this run did not execute")
    end

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
      # rindex, not index: step 1's own stop-path fallback (IMP-9fc894cf80e6)
      # also names record_agent_execution now, earlier in the body — the LAST
      # occurrence is the one this example is about, the final numbered step.
      expect(body.rindex("record_agent_execution")).to be > body.index("source of truth")
      # It is the last numbered step: after it comes the guardrails floor only.
      expect(body.rindex("record_agent_execution")).to be < body.index("## Baseline guardrails")
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

    # An empty list means NONE (HIER-P0 for types, IMP-d2873a16567e for
    # actions); the body used to render it as "any agent type".
    it "renders 'no agent type' when the policy lists no delegate types" do
      agent = build_agent(name: "Leaf Delegator", resolved_model: "claude-sonnet-4-6")
      create(:ai_delegation_policy, account: account, agent: agent, allowed_delegate_types: [])
      stub_syncable([ agent ])

      service.sync!

      expect(content_for(agent)).to include("May delegate to: no agent type")
      expect(content_for(agent)).not_to include("any agent type")
      expect(content_for(agent)).to include("Delegatable actions: none")
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
