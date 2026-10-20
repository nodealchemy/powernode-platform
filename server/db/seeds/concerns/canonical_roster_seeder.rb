# frozen_string_literal: true

require_relative "canonical_agent_owner"
require_relative "canonical_content"

# Seeds the canonical agents ONE OWNER registered into
# Ai::Agents::CanonicalRoster: core's seed passes core's owner, an extension's
# seed passes its own, so each seeds exactly what it declared and core never
# names an extension's agent. The registry (loaded at boot, before any seed
# runs) is the only input; this file knows no slug.
#
# SHADOW MODE (unchanged from the four-survivor seed): rows are written
# INACTIVE on create (Ai::Routing::RoutableAgents and
# Ai::Agent.resolve_concierge_for read active rows only; Ai::Agent.resolve_for —
# the get_agent / record_agent_execution slug lookup the Claude Code skeletons
# bootstrap through — ignores status), is_concierge is never set, and NO
# intervention-policy row is written or bound: declared rows have one writer
# (System::Governance::PolicyReconciler).
#
# Tool access is the bootstrap floor only (BootstrapVerbs plus the self-report
# verb); the working set comes from the skills an assembly returns, never from
# the row. Trust scores and approval chains are CREATE-ONLY and wait for the
# admin account; the canonical rows do not (IMP-6cda93db7f31). Text is assigned
# on create and carried to an existing row by CanonicalContent.refresh!, which
# keeps an operator's edit.
module CoreSeeds
  module CanonicalRosterSeeder
    TOOL_FLOOR = (Ai::Tools::BootstrapVerbs::ACTIONS + %w[record_agent_execution]).freeze

    module_function

    # @param owner [String] Ai::Agents::CanonicalRoster owner id ("core", "extensions/<slug>")
    # @return [Integer] rows written or confirmed
    def seed!(owner:)
      admin_account = Account.find_by(name: "Powernode Admin")
      admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")
      provider = Ai::Provider.find_by(provider_type: "anthropic") || Ai::Provider.where(is_active: true).first
      written = 0

      ActiveRecord::Base.transaction do
        Ai::Agents::CanonicalRoster.each(owner: owner) do |slug, spec, _owner|
          agent = seed_agent!(slug, spec, admin_user: admin_user, provider: provider)
          written += 1
          next if admin_account.nil?

          seed_trust!(agent, spec.dig(:posture, :trust), admin_account)
          seed_chain!(agent, spec.dig(:posture, :chain_approvers), admin_account, admin_user)
        end
      end

      puts "  ✅ #{owner} canonicals: #{written} written " \
           "(#{admin_account ? 'trust and chains create-only' : 'no admin account yet — trust and chains wait for setup'})"
      written
    end

    def seed_agent!(slug, spec, admin_user:, provider:)
      agent = Ai::Agent.find_or_initialize_global(slug: slug)
      charter = spec[:charter].strip
      agent.assign_attributes(
        name: spec[:name],
        agent_type: spec[:agent_type],
        # Create-only: inactive in shadow mode; an operator's activation survives.
        status: (agent.new_record? ? "inactive" : agent.status),
        version: (agent.version || "1.0.0")
      )
      if agent.new_record?
        agent.description = spec[:description]
        agent.system_prompt = charter
      end
      metadata = (agent.mcp_metadata || {}).merge(
        "model_config" => (agent.mcp_metadata&.dig("model_config") || {}).merge(
          "model_requirements" => { "tier" => spec[:tier] }
        ),
        "tool_access" => { "tool_families" => TOOL_FLOOR }
      )
      agent.mcp_metadata = metadata unless metadata == agent.mcp_metadata
      agent.save! if agent.new_record? || agent.changed?
      CanonicalAgentOwner.backfill_owner!(agent, creator: admin_user, provider: provider)
      CanonicalContent.refresh!(agent, { description: spec[:description], system_prompt: charter })
      agent
    end

    def seed_trust!(agent, trust, account)
      return unless trust

      score = Ai::AgentTrustScore.find_or_initialize_by(agent_id: agent.id)
      return unless score.new_record?

      dims = trust[:dimensions]
      score.update!(
        account: account, tier: trust[:tier], overall_score: trust[:overall],
        reliability: dims[:reliability], cost_efficiency: dims[:cost_efficiency], safety: dims[:safety],
        quality: dims[:quality], speed: dims[:speed]
      )
    end

    # The chain each require_approval verb would route to ("<Agent Name> Actions",
    # the Ai::AutonomyGate#resolve_chain default).
    def seed_chain!(agent, approvers, account, user)
      return unless approvers

      chain = Ai::ApprovalChain.find_or_initialize_by(account: account, name: "#{agent.name} Actions")
      return unless chain.new_record?

      chain.assign_attributes(
        trigger_type: "autonomy_action", status: "active", is_sequential: true,
        timeout_action: "reject", timeout_hours: 4,
        steps: [ { "name" => "Operator Approval", "approvers" => approvers, "required_approvals" => 1 } ]
      )
      chain.created_by = user if chain.respond_to?(:created_by=)
      chain.save!
    end
  end
end
