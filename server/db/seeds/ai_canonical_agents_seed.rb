# frozen_string_literal: true

# The four target canonicals (streamlining campaign C4,
# docs/operations/streamlining-review-2026-10-19.md §4.1 / §7 C4-2): Powernode
# Concierge, Platform Engineer, Fleet Operator, Platform Reviewer. WHO they are
# (slug, name, type, tier, routing description) is Ai::Agents::CanonicalRoster,
# shared with the Claude Code export; this file adds the charter and the
# account-keyed posture.
#
# SHADOW MODE — seeded BESIDE the 28 canonicals they will absorb, which keep
# running the platform. So this file:
#   * writes the rows INACTIVE (create-only): Ai::Routing::RoutableAgents
#     (the route_task pool) and Ai::Agent.resolve_concierge_for read active
#     rows only, so no live routing or front-door resolution can pick a
#     survivor. Ai::Agent.resolve_for — the get_agent / record_agent_execution
#     slug lookup the Claude Code skeletons bootstrap through — ignores status.
#     Activation is the re-home step's (§5 step 5), and a re-seed keeps it;
#   * never sets is_concierge (the Powernode Assistant stays the front door);
#   * writes NO intervention-policy row, binds no lane and moves no policy.
#     Declared rows have one writer (System::Governance::PolicyReconciler,
#     ruling 7); spec/db/seeds/ai_canonical_agents_seed_spec.rb pins it.
#
# Tool access is the bootstrap floor only (BootstrapVerbs plus the self-report
# verb): §4.3 makes tool_families a ceiling, and the working set comes from the
# skills a task discovers, never from this row. Note the ceiling currently fails
# OPEN: AgentToolBridgeService#scope_to_tool_families falls back to the full
# registry when no family matches, so every name here must match a registered
# verb exactly (or by prefix: `search_knowledge` also admits search_knowledge_graph).
#
# Posture follows the agents each survivor absorbs: Platform Engineer like
# the Platform Developer and Fleet Operator like Fleet Autonomy (monitored, a
# 4h reject-on-timeout chain); the Concierge like the Powernode Assistant
# (trusted, no chain); the Reviewer like LLM Judge / System Quality Assurance
# (no trust row, no chain). Trust scores and chains are CREATE-ONLY and wait
# for the admin account; the canonical rows do not (IMP-6cda93db7f31).

puts "\n🧭 Seeding the C4 target canonicals (shadow mode: inactive, no policy rows)..."

require_relative "concerns/canonical_agent_owner"
require_relative "concerns/canonical_content"

canonical_roster_admin_account = Account.find_by(name: "Powernode Admin")
canonical_roster_admin_user = canonical_roster_admin_account&.users&.find_by(email: "admin@powernode.org")
canonical_roster_provider = Ai::Provider.find_by(provider_type: "anthropic") || Ai::Provider.where(is_active: true).first

CANONICAL_ROSTER_TOOL_FLOOR = (Ai::Tools::BootstrapVerbs::ACTIONS + %w[record_agent_execution]).freeze

# The progressive-disclosure protocol (§4.4) every charter ends with.
CANONICAL_ROSTER_PROTOCOL = <<~PROTOCOL
  ## How you work
  1. Discover, never assume: `discover_skills` with the task, then `get_skill_context`
     (mode "manifest") for the skills you choose; `search_knowledge` (tag `guidance-*`)
     and `query_learnings` for the rules and gotchas of the area.
  2. Load only the verbs those skills name, or that `discover_tools` returns for the
     intent; `describe_tool` a verb before you first call it. Never scan the catalog.
  3. Every verb is gated by the platform (intervention policies, approval chains):
     read the returned status, never predict or retry around a parked action.
  4. Work outside your charter goes back through `route_task`; never do it yourself.
  5. Report each run with `record_agent_execution` under your own slug.
PROTOCOL

CANONICAL_ROSTER_CHARTERS = {
  "powernode-concierge" => <<~CHARTER,
    You are the **Powernode Concierge**, the platform's front door.
    You answer questions about the platform, onboard operators, capture provisioning
    briefs, and route every request to the agent or skill that owns it. You never
    execute fleet or code writes yourself; you hand them on with `route_task`.
  CHARTER
  "platform-engineer" => <<~CHARTER,
    You are the **Platform Engineer**: everything that changes the platform itself —
    code and specs, docs, releases and the promotion ladder, campaigns, research and
    the knowledge that records it. Your roles are skills, chosen per task. Red first,
    targeted specs only, commits only on the branch you were given, and the loop
    guardrails `dev_next_task` returns whenever you drain a task.
  CHARTER
  "fleet-operator" => <<~CHARTER,
    You are the **Fleet Operator**: you operate the running fleet — nodes, instances,
    capacity, storage, networking, ingress, runtimes, disk images, packages and CVEs.
    Sense, decide, then act through the platform's gated verbs; domain expertise lives
    in the bound `system-*` skills, not in you. You own no autonomy lane yet.
  CHARTER
  "platform-reviewer" => <<~CHARTER
    You are the **Platform Reviewer**: the independent review of finished work — a
    drained task's diff, a campaign increment, a doc change, an autonomy decision —
    against its acceptance criteria. You are read-only: you never edit, commit or call
    a mutating verb, and you never review work you produced. Report findings by
    severity with file and line, and a verdict.
  CHARTER
}.freeze

CANONICAL_ROSTER_TRUST = {
  "powernode-concierge" => { tier: "trusted", overall: 0.85,
                             dimensions: { reliability: 0.85, cost_efficiency: 0.80, safety: 0.90, quality: 0.80, speed: 0.80 } },
  "platform-engineer"   => { tier: "monitored", overall: 0.58,
                             dimensions: { reliability: 0.60, cost_efficiency: 0.70, safety: 0.84, quality: 0.58, speed: 0.66 } },
  "fleet-operator"      => { tier: "monitored", overall: 0.74,
                             dimensions: { reliability: 0.70, cost_efficiency: 0.70, safety: 0.85, quality: 0.70, speed: 0.70 } }
}.freeze

# The chain each require_approval verb would route to ("<Agent Name> Actions",
# the Ai::AutonomyGate#resolve_chain default), in the absorbed agent's shape.
CANONICAL_ROSTER_CHAIN_APPROVERS = {
  "platform-engineer" => [ { "type" => "permission", "value" => "ai.autonomy.approve" } ],
  "fleet-operator"    => [ "*" ]
}.freeze

canonical_roster_written = 0

ActiveRecord::Base.transaction do
  Ai::Agents::CanonicalRoster::SURVIVORS.each do |slug, spec|
    agent = Ai::Agent.find_or_initialize_global(slug: slug)
    charter = "#{CANONICAL_ROSTER_CHARTERS.fetch(slug)}\n#{CANONICAL_ROSTER_PROTOCOL}".strip
    agent.assign_attributes(
      name: spec[:name],
      agent_type: spec[:agent_type],
      # Create-only: inactive in shadow mode; an operator's activation survives.
      status: (agent.new_record? ? "inactive" : agent.status),
      version: (agent.version || "1.0.0")
    )
    # Text is assigned on create only; refresh! below carries later seed text to
    # an existing row unless an operator edited it (concerns/canonical_content.rb).
    if agent.new_record?
      agent.description = spec[:description]
      agent.system_prompt = charter
    end
    metadata = (agent.mcp_metadata || {}).merge(
      "model_config" => (agent.mcp_metadata&.dig("model_config") || {}).merge(
        "model_requirements" => { "tier" => spec[:tier] }
      ),
      "tool_access" => { "tool_families" => CANONICAL_ROSTER_TOOL_FLOOR }
    )
    agent.mcp_metadata = metadata unless metadata == agent.mcp_metadata
    agent.save! if agent.new_record? || agent.changed?
    CoreSeeds::CanonicalAgentOwner.backfill_owner!(agent, creator: canonical_roster_admin_user, provider: canonical_roster_provider)
    CoreSeeds::CanonicalContent.refresh!(agent, { description: spec[:description], system_prompt: charter })
    canonical_roster_written += 1

    next if canonical_roster_admin_account.nil?

    if (trust = CANONICAL_ROSTER_TRUST[slug])
      score = Ai::AgentTrustScore.find_or_initialize_by(agent_id: agent.id)
      if score.new_record?
        dims = trust[:dimensions]
        score.update!(
          account: canonical_roster_admin_account, tier: trust[:tier], overall_score: trust[:overall],
          reliability: dims[:reliability], cost_efficiency: dims[:cost_efficiency], safety: dims[:safety],
          quality: dims[:quality], speed: dims[:speed]
        )
      end
    end

    approvers = CANONICAL_ROSTER_CHAIN_APPROVERS[slug]
    next unless approvers

    chain = Ai::ApprovalChain.find_or_initialize_by(account: canonical_roster_admin_account, name: "#{agent.name} Actions")
    next unless chain.new_record?

    chain.assign_attributes(
      trigger_type: "autonomy_action", status: "active", is_sequential: true,
      timeout_action: "reject", timeout_hours: 4,
      steps: [ { "name" => "Operator Approval", "approvers" => approvers, "required_approvals" => 1 } ]
    )
    chain.created_by = canonical_roster_admin_user if chain.respond_to?(:created_by=)
    chain.save!
  end
end

puts "  ✅ C4 target canonicals: #{canonical_roster_written} written " \
     "(#{canonical_roster_admin_account ? 'trust and chains create-only' : 'no admin account yet — trust and chains wait for setup'})"
