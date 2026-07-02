# frozen_string_literal: true

require "rails_helper"

# Governed per-task tier router (inc2). Proves the ONE-classification →
# {tier, effort, rationale} contract, the effort-first-before-tier-jump policy,
# both directions of frontier gating, mandatory-rationale fail-closed, pin
# honoring, downgrades, and durable persistence onto Ai::RoutingDecision linked
# to a single Ai::TaskComplexityAssessment.
RSpec.describe Ai::Routing::TaskTierResolver do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, :anthropic, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider, agent_type: "assistant") }
  let(:messages) { [{ role: "user", content: "Do the thing" }] }

  before { Ai::ModelTiers.reset_price_cache! } # prefix-only tiering; no leaked price index

  # Deterministic classifier — the resolver's routing policy is under test here,
  # not the classifier's tuning. Signals shaped like the real preview output.
  def stub_classification(level:, score:, tier: "standard")
    signals = {
      token_density: 0.3, tool_complexity: 0.0, conversation_depth: 0.15,
      content_complexity: 0.5, task_type_baseline: 0.4,
      raw: { token_count: 120, tool_count: 0, message_count: 1 }
    }
    allow_any_instance_of(Ai::Routing::TaskComplexityClassifierService)
      .to receive(:classify_preview)
      .and_return(
        complexity_level: level, complexity_score: score, recommended_tier: tier,
        signals: signals, classifier_version: "1.0.0"
      )
  end

  # Stub model re-selection so tier decisions are isolated from selector scoring.
  def stub_selector(by_tier)
    allow(Ai::AgentModelSelector).to receive(:recommend) do |args|
      { model: by_tier.fetch(args[:requirements][:tier]), provider: provider }
    end
  end

  describe ".enabled_for?" do
    it "is false by default (no account or site setting)" do
      expect(described_class.enabled_for?(account)).to be(false)
    end

    it "honors an account settings opt-in" do
      account.update!(settings: { "ai_task_tier_routing_enabled" => true })
      expect(described_class.enabled_for?(account)).to be(true)
    end

    it "falls back to the SiteSetting global when no account override" do
      allow(SiteSetting).to receive(:get).with("ai_task_tier_routing_enabled").and_return(true)
      expect(described_class.enabled_for?(account)).to be(true)
    end
  end

  describe "#resolve — one classification feeds tier + effort" do
    it "does NOT persist during resolve (pure)" do
      stub_classification(level: "moderate", score: 0.3)
      allow(agent).to receive(:resolved_model).and_return("claude-sonnet-5")
      expect do
        described_class.resolve(account: account, agent: agent, task_type: "analysis", messages: messages)
      end.not_to change(Ai::RoutingDecision, :count)
      expect do
        described_class.resolve(account: account, agent: agent, task_type: "analysis", messages: messages)
      end.not_to change(Ai::TaskComplexityAssessment, :count)
    end

    it "maps moderate → standard and returns a valid effort" do
      stub_classification(level: "moderate", score: 0.3)
      allow(agent).to receive(:resolved_model).and_return("claude-sonnet-5")
      res = described_class.resolve(account: account, agent: agent, task_type: "analysis", messages: messages)
      expect(res.tier).to eq(:standard)
      expect(Ai::Routing::EffortMapper::VALID_EFFORTS + [nil]).to include(res.effort)
    end

    it "holds at baseline when messages are blank (no routing basis)" do
      allow(agent).to receive(:resolved_model).and_return("claude-opus-4-8")
      res = described_class.resolve(account: account, agent: agent, task_type: "analysis", messages: [])
      expect(res.tier).to eq(:reasoning) # opus baseline unchanged
      expect(res.rationale[:decision]).to eq("baseline")
    end
  end

  describe "effort-first before tier-jump" do
    before { allow(agent).to receive(:resolved_model).and_return("claude-sonnet-5") } # standard + effort-capable

    it "holds baseline tier and raises effort when a complex task is below the escalation score" do
      stub_classification(level: "complex", score: 0.50) # < 0.60 threshold
      res = described_class.resolve(account: account, agent: agent, task_type: "code_review", messages: messages)
      expect(res.tier).to eq(:standard)                 # NOT escalated to reasoning
      expect(res.effort).to eq("xhigh")                 # complex → xhigh, in place
      expect(res.rationale.dig(:effort_first, :chosen)).to eq("effort_bump")

      # Governance: an above-default effort choice (xhigh) is never silent — the
      # persisted Ai::RoutingDecision rationale must carry the effort choice.
      decision = res.persist!
      expect(decision.rationale["effort"]).to eq("xhigh")
    end

    it "escalates the tier when a complex task exceeds the escalation score" do
      stub_classification(level: "complex", score: 0.75) # >= 0.60
      stub_selector(reasoning: "claude-opus-4-8")
      res = described_class.resolve(account: account, agent: agent, task_type: "code_review", messages: messages)
      expect(res.tier).to eq(:reasoning)
      expect(res.model).to eq("claude-opus-4-8")
      expect(res.rationale.dig(:effort_first, :chosen)).to eq("tier_escalation")
      expect(res.rationale[:evidence]).to be_present
    end

    it "escalates (cannot effort-bump) when the baseline model is not effort-capable" do
      allow(agent).to receive(:resolved_model).and_return("claude-sonnet-4-6") # standard, NOT effort-capable
      stub_classification(level: "complex", score: 0.50) # below threshold, but no effort lever
      stub_selector(reasoning: "claude-opus-4-8")
      res = described_class.resolve(account: account, agent: agent, task_type: "code_review", messages: messages)
      expect(res.tier).to eq(:reasoning)
      expect(res.rationale.dig(:effort_first, :baseline_supports_effort)).to be(false)
    end
  end

  describe "frontier gating (both directions)" do
    let(:agent) { create(:ai_agent, account: account, provider: provider, agent_type: "code_assistant") }

    before do
      allow(agent).to receive(:resolved_model).and_return("claude-opus-4-8") # reasoning baseline
      stub_classification(level: "expert", score: 0.9, tier: "premium")
    end

    context "gate ON, allowlisted, expert, budget OK (end-to-end via the real selector)" do
      let(:provider) do
        create(:ai_provider, :anthropic, account: account, supported_models: [
          { "id" => "claude-fable-5",
            "capabilities" => %w[text_generation chat code_generation extended_thinking function_calling],
            "cost_per_1k_tokens" => { "input" => 0.01 } },
          { "id" => "claude-opus-4-8",
            "capabilities" => %w[text_generation chat extended_thinking],
            "cost_per_1k_tokens" => { "input" => 0.005 } },
          { "id" => "claude-haiku-4-5",
            "capabilities" => %w[text_generation chat],
            "cost_per_1k_tokens" => { "input" => 0.0008 } }
        ])
      end

      before do
        create(:ai_provider_credential, account: account, provider: provider)
        account.update!(settings: { "fable_routing_enabled" => true })
      end

      it "selects a frontier (Fable) model WITH a non-empty rationale" do
        res = described_class.resolve(account: account, agent: agent, task_type: "code_review", messages: messages)
        expect(res.tier).to eq(:frontier)
        expect(res.model).to start_with("claude-fable")
        expect(res.effort).to eq("max")                   # expert → max
        expect(res.rationale[:evidence]).to be_present
        expect(res.rationale.dig(:gates, :fable_routing_enabled)).to be(true)

        # Governance: max effort is never silent — the persisted rationale must
        # carry the effort choice.
        decision = res.persist!
        expect(decision.rationale["effort"]).to eq("max")
      end
    end

    it "NEVER escalates to frontier when the Fable gate is OFF (caps to reasoning)" do
      account.update!(settings: { "fable_routing_enabled" => false })
      stub_selector(reasoning: "claude-opus-4-8")
      res = described_class.resolve(account: account, agent: agent, task_type: "code_review", messages: messages)
      expect(res.tier).to eq(:reasoning)
      expect(res.rationale.dig(:gates, :fable_routing_enabled)).to be(false)
      expect(res.rationale[:evidence].join(" ")).to match(/frontier/i)
    end

    it "caps to reasoning when the agent_type is not allowlisted even with the gate ON" do
      other = create(:ai_agent, account: account, provider: provider, agent_type: "monitor")
      allow(other).to receive(:resolved_model).and_return("claude-opus-4-8")
      account.update!(settings: { "fable_routing_enabled" => true })
      stub_selector(reasoning: "claude-opus-4-8")
      res = described_class.resolve(account: account, agent: other, task_type: "analysis", messages: messages)
      expect(res.tier).not_to eq(:frontier)
    end
  end

  describe "mandatory rationale (fail-closed)" do
    before { allow(agent).to receive(:resolved_model).and_return("claude-sonnet-5") }

    it "every escalation carries non-empty rationale evidence" do
      stub_classification(level: "complex", score: 0.9)
      stub_selector(reasoning: "claude-opus-4-8")
      res = described_class.resolve(account: account, agent: agent, task_type: "code_review", messages: messages)
      expect(res.escalated?).to be(true)
      expect(res.rationale[:evidence]).to be_present
    end

    it "fails closed to the cheaper tier when the escalation justification is empty" do
      stub_classification(level: "complex", score: 0.9)
      allow_any_instance_of(described_class).to receive(:escalation_justification).and_return([])
      res = described_class.resolve(account: account, agent: agent, task_type: "code_review", messages: messages)
      expect(res.tier).to eq(:standard) # held at baseline, not escalated
      expect(res.escalated?).to be(false)
    end
  end

  describe "downgrade (selector-chosen only)" do
    it "downgrades a reasoning-baseline agent on a trivial task and records rationale" do
      allow(agent).to receive(:resolved_model).and_return("claude-opus-4-8") # reasoning baseline
      stub_classification(level: "trivial", score: 0.05, tier: "economy")
      stub_selector(light: "claude-haiku-4-5")
      res = described_class.resolve(account: account, agent: agent, task_type: "classification", messages: messages)
      expect(res.tier).to eq(:light)
      expect(res.downgraded?).to be(true)
      expect(res.rationale[:decision]).to eq("downgrade")
      expect(res.rationale[:evidence]).to be_present
    end
  end

  describe "pin honoring" do
    it "honors a model pin (no re-selection) and records the pin as the reason" do
      allow(agent).to receive(:mcp_metadata).and_return({ "model_config" => { "model" => "claude-opus-4-8" } })
      allow(agent).to receive(:resolved_model).and_return("claude-opus-4-8")
      stub_classification(level: "trivial", score: 0.05, tier: "economy")
      expect(Ai::AgentModelSelector).not_to receive(:recommend)
      res = described_class.resolve(account: account, agent: agent, task_type: "classification", messages: messages)
      expect(res.model).to eq("claude-opus-4-8")
      expect(res.rationale[:decision]).to eq("pinned")
      expect(res.rationale[:evidence]).to be_present
    end
  end

  describe "#persist! — durable governance record" do
    before do
      allow(agent).to receive(:resolved_model).and_return("claude-sonnet-5")
      stub_classification(level: "complex", score: 0.75)
      stub_selector(reasoning: "claude-opus-4-8")
    end

    it "creates ONE assessment and ONE routing decision, bidirectionally linked, with rationale" do
      res = described_class.resolve(account: account, agent: agent, task_type: "code_review", messages: messages)
      decision = nil
      expect do
        decision = res.persist!
      end.to change(Ai::RoutingDecision, :count).by(1)
        .and change(Ai::TaskComplexityAssessment, :count).by(1)

      assessment = decision.complexity_assessment
      expect(assessment).to be_present
      expect(assessment.routing_decision_id).to eq(decision.id)
      expect(decision.rationale).to be_present
      expect(decision.rationale["decision"]).to eq("escalate")
      expect(decision.model_tier).to eq("reasoning")
      expect(assessment.actual_tier_used).to eq("premium") # to_label(:reasoning)
      expect(assessment.recommended_tier).to eq("standard") # classifier's raw recommendation
    end
  end
end
