# frozen_string_literal: true

require "rails_helper"

# HIER-P2B-ENG — the two refine verbs are approval-gated on the engineering
# policy set's trust-conditioned categories:
#
#   mutate_skill      -> dev.prompt_refine  (one skill's prompt, one strategy)
#   auto_evolve_skill -> dev.skill_refine   (every underperforming skill)
#
# Operator ruling 2026-09-03 #3: skill and prompt refinements AUTO-APPROVE on
# trusted agents and require approval below that. The verdict is carried by
# the EXISTING conditions mechanism — a row pair per category on the owning
# agent (auto_approve with trust_tier_minimum "trusted" at the higher
# priority, an unconditioned require_approval beneath it) — so a supervised
# Platform Developer parks and a trusted one proceeds through the same
# declaration, with nothing new in the gate.
#
# The generic replay executor re-invokes the action as the ORIGINAL principal
# on approval, so the action body stays the single author of the write, and
# the gate context resolves the skill under the account BEFORE parking so an
# unknown or foreign id keeps its inline error instead of becoming an
# approval that could only ever fail.
#
# THE ORACLE IS THE SERVICE CALL: every gated example observes whether
# Ai::SelfImprovement::SkillMutationService was reached, so "gated" cannot be
# satisfied by a verb that refuses everything.
#
# THE ACCOUNT-WIDE FLOORS (IMP-a51963f8717f, proposal §5 ruling 11c). An
# agent-scoped row matches only the agent it names, and the principals that
# legitimately refine a skill over MCP carry none: an operator's Claude Code
# session (an `mcp_client` identity) and a dev-cell instance principal (no
# user, no agent). Without a floor both met the unmatched require_approval
# default and parked where they previously ran. One scope-"global"
# auto_approve row per category, written by the same seam as the
# release.build_dispatch floor, carries their verdict; the agent-scoped pairs
# OUTRANK it (Ai::InterventionPolicy#specificity_key ranks an agent row above
# any global row whatever its priority), so a seeded agent's trust-conditioned
# verdict is unchanged.
RSpec.describe Ai::Tools::SelfImprovementTool, "refine verb gating (HIER-P2B-ENG)" do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account, permissions: %w[ai.skills.read ai.skills.update]) }
  let(:agent)   { create(:ai_agent, account: account, name: "Platform Developer", agent_type: "code_assistant") }
  let(:tool)    { described_class.new(account: account, user: user, agent: agent) }
  let!(:skill)  { create(:ai_skill, account: account, slug: "refine-me", name: "Refine Me") }

  let(:service) { instance_double(Ai::SelfImprovement::SkillMutationService) }

  before do
    allow(Ai::SelfImprovement::SkillMutationService).to receive(:new).and_return(service)
    allow(service).to receive(:mutate!).and_return(double("version", id: SecureRandom.uuid))
    allow(service).to receive(:auto_mutate_underperforming!).and_return(2)
  end

  # The seed's shape for one refine category: the trusted auto_approve row
  # above an unconditioned require_approval row.
  def seed_refine_pair!(category)
    Ai::InterventionPolicy.create!(
      account: account, scope: "agent", ai_agent_id: agent.id, action_category: category,
      policy: "auto_approve", priority: 20, is_active: true,
      conditions: { "trust_tier_minimum" => "trusted" }, preferred_channels: %w[notification]
    )
    Ai::InterventionPolicy.create!(
      account: account, scope: "agent", ai_agent_id: agent.id, action_category: category,
      policy: "require_approval", priority: 10, is_active: true, conditions: {}, preferred_channels: %w[notification]
    )
  end

  # The factory's default IS the supervised tier (no trait for it).
  def trust!(tier)
    traits = tier.to_sym == :supervised ? [] : [ tier.to_sym ]
    create(:ai_agent_trust_score, *traits, account: account, agent: agent)
  end

  def pending_ops
    Ai::DeferredOperation.where(account_id: account.id, status: "pending")
  end

  def mutate!(with: tool, **extra)
    with.execute(params: { action: "mutate_skill", skill_id: skill.id, strategy: "rephrase" }.merge(extra).with_indifferent_access)
  end

  def evolve!(with: tool, **extra)
    with.execute(params: { action: "auto_evolve_skill", threshold: 0.3 }.merge(extra).with_indifferent_access)
  end

  # The account-wide floors, through the one seam that writes them.
  def seed_floors!
    Ai::Engineering::ReleaseDispatchFloorSeeder.ensure_for!(account)
  end

  # An operator's Claude Code session: its MCP principal is an `mcp_client`
  # identity minted by Ai::McpClientIdentityService — an agent that owns no
  # policy row — acting for the operator's own user.
  def mcp_client_tool
    described_class.new(account: account, user: user,
                        agent: create(:ai_agent, :mcp_client, account: account, name: "claude-code-1"))
  end

  # A dev-cell instance principal (mTLS node cert): no user and no agent at
  # all, marked the way McpPlatformToolRegistrar marks it after the grant
  # gate, with the node instance the auto-approve replay re-resolves through
  # Mcp::Principal (a restricted principal WITHOUT one is federation-shaped
  # and refused as unreplayable before the gate — a different contract).
  let(:node_instance) { double("NodeInstance", id: "aa11bb22-0000-4000-8000-000000000002", account: account) }

  def instance_principal_tool
    ::Mcp::Principal.instance_resolver = ->(cn) { cn == node_instance.id ? node_instance : nil }
    ::Mcp::Principal.tool_grant_resolver = ->(_instance) { %w[platform.mutate_skill platform.auto_evolve_skill] }
    described_class.new(account: account).tap do |t|
      t.instance_authorized = true
      t.node_instance = node_instance
    end
  end

  after { ::Mcp::Principal.reset! }

  shared_examples "a fully armed refine gate" do |action, category|
    it "arms #{action} with the full quartet on the generic replay executor under #{category}" do
      declaration = described_class.declared_action(action)

      expect(declaration).to be_present
      aggregate_failures do
        expect(declaration[:mutating]).to be(true)
        expect(declaration[:action_category]).to eq(category)
        expect(declaration[:executor_class]).to eq("Ai::Executors::DeferredToolCall")
        expect(declaration[:gate_context]).to be_present
        expect(declaration[:on_proceed]).to be_present
      end
    end

    it "registers #{category} as a core intervention category" do
      expect(Ai::InterventionPolicy.category_registered?(category)).to be(true)
    end

    it "announces the gate in the description an agent reads" do
      description = described_class.action_definitions.fetch(action)[:description]

      expect(description).to include(category)
      expect(description).to match(/pending/i)
      expect(description).to include("when policy requires approval")
    end
  end

  # The floor's contract for one refine verb. `invoke` calls the verb through
  # a given tool; `service_method` is the oracle the verb must reach.
  shared_examples "a floored refine verb" do |category, service_method|
    it "parks a row-less mcp_client identity while the floor is ABSENT — the floor is what carries its verdict" do
      result = invoke.call(mcp_client_tool)

      expect(result[:success]).to be(true)
      expect(result[:data][:pending]).to be(true)
      expect(result[:data][:action_category]).to eq(category)
      expect(service).not_to have_received(service_method)
    end

    context "with the account-wide floor" do
      before { seed_floors! }

      it "proceeds for an operator's mcp_client identity, which owns no row of its own" do
        result = invoke.call(mcp_client_tool)

        expect(result[:success]).to be(true)
        expect(result[:data][:pending]).to be_nil
        expect(service).to have_received(service_method)
        expect(pending_ops).to be_empty
      end

      it "proceeds for an instance principal — no user, no agent" do
        result = invoke.call(instance_principal_tool)

        expect(result[:success]).to be(true), result.inspect
        expect(result[:data][:pending]).to be_nil
        expect(service).to have_received(service_method)
        expect(pending_ops).to be_empty
      end

      it "still parks a SUPERVISED agent that carries its own row pair — the agent row outranks the floor" do
        trust!(:monitored)

        result = invoke.call(tool)

        expect(result[:success]).to be(true)
        expect(result[:data][:pending]).to be(true)
        expect(service).not_to have_received(service_method)
        expect(pending_ops.count).to eq(1)
      end

      it "still proceeds for the TRUSTED agent through its own conditioned row" do
        trust!(:trusted)

        result = invoke.call(tool)

        expect(result[:success]).to be(true)
        expect(result[:data][:pending]).to be_nil
        expect(service).to have_received(service_method)
      end
    end
  end

  describe "mutate_skill" do
    include_examples "a fully armed refine gate", "mutate_skill", "dev.prompt_refine"

    before { seed_refine_pair!("dev.prompt_refine") }

    include_examples "a floored refine verb", "dev.prompt_refine", :mutate! do
      let(:invoke) { ->(with) { mutate!(with: with) } }
    end

    it "parks a SUPERVISED agent's mutation: nothing mutated, one pending operation naming the category" do
      trust!(:monitored)

      result = mutate!

      expect(result[:success]).to be(true)
      expect(result[:data][:pending]).to be(true)
      expect(result[:data][:action_category]).to eq("dev.prompt_refine")
      expect(service).not_to have_received(:mutate!)
      expect(pending_ops.count).to eq(1)
      expect(pending_ops.first.executor_class).to eq("Ai::Executors::DeferredToolCall")
    end

    it "proceeds for a TRUSTED agent through the same declaration, with the tool's own envelope" do
      trust!(:trusted)

      result = mutate!

      expect(result[:success]).to be(true)
      expect(result[:data][:pending]).to be_nil
      expect(result[:data][:version_id]).to be_present
      expect(result[:data][:strategy]).to eq("rephrase")
      expect(service).to have_received(:mutate!).with(skill: skill, strategy: "rephrase")
      expect(pending_ops).to be_empty
    end

    it "replays the parked mutation as the ORIGINAL principal once approved" do
      trust!(:monitored)
      mutate!
      operation = pending_ops.first

      operation.update!(status: "approved")
      operation.execute_now!

      expect(service).to have_received(:mutate!).with(skill: skill, strategy: "rephrase")
      expect(operation.reload.status).to eq("completed")
    end

    it "keeps the inline error for an unknown or foreign skill and parks nothing" do
      trust!(:monitored)
      foreign = create(:ai_skill, account: create(:account), slug: "not-mine")

      [ SecureRandom.uuid, foreign.id ].each do |id|
        result = mutate!(skill_id: id)

        expect(result[:success]).to be(false)
        expect(result[:error]).to include("Skill not found")
      end
      expect(pending_ops).to be_empty
    end

    it "still refuses a caller without ai.skills.update BEFORE the gate" do
      trust!(:trusted)
      nobody = create(:user, account: account, permissions: %w[ai.skills.read])

      result = mutate!(with: described_class.new(account: account, user: nobody, agent: agent))

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("permission denied")
      expect(Ai::DeferredOperation.where(account_id: account.id)).to be_empty
    end
  end

  describe "auto_evolve_skill" do
    include_examples "a fully armed refine gate", "auto_evolve_skill", "dev.skill_refine"

    before { seed_refine_pair!("dev.skill_refine") }

    include_examples "a floored refine verb", "dev.skill_refine", :auto_mutate_underperforming! do
      let(:invoke) { ->(with) { evolve!(with: with) } }
    end

    it "parks a SUPERVISED agent's evolution sweep" do
      trust!(:supervised)

      result = evolve!

      expect(result[:success]).to be(true)
      expect(result[:data][:pending]).to be(true)
      expect(result[:data][:action_category]).to eq("dev.skill_refine")
      expect(service).not_to have_received(:auto_mutate_underperforming!)
      expect(pending_ops.count).to eq(1)
    end

    it "proceeds for a TRUSTED agent and reports what the sweep mutated" do
      trust!(:trusted)

      result = evolve!

      expect(result[:success]).to be(true)
      expect(result[:data][:skills_mutated]).to eq(2)
      expect(service).to have_received(:auto_mutate_underperforming!).with(threshold: 0.3)
    end

    it "keeps the inline error for a non-numeric threshold and parks nothing" do
      trust!(:supervised)

      result = evolve!(threshold: "lots")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("threshold")
      expect(pending_ops).to be_empty
    end
  end

  describe "what the floors do NOT cover" do
    before { seed_floors! }

    it "leaves release.promote / release.rollback / release.deploy_platform at the require_approval default for a row-less caller" do
      resolver = Ai::InterventionPolicyService.new(account: account)

      %w[release.promote release.rollback release.deploy_platform].each do |category|
        expect(resolver.resolve(action_category: category)[:policy]).to eq("require_approval"),
                                                                        "#{category} must keep parking"
      end
    end
  end
end
