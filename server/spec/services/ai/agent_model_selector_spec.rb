# frozen_string_literal: true

require "rails_helper"

# Selection-logic specs for the shared (provider, model) recommender. These use
# REAL provider/credential records (no empirical AgentModelPerformance rows, so
# scoring stays on deterministic cold-start priors) to prove the candidate-
# provider gating: credentialed-only when any credential exists, all-active as a
# graceful fallback, and provider-constrained when a provider is passed.
RSpec.describe Ai::AgentModelSelector do
  let(:account) { create(:account) }

  describe ".recommend" do
    it "returns a Hash carrying :provider and :model" do
      provider = create(:ai_provider, :openai, account: account)
      create(:ai_provider_credential, account: account, provider: provider)

      result = described_class.recommend(account: account, agent_type: "assistant")

      expect(result).to be_a(Hash)
      expect(result).to include(:provider, :model)
      expect(result[:provider]).to be_a(Ai::Provider)
      expect(result[:model]).to be_present
    end

    # HIER-P1C item 2: the synthetic scope Claude Code runs are recorded under
    # (Ai::ClaudeExport::ExecutionRecorder) carries real model statistics but no
    # platform credential can serve it — never a routing candidate, not even
    # through the fallback's last-resort arm.
    context "with the Claude Code synthetic provider present" do
      let!(:synthetic) do
        create(:ai_provider, account: account, slug: "claude-code", provider_type: "anthropic", is_active: false,
                             supported_models: [], metadata: { "execution_source" => "claude_code" })
      end

      it "is excluded from the candidates and from the fallback even when it is the only provider" do
        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:provider]).to be_nil
        expect(Ai::Provider.platform_routable.where(account: account)).not_to include(synthetic)
      end

      it "still routes to a real credentialed provider beside it" do
        provider = create(:ai_provider, :openai, account: account)
        create(:ai_provider_credential, account: account, provider: provider)

        expect(described_class.recommend(account: account, agent_type: "assistant")[:provider]).to eq(provider)
      end
    end

    context "with no provider argument" do
      it "only considers providers that have an active credential" do
        # Two active providers; only the openai one is credentialed. The selector
        # must confine itself to the credentialed provider even though the other
        # is active and has scorable models.
        credentialed = create(:ai_provider, :openai, account: account)
        _uncredentialed = create(:ai_provider, :anthropic, account: account)
        create(:ai_provider_credential, account: account, provider: credentialed)

        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:provider]).to eq(credentialed)
      end

      it "falls back to all active providers when none are credentialed" do
        # No credentials anywhere — a fresh account should still get a usable
        # recommendation rather than nil.
        provider = create(:ai_provider, :openai, account: account)

        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:provider]).to eq(provider)
        expect(result[:model]).to be_present
      end

      it "does not consider another account's credentialed providers" do
        other_account = create(:account)
        other_provider = create(:ai_provider, :openai, account: other_account)
        create(:ai_provider_credential, account: other_account, provider: other_provider)

        mine = create(:ai_provider, :anthropic, account: account)
        create(:ai_provider_credential, account: account, provider: mine)

        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:provider]).to eq(mine)
      end
    end

    context "with a provider: argument (Ai::Provider)" do
      it "constrains the result to exactly that provider" do
        constrained = create(:ai_provider, :anthropic, account: account)
        # A second, credentialed provider that would otherwise be eligible —
        # the constraint must win and selection must NOT cross to it.
        other = create(:ai_provider, :openai, account: account)
        create(:ai_provider_credential, account: account, provider: other)

        result = described_class.recommend(
          account: account, agent_type: "assistant", provider: constrained
        )

        expect(result[:provider]).to eq(constrained)
      end

      it "picks a model from the constrained provider's own catalog" do
        constrained = create(:ai_provider, :anthropic, account: account)

        result = described_class.recommend(
          account: account, agent_type: "assistant", provider: constrained
        )

        catalog_ids = constrained.supported_models.map { |m| m["id"] || m["name"] }
        expect(catalog_ids).to include(result[:model])
      end

      it "never crosses to another provider even when the constrained one is uncredentialed" do
        constrained = create(:ai_provider, :anthropic, account: account)
        other = create(:ai_provider, :openai, account: account)
        create(:ai_provider_credential, account: account, provider: other)

        result = described_class.recommend(
          account: account, agent_type: "assistant", provider: constrained
        )

        expect(result[:provider]).to eq(constrained)
        expect(result[:provider]).not_to eq(other)
      end
    end
  end

  # 2b — Fable-5 routing preference. Two reasoning-tier models with IDENTICAL
  # base scores (opus first so it wins any cold-start tie); the ONLY thing that
  # can flip selection to Fable is the gated preference bonus. This makes the
  # toggle-off = behavior-neutral guarantee directly observable.
  describe "Fable-5 routing preference" do
    let(:reasoning_models) do
      [
        { "name" => "claude-opus-4-8", "id" => "claude-opus-4-8",
          "cost_per_1k_tokens" => { "input" => 0.005 },
          "capabilities" => %w[text_generation chat code_generation extended_thinking function_calling] },
        { "name" => "claude-fable-5", "id" => "claude-fable-5",
          "cost_per_1k_tokens" => { "input" => 0.010 },
          "capabilities" => %w[text_generation chat code_generation extended_thinking function_calling] }
      ]
    end
    let!(:provider) do
      p = create(:ai_provider, :anthropic, account: account, supported_models: reasoning_models)
      create(:ai_provider_credential, account: account, provider: p)
      p
    end

    context "with the framework OFF (default — inert deploy)" do
      it "selects the same non-Fable model as before and applies NO fable bonus" do
        result = described_class.recommend(account: account, agent_type: "code_assistant")

        expect(result[:model]).to eq("claude-opus-4-8")
        expect(result[:score_details]).not_to have_key(:fable_bonus)
      end

      it "runs no budget query when off (zero cost/perf impact on the inert path)" do
        expect(Ai::AgentExecution).not_to receive(:joins)
        described_class.recommend(account: account, agent_type: "code_assistant")
      end

      it "runs no pre-route query when off (zero extra ModelRoutingRule reads)" do
        expect(Ai::ModelRoutingRule).not_to receive(:for_account)
        described_class.recommend(account: account, agent_type: "code_assistant")
      end
    end

    context "with the framework ON for an allowlisted agent_type" do
      before { account.update!(settings: { "fable_routing_enabled" => true }) }

      it "prefers Fable for a reasoning-tier allowlisted agent_type" do
        result = described_class.recommend(account: account, agent_type: "code_assistant")

        expect(result[:model]).to eq("claude-fable-5")
        expect(result[:score_details][:fable_bonus]).to eq(described_class::FABLE_PREFERENCE_BONUS.round(3))
      end

      it "does NOT prefer Fable for a non-allowlisted agent_type" do
        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:model]).to eq("claude-opus-4-8")
      end

      it "honors an operator allowlist override from Account#settings" do
        # Override excludes code_assistant → the preference must not engage.
        account.update!(settings: { "fable_routing_enabled" => true, "fable_routing_agent_types" => %w[data_analyst] })
        result = described_class.recommend(account: account, agent_type: "code_assistant")

        expect(result[:model]).to eq("claude-opus-4-8")
      end

      it "suppresses the preference when the account budget is >90% consumed" do
        creator = create(:user, account: account)
        budget_agent = create(:ai_agent, account: account, provider: provider, creator: creator)
        create(:ai_agent_execution, account: account, agent: budget_agent, provider: provider, cost_usd: 95)
        account.update!(settings: { "fable_routing_enabled" => true, "ai_monthly_budget" => 100 })

        result = described_class.recommend(account: account, agent_type: "code_assistant")

        expect(result[:model]).to eq("claude-opus-4-8")
      end
    end

    # 3 — inc1 learned pre-route rules must be able to OVERRIDE the preference.
    context "composing with inc1 learned pre-route rules" do
      before { account.update!(settings: { "fable_routing_enabled" => true }) }

      def create_preroute_rule(agent_type:, model: "claude-fable-5", active: true)
        Ai::ModelRoutingRule.create!(
          account: account,
          name: "fable-refusal-preroute:#{model}:#{agent_type}:any",
          rule_type: "quality_based", priority: 100, is_active: active,
          conditions: { "request_types" => [agent_type], "model_patterns" => [Regexp.escape(model)] },
          target: { "model_names" => %w[claude-opus-4-8], "strategy" => "quality_optimized" }
        )
      end

      it "hard-suppresses the preference (learned routing overrides it)" do
        create_preroute_rule(agent_type: "code_assistant")
        result = described_class.recommend(account: account, agent_type: "code_assistant")

        expect(result[:model]).to eq("claude-opus-4-8")
      end

      it "does not suppress when the rule targets a different agent_type" do
        create_preroute_rule(agent_type: "data_analyst")
        result = described_class.recommend(account: account, agent_type: "code_assistant")

        expect(result[:model]).to eq("claude-fable-5")
      end

      it "does not suppress when the rule is inactive" do
        create_preroute_rule(agent_type: "code_assistant", active: false)
        result = described_class.recommend(account: account, agent_type: "code_assistant")

        expect(result[:model]).to eq("claude-fable-5")
      end
    end

    # Candidacy gate: OFF must make Fable NON-SELECTABLE, not merely un-preferred.
    # The UCB exploration term rewards Fable's zero-trial state, so it could win on
    # exploration alone if it stayed in the pool — exclusion is what prevents that.
    context "candidacy gate under maximal UCB exploration" do
      before do
        # Opus accrues a large trial history → high total_observed → Fable's
        # zero-trial exploration bonus is maximal; with Fable in the pool it wins
        # on exploration alone (non-allowlisted agent_type ⇒ no preference bonus).
        Ai::AgentModelPerformance.create!(
          account: account, provider: provider,
          model: "claude-opus-4-8", agent_type: "assistant",
          total_runs: 200, successful_runs: 100
        )
      end

      it "toggle OFF → excludes Fable entirely; never selected despite max UCB" do
        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:model]).to eq("claude-opus-4-8")
      end

      it "toggle ON → Fable re-enters the pool and UCB can select it" do
        account.update!(settings: { "fable_routing_enabled" => true })
        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:model]).to eq("claude-fable-5")
      end
    end

    describe ".default_fable_preferred_agent_types" do
      it "derives from the reasoning-tier profiles (not hardcoded)" do
        expected = described_class::AGENT_TYPE_PROFILES.select { |_t, p| p[:tier] == :reasoning }.keys
        expect(described_class.default_fable_preferred_agent_types).to match_array(expected)
      end
    end
  end

  # Parity fix: the fallback path must not leak a Fable/Mythos default_model when
  # the framework is off (mirrors the models_for_tier default guard).
  describe "#fallback Fable candidacy gate" do
    let(:fallback_provider) do
      p = create(:ai_provider, :anthropic, account: account,
        supported_models: [
          { "id" => "claude-fable-5", "name" => "claude-fable-5" },
          { "id" => "claude-opus-4-8", "name" => "claude-opus-4-8" }
        ])
      # default_model resolution is API/config-driven; pin it deterministically to
      # Fable so we exercise the fallback guard, and inject the instance so fallback
      # uses this exact provider.
      allow(p).to receive(:default_model).and_return("claude-fable-5")
      p
    end
    let(:selector) do
      s = described_class.new(account: account, agent_type: "code_assistant")
      allow(s).to receive(:candidate_providers).and_return([fallback_provider])
      s
    end

    it "does not fall back to a Fable default_model when the framework is off" do
      result = selector.send(:fallback)

      expect(Ai::FableRouting.fable_model?(result[:model])).to be(false)
      expect(result[:model]).to eq("claude-opus-4-8")
    end

    it "returns the Fable default_model when the framework is on" do
      account.update!(settings: { "fable_routing_enabled" => true })
      result = selector.send(:fallback)

      expect(result[:model]).to eq("claude-fable-5")
    end
  end
end
