# frozen_string_literal: true

require "rails_helper"

# The DISCOVERY half of the model-selection learning loop: a deterministic UCB
# exploration term. Pure exploitation (greedy max on the empirical-weighted
# score) lets a model with many samples at a mediocre success rate outscore an
# untried alternative forever — the untried model is never sampled, so a
# genuinely better/cheaper model is never discovered. The exploration bonus
# corrects that.
RSpec.describe Ai::AgentModelSelector, "UCB exploration" do
  let(:account) { create(:account) }

  describe "#exploration_bonus" do
    subject(:selector) { described_class.new(account: account, agent_type: "assistant") }

    it "is zero at true cold-start (no arm has any runs)" do
      expect(selector.send(:exploration_bonus, 0, 0)).to eq(0.0)
    end

    it "rewards under-sampled arms and decays monotonically as a candidate accrues runs" do
      unsampled = selector.send(:exploration_bonus, 0, 100)
      some      = selector.send(:exploration_bonus, 10, 100)
      many      = selector.send(:exploration_bonus, 1000, 100)

      expect(unsampled).to be > some
      expect(some).to be > many
      expect(many).to be >= 0.0
    end

    it "honors the coefficient (0 disables exploration)" do
      stub_const("#{described_class}::EXPLORATION_COEFFICIENT", 0.0)
      expect(selector.send(:exploration_bonus, 0, 100)).to eq(0.0)
    end
  end

  describe ".recommend with a proven-mediocre incumbent vs an untried model" do
    # Two providers, each with one model — identical capabilities + cost, so the
    # ONLY differentiators are empirical history and exploration.
    let(:model_attrs) do
      [ { "id" => "model-incumbent", "name" => "model-incumbent",
          "capabilities" => %w[text_generation chat],
          "cost_per_1k_tokens" => { "input" => 0.001 } } ]
    end
    let(:challenger_attrs) do
      [ { "id" => "model-challenger", "name" => "model-challenger",
          "capabilities" => %w[text_generation chat],
          "cost_per_1k_tokens" => { "input" => 0.001 } } ]
    end

    let!(:incumbent_provider) do
      create(:ai_provider, account: account, provider_type: "openai", is_active: true,
                           capabilities: %w[text_generation chat], supported_models: model_attrs)
    end
    let!(:challenger_provider) do
      create(:ai_provider, account: account, provider_type: "anthropic", is_active: true,
                           capabilities: %w[text_generation chat], supported_models: challenger_attrs)
    end

    before do
      create(:ai_provider_credential, account: account, provider: incumbent_provider)
      create(:ai_provider_credential, account: account, provider: challenger_provider)

      # Incumbent: 50 runs, 40% success — proven mediocre (and confidently so).
      Ai::AgentModelPerformance.create!(
        account: account, provider: incumbent_provider, model: "model-incumbent",
        agent_type: "assistant", total_runs: 50, successful_runs: 20, failed_runs: 30
      )
      # Challenger: no record → untried.
    end

    it "greedily keeps the proven-mediocre incumbent when exploration is OFF" do
      stub_const("#{described_class}::EXPLORATION_COEFFICIENT", 0.0)
      result = described_class.recommend(account: account, agent_type: "assistant")
      expect(result[:model]).to eq("model-incumbent")
    end

    it "discovers (selects) the untried challenger when exploration is ON" do
      # Default coefficient (0.3). The incumbent's confident 0.4 empirical signal
      # would win greedily; the UCB bonus on the untried arm tips selection to it
      # so it can gather its own signal.
      result = described_class.recommend(account: account, agent_type: "assistant")
      expect(result[:model]).to eq("model-challenger")
      expect(result.dig(:score_details, :exploration_bonus)).to be > 0.0
    end

    it "never lets exploration promote a capability-incapable model" do
      # An image-only provider can't satisfy assistant's required text/chat gate;
      # even with a maximal exploration bonus it must not be selected over a
      # capable model.
      incapable = create(:ai_provider, account: account, provider_type: "custom", is_active: true,
                                       capabilities: %w[image_generation],
                                       supported_models: [ { "id" => "img-only", "name" => "img-only",
                                                             "capabilities" => %w[image_generation],
                                                             "cost_per_1k_tokens" => { "input" => 0.0001 } } ])
      create(:ai_provider_credential, account: account, provider: incapable)

      result = described_class.recommend(account: account, agent_type: "assistant")
      expect(result[:model]).not_to eq("img-only")
    end
  end
end
