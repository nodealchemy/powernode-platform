# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Ralph::MakerCheckerPolicy do
  let(:account) { create(:account) }

  # A provider exposing a clean light-tier and a clean reasoning-tier model so the
  # shared selector (Ai::AgentModelSelector / Ai::ModelTiers) resolves distinct
  # cheap/strong picks. Tier prefixes: "gpt-4o-mini" ⇒ :light, "gpt-4o" ⇒ :reasoning.
  let!(:provider) do
    create(:ai_provider, account: account, is_active: true,
           capabilities: %w[text_generation chat],
           supported_models: [
             { "id" => "gpt-4o-mini", "capabilities" => %w[text_generation chat] },
             { "id" => "gpt-4o",      "capabilities" => %w[text_generation chat] }
           ])
  end

  # default_agent: nil keeps the account's provider set clean (the loop factory
  # would otherwise spin up an extra agent + provider, polluting tier selection).
  def loop_with(config)
    create(:ai_ralph_loop, account: account, default_agent: nil, configuration: config)
  end

  describe "#enabled?" do
    it "is opt-in — off by default" do
      expect(described_class.new(loop_with({})).enabled?).to be false
    end

    it "is on when configuration enables it" do
      expect(described_class.new(loop_with("maker_checker" => true)).enabled?).to be true
    end
  end

  describe "cheap_explore_strong_verify preset" do
    subject(:policy) do
      described_class.new(loop_with("maker_checker" => true, "preset" => "cheap_explore_strong_verify"))
    end

    it "selects a cheap (light-tier) maker model" do
      expect(policy.maker_model).to eq("gpt-4o-mini")
    end

    it "selects a strong (reasoning-tier) checker model" do
      expect(policy.checker_model).to eq("gpt-4o")
    end

    it "enforces the self-review ban: the checker model differs from the maker" do
      expect(policy.checker_model).not_to eq(policy.maker_model)
      expect(policy.distinct_checker?).to be true
    end
  end

  describe "#checker_model override" do
    it "honors an explicit configuration override" do
      policy = described_class.new(loop_with("maker_checker" => true, "checker_model" => "custom-verifier"))
      expect(policy.checker_model).to eq("custom-verifier")
    end
  end

  describe "#distinct_checker? (self-review ban) with a single-model account" do
    it "is false when maker and checker would resolve to the same model" do
      acct = create(:account)
      create(:ai_provider, account: acct, is_active: true,
             capabilities: %w[text_generation chat],
             supported_models: [{ "id" => "gpt-4o", "capabilities" => %w[text_generation chat] }])
      loop_rec = create(:ai_ralph_loop, account: acct, default_agent: nil,
                        configuration: { "maker_checker" => true, "preset" => "cheap_explore_strong_verify" })
      policy = described_class.new(loop_rec)

      expect(policy.maker_model).to eq("gpt-4o")
      expect(policy.checker_model).to eq("gpt-4o")
      expect(policy.distinct_checker?).to be false
    end
  end

  describe "#criteria" do
    it "passes through configured criteria as strings" do
      policy = described_class.new(loop_with("maker_checker" => true, "checker_criteria" => %w[accuracy safety]))
      expect(policy.criteria).to eq(%w[accuracy safety])
    end

    it "is empty when unset (evaluator falls back to its defaults)" do
      expect(described_class.new(loop_with("maker_checker" => true)).criteria).to eq([])
    end
  end
end
