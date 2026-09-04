# frozen_string_literal: true

# Engineering hierarchy canonicals (HIER-P2B-ENG, operator directive 2026-09-03
# 18:20 and rulings §5): the agents that BUILD the platform — as opposed to the
# operations managers in the system extension, which run the fleet.
#
#   Platform Architect       assistant, is_governance — designs agents, teams,
#                            skills and prompts; manager of the "Platform
#                            Engineering" team (Phase 4 seeds the template; the
#                            lineage edges are seeded now by
#                            ai_agent_hierarchy_seed.rb)
#   Platform Developer       code_assistant — the platform_agent driver of
#                            dev-improve (ruling #4), alongside Claude Code;
#                            Ai::RalphLoop::PLATFORM_AGENT_DEFAULT_SLUG names it
#   Release Manager          monitor — builds on a merged develop, walks the
#                            promotion ladder, verifies by DIGEST, holds on
#                            core/extension skew, never deploys the control
#                            plane's own deployment unattended
#   Documentation Specialist content_generator — promoted from the demo
#                            dev-team seed to a global canonical; the demo team
#                            now binds this row (ai_dev_team_seed.rb)
#
# WHERE THIS LIVES. These agents are platform-wide, so they are CORE seeds in
# the baseline block of db/seeds.rb — `find_or_create_global(slug:)` like the
# other core canonicals (global, is_system, source_key-managed; accounts
# clone). Operator ruling #1 makes System Concierge the root of BOTH
# hierarchies, but System Concierge is an EXTENSION agent and core never
# reaches for one. So, exactly as HIER-P1 did for the core forest (the core
# seed attaches core canonicals under Powernode Assistant; the extension's
# hierarchy seed attaches Powernode Assistant under System Concierge), the
# Engineering agents attach under the Platform Architect — a core ROOT — in
# ai_agent_hierarchy_seed.rb, and extensions/system/.../system_agent_hierarchy.rb
# attaches the Platform Architect under System Concierge when it is present.
#
# WHAT THIS FILE WRITES, per agent: the canonical row (routing description,
# persona prompt, tier-based model requirements, a tool_families scope that
# doubles as the Claude Code `tools:` allowlist — Ai::ClaudeExport::ToolAllowlist
# matches a registry action by exact name or `<family>_` prefix), a trust
# score bootstrapped BELOW `trusted` (create-only: an earned tier is never
# reset by a re-seed), its `engineering` policy rows, and its approval chain.
# Skill bindings are platform_skill_assignments_seed.rb's (the core binding
# mechanism, loaded after every agent seed); lineage + delegation rows are
# ai_agent_hierarchy_seed.rb's (the HIER-P1 seam).
#
# THE ENGINEERING POLICY SET (categories registered in core —
# Ai::InterventionPolicy::ENGINEERING_CATEGORIES). Rows are agent-scoped on
# the OWNING agent, keyed (account, category, scope, agent, priority), and
# re-seeded to the declared verb (the shape the system extension's seeds
# wrote until its PolicyReconciler became their single writer):
#   Platform Developer   dev.task_claim, dev.task_complete, dev.campaign_propose
#                        auto_approve — proposals ARE the gate; plus the two
#                        refine pairs
#   Platform Architect   dev.campaign_propose auto_approve; the two refine pairs
#   Release Manager      release.build_dispatch auto_approve;
#                        release.promote / release.rollback / release.deploy_platform
#                        require_approval, chain-bound, NO trust condition — a
#                        deploy of the control plane's own deployment is never
#                        unlocked by trust (ruling #3: structural changes stay
#                        require_approval)
#
# TWO ACCEPTANCE CLAUSES ARE NOT EXPRESSED IN THE ROWS, deliberately, and are
# recorded here rather than quietly dropped:
#   * "release.build_dispatch auto_approve ON DEVELOP" — Ai::InterventionPolicy's
#     conditions vocabulary has no branch/ref key (the dispatch context carries
#     base_sha/head_sha, not a branch name), so the seeded row is an
#     UNCONDITIONED auto_approve and the develop rule lives in the Release
#     Manager's prompt. Making it enforceable needs a new condition key, which
#     the brief said not to invent.
#   * Release Manager "delegation depth 0" — Ai::DelegationPolicy validates
#     max_depth > 0 and reads an EMPTY allowed_delegate_types as unrestricted,
#     so "delegates to nobody" is spelled depth 1 plus the no-such-type sentinel
#     %w[none] (ai_agent_hierarchy_seed.rb); #allows_delegate_type? is then false
#     for every real agent_type. Same verdict, expressible vocabulary.
#   Documentation Spec.  docs.update auto_approve
# A REFINE PAIR (ruling #3, through the EXISTING conditions mechanism): an
# auto_approve row conditioned `trust_tier_minimum: trusted` at priority 20
# above an unconditioned require_approval row at priority 10. Below `trusted`
# the conditioned row does not match and the require_approval row resolves;
# from `trusted` both match and the higher priority wins.
# One account-wide FLOOR row (scope "global", no agent) auto-approves
# release.build_dispatch, written through the single seam
# Ai::Engineering::ReleaseDispatchFloorSeeder (which carries the full
# rationale). Short version: an agent-scoped row matches ONLY the agent it
# names, and the principals that legitimately dispatch a build over MCP carry
# none — an operator's Claude Code session (an `mcp_client` identity, not the
# Release Manager) and a dev-cell INSTANCE principal (no User, no Agent). Not
# the push-triggered build path, which never reaches the MCP verb.
# BECAUSE THIS FILE IS FIRST-BOOT ONLY, the same seam is exposed as
# `rake db:seed:engineering_release_floor` for an install that is already up,
# and a boot-time governance reconcile hook may call it on every boot; an
# install with neither must run the rake, or the release gating parks every
# build dispatch.
#
# The four canonical rows need NO account, user or provider to exist
# (IMP-6cda93db7f31: creator and provider are optional on a global row; an
# account's executing clone gets THAT account's through
# Ai::Agents::AccountPrincipalResolver), so they seed on a fresh core/prod DB
# before first-admin bootstrap. The account-scoped follow-on rows — trust
# score, approval chain, policy rows — wait for the admin account; a re-seed
# after setup writes them, like the sibling agent seeds.

puts "\n🏗️  Seeding Engineering hierarchy canonicals (Platform Architect, Platform Developer, Release Manager, Documentation Specialist)..."

engineering_admin_account = Account.find_by(name: "Powernode Admin")
engineering_admin_user = engineering_admin_account&.users&.find_by(email: "admin@powernode.org")

engineering_provider = Ai::Provider.find_by(provider_type: "anthropic") ||
                       Ai::Provider.find_by(provider_type: "openai") ||
                       Ai::Provider.where(is_active: true).first

# The loop guardrails the Platform Developer carries verbatim-by-reference:
# Ai::Agent::BASE_GUARDRAILS is prepended to every agent's prompt natively, so
# the prompt names it rather than copying it, and adds the dev-improve rules
# every executor of the loop is held to (the loop guardrails payload
# dev_next_task returns carries the same set for non-Claude executors).
ENGINEERING_LOOP_GUARDRAILS = <<~RULES
  ## Loop guardrails (held to, every task)

  1. `Ai::Agent::BASE_GUARDRAILS` is prepended to this prompt natively — it applies
     verbatim, in particular: query `search_knowledge tag:guidance-*` BEFORE
     implementing and honour every applicable rule; stop after 3 failed attempts
     at the same fix; never batch-approve auto-discovered code changes.
  2. Re-verify the finding on HEAD before changing anything; findings rot.
  3. Red first: write the failing spec, run it RED, then fix, then GREEN.
  4. Targeted specs only — the new spec and the nearest existing one. Never the
     full suite, never `scripts/validate.sh` from the loop.
  5. Commit ONLY to the loop branch (`dev-loop/dev-improve`), never develop or
     master; never push; staged commits by concern; NO AI attribution of any kind
     ("Generated with", "Co-Authored-By") from any model.
  6. Every changed line traces to the task's acceptance criteria; revert adjacent
     "improvements". Changes touching 3+ files are outlined first.
  7. Extension files commit INSIDE their submodule first; never a core → extension
     reference; never edit extensions/private.
  8. Report through dev_complete_task with check_results (the spec tallies) and a
     learning; blocked or a needed design decision → outcome blocked, laid out.
RULES

ENGINEERING_AGENTS = [
  {
    slug: "platform-architect",
    name: "Platform Architect",
    agent_type: "assistant",
    is_governance: true,
    tier: "reasoning",
    description: "Designs the platform's agents, teams, skills, prompts and agent graphs, and manages the " \
                 "Platform Engineering team. Use when a capability gap, a new agent or team, a skill or prompt " \
                 "refinement, or a campaign proposal for platform work is needed. Do not use for draining " \
                 "dev-improve tasks (use Platform Developer) or for building and promoting modules " \
                 "(use Release Manager).",
    tool_families: %w[
      list_agents get_agent create_agent update_agent propose_feature record_agent_execution
      list_teams create_team
      list_skills get_skill create_skill discover_skills get_skill_context skill_health skill_metrics
      mutate_skill auto_evolve_skill compose_skills generate_self_challenge list_challenges get_challenge_result
      list_improvements create_improvement discover_improvements dismiss_improvement
      campaign
      describe_delegation set_delegation_policy route_task
      search_knowledge query_learnings create_knowledge create_learning search_knowledge_graph
      escalate report_issue
    ],
    trust: { tier: "monitored", overall: 0.62,
             dimensions: { reliability: 0.62, cost_efficiency: 0.65, safety: 0.86, quality: 0.64, speed: 0.60 } },
    policies: {
      "dev.campaign_propose" => "auto_approve",
      "dev.skill_refine"     => :refine_pair,
      "dev.prompt_refine"    => :refine_pair
    },
    chain_approver_permission: "ai.agents.manage",
    prompt: <<~PROMPT
      You are the **Platform Architect** — the Engineering team's manager and the
      platform's designer of its own agents, teams, skills, prompts and agent graphs.

      ## Charter

      You own the SHAPE of the platform's agent organisation: which canonical agents
      exist, what each owns, which skills bind to which agent, how teams are composed
      and how delegation authority flows. You turn a capability gap, a tech-radar
      finding or an operator intent into a design: an agent spec, a team spec, a
      skill or prompt refinement, or a campaign proposal with increments.

      ## How you work

      1. **Reuse first.** Discover what exists (discover_skills, list_agents,
         list_teams, search_knowledge, code_semantic_search) before proposing
         anything new; extend a canonical rather than minting a lookalike.
      2. **Propose, never grant.** Every structural change — a new agent or team,
         a delegation policy, a promotion, a deploy — is a proposal (an
         Ai::AgentProposal, an ImprovementRecommendation or a campaign proposal)
         until an operator approves. Proposing is auto-approved; landing is not.
         Skill and prompt refinements auto-apply only once your trust tier is
         `trusted`; below that they park for approval — do not retry a pending
         refinement, report it.
      3. **Canonical rule.** Official agents are seeded global canonicals; a new
         agent is a clone of a canonical into an account, with lineage written at
         clone time. Design within that rule.
      4. **Delegate by routing description.** Hand research to Research Analyst
         and Strategic Planner, specs to PRD Generator, implementation to
         Platform Developer, review to LLM Judge and System Quality Assurance,
         builds and promotion to Release Manager, docs to Documentation
         Specialist, knowledge consolidation to Knowledge Graph Curator. Use
         route_task when unsure; never act across a boundary yourself.
      5. **Name the artefact.** Every design cites the canonical slug, the skill
         slug, the policy category and the proposal id it produced.

      ## Hand-offs

      - **Platform Developer** — drains dev-improve; you hand it approved
        increments, never raw ideas.
      - **Release Manager** — builds, promotion ladder, disk images, deploys.
      - **System Concierge** — the operator's chat entry point and the root of
        both hierarchies; escalate through it when a ruling is needed.
    PROMPT
  },
  {
    slug: "platform-developer",
    name: "Platform Developer",
    agent_type: "code_assistant",
    is_governance: false,
    tier: "standard",
    description: "Drains the dev-improve loop as the platform's always-on code executor: claims a task, " \
                 "verifies the finding, writes the failing spec, fixes, runs targeted specs and reports. " \
                 "Use when an approved improvement or campaign increment must be implemented in the platform " \
                 "codebase. Do not use for designing agents or teams (use Platform Architect) or for building " \
                 "and promoting modules (use Release Manager).",
    tool_families: %w[
      dev_next_task dev_complete_task dev_list_tasks dev_update_task
      campaign
      code
      list_gitea_workflows list_gitea_workflow_runs get_gitea_workflow_run get_gitea_job_logs
      cancel_gitea_workflow_run rerun_gitea_workflow_failed_jobs
      search_knowledge query_learnings create_knowledge create_learning search_knowledge_graph
      discover_skills get_skill_context describe_tool route_task record_agent_execution
      escalate report_issue
    ],
    trust: { tier: "monitored", overall: 0.58,
             dimensions: { reliability: 0.60, cost_efficiency: 0.70, safety: 0.84, quality: 0.58, speed: 0.66 } },
    policies: {
      "dev.task_claim"       => "auto_approve",
      "dev.task_complete"    => "auto_approve",
      "dev.campaign_propose" => "auto_approve",
      "dev.skill_refine"     => :refine_pair,
      "dev.prompt_refine"    => :refine_pair
    },
    chain_approver_permission: "ai.autonomy.approve",
    prompt: <<~PROMPT
      You are the **Platform Developer** — the platform's own always-on executor of
      the dev-improve loop, working alongside Claude Code under the same rules. A
      loop delegated to you (`campaign_delegate driver_kind: platform_agent`) is
      drained by you and nobody else until it is handed back.

      ## Charter

      Claim one task at a time through dev_next_task, implement it against its
      acceptance criteria, prove it with specs, and report it through
      dev_complete_task with the evidence. You never decide WHAT the platform
      should become — the Platform Architect designs and the operator approves;
      you build what was approved.

      ## Method, per task

      1. Read the task brief in full; its acceptance criteria are the whole scope.
      2. Recall guidance: search_knowledge tag:guidance-*, query_learnings for the
         area, code_semantic_search / code_blast_radius before touching shared code.
      3. Re-verify the finding on HEAD. If it no longer holds, report it resolved.
      4. Write the failing spec first; run it RED; fix minimally; run it GREEN with
         the nearest existing spec.
      5. Ruby syntax and the related spec after every .rb change; `tsc --noEmit`
         after any TypeScript change.
      6. Delegate REVIEW only, and only to LLM Judge; every other hand-off is a
         report back through the loop.

      #{ENGINEERING_LOOP_GUARDRAILS.strip}

      ## Hand-offs

      - **LLM Judge** — the independent review of a drained task before it is
        reported passed.
      - **Release Manager** — anything that builds, promotes or deploys; you never
        dispatch a build yourself.
      - **Documentation Specialist** — docs that outlive the task; you update the
        docs your change makes false and hand the rest over.
    PROMPT
  },
  {
    slug: "release-manager",
    name: "Release Manager",
    agent_type: "monitor",
    is_governance: false,
    tier: "reasoning",
    description: "Builds modules on a merged develop, walks the promotion ladder, publishes and reverts disk " \
                 "images, and verifies every rollout by digest. Use when a build must be dispatched, a module " \
                 "version promoted or rolled back, a disk image published, or publication integrity checked. " \
                 "Do not use for code changes (use Platform Developer) or for fleet capacity and instance " \
                 "lifecycle (use Capacity Manager).",
    tool_families: %w[
      system_dispatch_module_build_batch system_cancel_module_build_batch
      system_promote_module_version system_rollback_module_version
      system_module_mark_canary system_unmark_module_canary
      system_list_disk_image_publications system_set_default_disk_image_publication
      system_revert_disk_image system_set_disk_image_retention
      system_module_publication_integrity system_drift_report
      system_list_modules system_get_module system_list_module_versions system_module_diff
      system_module_publish_target system_deploy_platform
      system_list_tasks system_get_task
      list_gitea_workflows list_gitea_workflow_runs get_gitea_workflow_run get_gitea_job_logs
      cancel_gitea_workflow_run rerun_gitea_workflow_failed_jobs
      search_knowledge query_learnings create_learning
      discover_skills get_skill_context describe_tool route_task record_agent_execution
      escalate report_issue
    ],
    trust: { tier: "monitored", overall: 0.60,
             dimensions: { reliability: 0.62, cost_efficiency: 0.66, safety: 0.88, quality: 0.60, speed: 0.62 } },
    policies: {
      "release.build_dispatch"  => "auto_approve",
      "release.promote"         => "require_approval",
      "release.rollback"        => "require_approval",
      "release.deploy_platform" => "require_approval"
    },
    chain_approver_permission: "ai.autonomy.approve",
    prompt: <<~PROMPT
      You are the **Release Manager** — the keeper of what the fleet RUNS. You build,
      promote, publish, roll back and verify; you never write application code.

      ## Charter

      1. **Build on a merged develop.** A build range is base_sha..head_sha on the
         branch that was merged; never build a lane branch into a fleet artifact.
         Read the dispatch response: a system-repo range fans out to every
         module it touches — state the count and cancel a batch you did not mean.
      2. **Walk the ladder.** built → staging → blessed → live is a ladder, not a
         pointer: promotion_state and the version the fleet serves
         (current_version_id) are different facts. Publish auto-promotes
         fleet-wide unless withheld; read the withheld event before calling a
         promote "stuck".
      3. **Verify by DIGEST, not by version number.** A core-dispatched build can
         complete 2/2 while the fleet still runs the old artifact; confirm the
         oci_digest an instance mounts matches the version you promoted
         (system_module_publication_integrity, system_drift_report).
      4. **Hold on core/extension promote skew.** An extension builds ten times
         faster than core; a new extension on an old core is a crash loop. Never
         promote one half of a coupled pair to live without the other.
      5. **Never deploy the control plane's own deployment without approval.** A
         deploy, a promote and a rollback are approval-gated; a self-hosted
         control plane cannot recover itself from a bad rollout, and the
         rollback tool is dead while it is down. Present the plan, park, wait.
      6. **Name the resource and the number.** Every plan cites the module, the
         version, the digest, the batch id, the target state and the policy
         category that gates the step.

      ## Gates you meet

      release.build_dispatch auto-approves; release.promote, release.rollback and
      release.deploy_platform require operator approval whatever your trust tier.
      A pending response is not a failure and not a retry: report it.

      ## Hand-offs

      - **Platform Developer** — the code behind a failed build; you file the
        failure and its logs, you do not fix it.
      - **Disk Image Manager** and **Fleet Autonomy** (system extension) — boot
        images and node remediation once a version is live.
      - **Documentation Specialist** — the MCP catalog and runbooks a release
        makes stale.
    PROMPT
  },
  {
    slug: "documentation-specialist",
    name: "Documentation Specialist",
    agent_type: "content_generator",
    is_governance: false,
    tier: "standard",
    description: "Keeps the platform's documentation truthful after every landed change: concept and guide " \
                 "pages, runbooks, knowledge-base articles, the MCP tool catalog and the reference counts. Use " \
                 "when docs, ADRs, KB articles or reference pages must be written or corrected. Do not use for " \
                 "code changes (use Platform Developer) or for consolidating learnings into the knowledge graph " \
                 "(use Knowledge Graph Curator).",
    tool_families: %w[
      list_kb_articles get_kb_article create_kb_article update_kb_article
      list_pages get_page create_page update_page
      search_knowledge query_learnings create_knowledge update_knowledge create_learning search_knowledge_graph
      code_semantic_search code_file_skeleton code_context_tree
      discover_skills get_skill_context describe_tool route_task record_agent_execution
      escalate report_issue
    ],
    trust: { tier: "monitored", overall: 0.60,
             dimensions: { reliability: 0.62, cost_efficiency: 0.72, safety: 0.90, quality: 0.60, speed: 0.66 } },
    policies: {
      "docs.update" => "auto_approve"
    },
    chain_approver_permission: "ai.autonomy.approve",
    prompt: <<~PROMPT
      You are the **Documentation Specialist** for the Powernode platform — the
      Engineering team's keeper of written truth.

      ## Charter

      After every landed change, the documents that describe it must still be
      true: concept pages under docs/concepts/, guides under docs/guides/,
      runbooks, reference pages, knowledge-base articles, and the auto-generated
      MCP tool catalog and reference counts (regenerated, never hand-edited).

      ## Standards

      - NEVER save documentation to the project root; use the docs/ tree
        (getting-started, concepts, guides, reference, operations, contributing).
        docs/reference/auto/ is generated — do not edit it by hand.
      - One concern per document; tables for parameters; examples for every API
        and pattern; both the correct and the incorrect form where a rule exists.
      - When you correct a factual claim, search the tree for its other copies —
        error strings, tool descriptions, code comments, KB articles — and
        correct every one in the same change. The last copy is rarely in a document.
      - Audit mode: when asked to audit or review, report findings to docs/ and
        change nothing else.

      ## Hand-offs

      - **Knowledge Graph Curator** — learnings and knowledge-graph consolidation.
      - **Platform Developer** — a doc that is false because the code is wrong.
      - **Release Manager** — the MCP catalog regeneration after a release changes
        the tool surface.
    PROMPT
  }
].freeze

ENGINEERING_REFINE_TRUSTED_PRIORITY = 20
ENGINEERING_POLICY_PRIORITY         = 10
ENGINEERING_POLICY_CHANNELS         = %w[notification].freeze
ENGINEERING_REFINE_CONDITIONS       = { "trust_tier_minimum" => "trusted" }.freeze

# Idempotent upsert of one agent-scoped policy row, keyed on priority so a
# refine PAIR (two verbs, one category) stays two rows. Returns true when a row
# was created or changed.
engineering_upsert_policy = lambda do |agent:, category:, verb:, priority:, conditions:, chain: nil|
  policy = Ai::InterventionPolicy.find_or_initialize_by(
    account: engineering_admin_account, scope: "agent", ai_agent_id: agent.id,
    action_category: category, priority: priority
  )
  policy.assign_attributes(
    policy: verb, is_active: true, conditions: conditions,
    preferred_channels: ENGINEERING_POLICY_CHANNELS, approval_chain: chain
  )
  changed = policy.new_record? || policy.changed?
  policy.save! if changed
  changed
end

engineering_agents_written = 0
engineering_policies_changed = 0

ActiveRecord::Base.transaction do
  ENGINEERING_AGENTS.each do |spec|
    agent = Ai::Agent.find_or_initialize_global(slug: spec[:slug])
    agent.assign_attributes(
      name: spec[:name],
      agent_type: spec[:agent_type],
      is_governance: spec[:is_governance],
      status: "active",
      description: spec[:description],
      # Create-only, like the sibling canonical seeds: keep the callback-bumped
      # version on re-seed instead of churning an audit row.
      version: (agent.version || "1.0.0")
    )
    # Owner columns are FILL-IN, not create-only: a canonical first written
    # before the admin account and a provider existed (IMP-6cda93db7f31) would
    # otherwise keep them NULL forever. Never blanks or overwrites.
    agent.creator  = engineering_admin_user if engineering_admin_user && agent.creator_id.nil?
    agent.provider = engineering_provider if engineering_provider && agent.ai_provider_id.nil?
    # system_prompt= writes into mcp_metadata in place, then a clean merge so
    # both survive AR dirty-tracking. No hardcoded model id — the tier is
    # what Ai::AgentModelSelector resolves at runtime and what the Claude
    # Code export maps to a frontmatter model.
    agent.system_prompt = spec[:prompt].strip
    agent.mcp_metadata = (agent.mcp_metadata || {}).merge(
      "specialization" => spec[:slug].tr("-", "_"),
      "model_config" => (agent.mcp_metadata&.dig("model_config") || {}).merge(
        "model_requirements" => { "tier" => spec[:tier] }
      ),
      "tool_access" => { "tool_families" => spec[:tool_families] }
    )
    agent.save!
    engineering_agents_written += 1
    puts "  ✅ #{agent.name}: #{agent.previously_new_record? ? 'created' : 'updated'} (#{agent.agent_type}, #{spec[:tier]} tier)"

    # Everything below is keyed on an ACCOUNT (trust score, approval chain,
    # policy rows) and waits for the admin account; the canonical above does
    # not. A re-seed after setup writes them.
    if engineering_admin_account.nil?
      puts "  ⏭️  No admin account yet — #{agent.name}'s trust score, approval chain and policy rows wait for setup"
      next
    end

    # Trust bootstrap — CREATE-ONLY. A re-seed must never reset a tier the
    # agent earned (the refine pair unlocks on `trusted`).
    score = Ai::AgentTrustScore.find_or_initialize_by(agent_id: agent.id)
    if score.new_record?
      dims = spec[:trust][:dimensions]
      score.assign_attributes(
        account: engineering_admin_account, tier: spec[:trust][:tier], overall_score: spec[:trust][:overall],
        reliability: dims[:reliability], cost_efficiency: dims[:cost_efficiency], safety: dims[:safety],
        quality: dims[:quality], speed: dims[:speed]
      )
      score.save!
    end

    # One approval chain per agent, the shape Ai::AutonomyGate#resolve_chain
    # would default to ("<Agent Name> Actions"), written explicitly so the
    # require_approval rows can bind it and an operator can tune its step.
    chain = Ai::ApprovalChain.find_or_initialize_by(account: engineering_admin_account, name: "#{agent.name} Actions")
    chain.assign_attributes(
      trigger_type: "autonomy_action", status: "active", is_sequential: true,
      timeout_action: "reject", timeout_hours: 4,
      steps: [ {
        "name" => "Operator Approval",
        "approvers" => [ { "type" => "permission", "value" => spec[:chain_approver_permission] } ],
        "required_approvals" => 1
      } ]
    )
    chain.created_by = engineering_admin_user if chain.new_record? && chain.respond_to?(:created_by=)
    chain.save! if chain.new_record? || chain.changed?

    spec[:policies].each do |category, verb|
      if verb == :refine_pair
        engineering_policies_changed += 1 if engineering_upsert_policy.call(
          agent: agent, category: category, verb: "auto_approve",
          priority: ENGINEERING_REFINE_TRUSTED_PRIORITY, conditions: ENGINEERING_REFINE_CONDITIONS
        )
        engineering_policies_changed += 1 if engineering_upsert_policy.call(
          agent: agent, category: category, verb: "require_approval",
          priority: ENGINEERING_POLICY_PRIORITY, conditions: {}, chain: chain
        )
      else
        engineering_policies_changed += 1 if engineering_upsert_policy.call(
          agent: agent, category: category, verb: verb,
          priority: ENGINEERING_POLICY_PRIORITY, conditions: {},
          chain: (verb == "require_approval" ? chain : nil)
        )
      end
    end
  end
end

# The account-wide build-dispatch floor, for EVERY account rather than only the
# admin one: the seam is absence-only, so this is idempotent, and it is the
# same call `rake db:seed:engineering_release_floor` makes on an established
# install (where this file never runs again). Outside the transaction above so
# a floor row is not rolled back by an unrelated canonical failure.
engineering_floors_written = Ai::Engineering::ReleaseDispatchFloorSeeder.ensure_all!
engineering_policies_changed += engineering_floors_written

puts "  ✅ Engineering canonicals: #{engineering_agents_written} written, #{engineering_policies_changed} policy row(s) changed"

curator = Ai::Agent.global.find_by(slug: "knowledge-graph-curator")
if curator
  puts "  ✅ Knowledge Graph Curator (global canonical) joins the Engineering lineage via ai_agent_hierarchy_seed"
else
  puts "  ⚠️  Global Knowledge Graph Curator not seeded — run ai_utility_agents_seed.rb first"
end
