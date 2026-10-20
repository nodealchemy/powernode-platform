# frozen_string_literal: true

require "rails_helper"

# Streamlining campaign C4 (docs/operations/streamlining-review-2026-10-19.md
# §4.1, §7 C4-2), SHADOW MODE: the four survivors are seeded as NEW global
# canonicals beside the 28 they will absorb, and nothing the live fleet or the
# autonomy loop reads moves. So this pins, besides the rows themselves:
#   * ZERO intervention-policy rows from the seed (PolicyReconciler is the one
#     writer of declared rows — ruling 7; core's engineering seed is the only
#     core exception and this seed is not one);
#   * the survivors stay OUT of every live resolution: inactive, so neither the
#     router pool (Ai::Routing::RoutableAgents.for) nor the concierge
#     resolution (Ai::Agent.resolve_concierge_for) can pick one; and
#     PLATFORM_AGENT_DEFAULT_SLUG still names the Platform Developer;
#   * get_agent's slug lookup (Ai::Agent.resolve_for) still reaches them, since
#     the Claude Code skeletons bootstrap through it;
#   * a second run changes nothing.
RSpec.describe "db/seeds/ai_canonical_agents_seed.rb" do
  roster = Ai::Agents::CanonicalRoster
  core_slugs = %w[powernode-concierge platform-engineer platform-reviewer]

  def load_seed!(file = "ai_canonical_agents_seed.rb")
    silence_warnings { silence_stream { load Rails.root.join("db", "seeds", file) } }
  end

  def silence_stream
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  def survivor(slug) = Ai::Agent.global.find_by!(slug: slug)

  context "with the admin account seeded (the account-keyed rows run)" do
    let!(:account)  { create(:account, name: "Powernode Admin") }
    let!(:user)     { create(:user, account: account, email: "admin@powernode.org") }
    let!(:provider) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }

    it "seeds exactly core's three agents as global, system, source_key-managed canonicals" do
      load_seed!

      seeded = Ai::Agent.global.where(slug: core_slugs)
      expect(seeded.pluck(:slug)).to match_array(core_slugs)
      # An extension's agent (registered into the roster) is that extension's seed, never core's.
      expect(Ai::Agent.global.where(slug: roster.slugs - core_slugs)).to be_empty
      seeded.each do |agent|
        spec = roster.fetch(agent.slug)
        expect(agent).to have_attributes(account_id: nil, is_system: true, source_key: agent.slug,
                                         name: spec[:name], agent_type: spec[:agent_type],
                                         description: spec[:description], is_concierge: false)
        expect(agent.mcp_metadata.dig("model_config", "model_requirements", "tier")).to eq(spec[:tier])
      end
    end

    it "gives each its assembly prompt: at most 25 lines, assemble_task first, no domain knowledge" do
      load_seed!

      core_slugs.each do |slug|
        prompt = survivor(slug).system_prompt
        expect(prompt).to eq(roster.fetch(slug)[:charter].strip), slug
        expect(prompt.lines.size).to be <= 25, "#{slug}'s charter is #{prompt.lines.size} lines"
        expect(prompt).to include("assemble_task", "route_task", "record_agent_execution"), slug
        expect(prompt).not_to include("manifest"), slug
      end
    end

    it "serves the assembly prompt through get_agent, the first call of every thin loader" do
      load_seed!
      tool = Ai::Tools::AgentManagementTool.new(account: account, user: create(:user, account: account, permissions: %w[ai.agents.execute ai.agents.read]))

      core_slugs.each do |slug|
        result = tool.execute(params: { action: "get_agent", slug: slug })

        expect(result[:success]).to be(true), slug
        expect(result[:agent][:system_prompt]).to eq(roster.fetch(slug)[:charter].strip)
        expect(result[:agent][:system_prompt]).to include("assemble_task")
      end
    end

    it "declares each agent's roster tier on the row" do
      load_seed!

      core_slugs.each { |slug| expect(survivor(slug).mcp_metadata.dig("model_config", "model_requirements", "tier")).to eq(roster.fetch(slug)[:tier]) }
    end

    it "scopes platform-side tool access to the bootstrap floor (fails closed, never open)" do
      load_seed!

      core_slugs.each do |slug|
        families = survivor(slug).mcp_metadata.dig("tool_access", "tool_families")
        expect(families).to match_array(Ai::Tools::BootstrapVerbs::ACTIONS + %w[record_agent_execution]), slug
        expect(families).to include("assemble_task"), slug
      end
    end

    it "writes ZERO intervention-policy rows — PolicyReconciler is the single writer" do
      expect { load_seed! }.not_to change(Ai::InterventionPolicy, :count)
    end

    # Posture of the agents each survivor absorbs: Platform Developer and Fleet
    # Autonomy (monitored, a 4h reject-on-timeout chain), Powernode Assistant
    # (trusted, no chain), LLM Judge / System Quality Assurance (no trust row,
    # no chain — supervised by absence).
    it "bootstraps trust and approval chains like the agents each survivor absorbs" do
      load_seed!

      tiers = core_slugs.to_h { |slug| [ slug, Ai::AgentTrustScore.find_by(agent_id: survivor(slug).id)&.tier ] }
      expect(tiers).to eq("powernode-concierge" => "trusted", "platform-engineer" => "monitored", "platform-reviewer" => nil)

      chains = Ai::ApprovalChain.where(account: account, name: [ "Platform Engineer Actions", "Fleet Operator Actions",
                                                                  "Powernode Concierge Actions", "Platform Reviewer Actions" ])
      expect(chains.pluck(:name)).to match_array([ "Platform Engineer Actions" ])
      chains.each do |chain|
        expect(chain).to have_attributes(trigger_type: "autonomy_action", timeout_hours: 4, timeout_action: "reject")
      end
      engineer_approvers = chains.find_by(name: "Platform Engineer Actions").steps.first["approvers"]
      expect(engineer_approvers).to eq([ { "type" => "permission", "value" => "ai.autonomy.approve" } ])
    end

    it "keeps the survivors out of every live resolution (shadow mode)" do
      # The live front door, as its own seed writes it (it binds this global skill).
      create(:ai_skill, :global, slug: "powernode-concierge", name: "Powernode Concierge", is_system: true)
      load_seed!("ai_concierge_seed.rb")
      load_seed!

      expect(Ai::Agent.where(slug: core_slugs).pluck(:status).uniq).to eq([ "inactive" ])
      expect(Ai::Routing::RoutableAgents.for(account.id).map(&:slug)).not_to include(*core_slugs)
      expect(Ai::Agent.resolve_concierge_for(account.id).slug).to eq("powernode-assistant")
      expect(Ai::RalphLoop::PLATFORM_AGENT_DEFAULT_SLUG).to eq("platform-developer")
      # …while the skeletons' get_agent / record_agent_execution lookup still reaches them.
      core_slugs.each { |slug| expect(Ai::Agent.resolve_for(account.id, slug: slug)&.slug).to eq(slug) }
    end

    it "iterates the registry: an agent registered into it by another owner is not seeded by core" do
      registry = Ai::Agents::CanonicalRoster::Registry.new
      roster.each { |slug, spec, owner| registry.register(slug, spec, owner: owner) }
      registry.register("ext-agent", roster.fetch("platform-reviewer").merge(name: "Ext Agent"), owner: "extensions/other")
      allow(roster).to receive(:registry).and_return(registry)

      load_seed!

      expect(Ai::Agent.global.find_by(slug: "ext-agent")).to be_nil
      expect(Ai::Agent.global.where(slug: core_slugs).count).to eq(3)
    end

    it "keeps an operator's activation and edited charter on re-seed" do
      load_seed!
      engineer = survivor("platform-engineer")
      engineer.update!(status: "active")
      engineer.update!(system_prompt: "our own charter")

      load_seed!

      expect(engineer.reload.status).to eq("active")
      expect(engineer.system_prompt).to eq("our own charter")
    end

    it "is idempotent — a second run writes no row and changes no column" do
      load_seed!
      snapshot = lambda do
        [ Ai::Agent.global.where(slug: core_slugs).order(:slug).pluck(:id, :updated_at, :mcp_metadata),
          Ai::AgentTrustScore.order(:id).pluck(:id, :updated_at),
          Ai::ApprovalChain.order(:id).pluck(:id, :updated_at),
          Ai::InterventionPolicy.count ]
      end
      before = snapshot.call

      load_seed!

      expect(snapshot.call).to eq(before)
    end
  end

  context "on a database with no account, user or provider (fresh core install)" do
    it "still seeds the three core canonicals, and nothing account-scoped" do
      expect(Account.count).to eq(0)

      load_seed!

      expect(Ai::Agent.global.where(slug: core_slugs).count).to eq(3)
      expect(Ai::AgentTrustScore.count).to eq(0)
      expect(Ai::ApprovalChain.count).to eq(0)
      expect(Ai::InterventionPolicy.count).to eq(0)
    end
  end

  it "is wired into the baseline seed order after the engineering canonicals, before the hierarchy" do
    order = File.read(Rails.root.join("db", "seeds.rb"))[/%w\[\s*claude_agents_seed(.*?)\]/m, 0].to_s.split

    expect(order).to include("ai_canonical_agents_seed")
    expect(order.index("ai_canonical_agents_seed")).to be > order.index("ai_engineering_agents_seed")
    expect(order.index("ai_canonical_agents_seed")).to be < order.index("ai_agent_hierarchy_seed")
  end
end
