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

  describe "mutate_skill" do
    include_examples "a fully armed refine gate", "mutate_skill", "dev.prompt_refine"

    before { seed_refine_pair!("dev.prompt_refine") }

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
end
