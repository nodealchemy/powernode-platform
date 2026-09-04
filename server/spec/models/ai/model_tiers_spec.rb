# frozen_string_literal: true

require "rails_helper"

# Specs for the 4-tier price-ladder classifier + supported_models entry
# normalizer + label mapping. Ai::ModelTiers is the single home for tier data,
# the price ladder, and the Hash-vs-String handling shared by the selector,
# router, fallback resolver, Ai::Agent, and Devops::AiConfig.
RSpec.describe Ai::ModelTiers do
  # Persist a synced pricing row (mirrors Ai::ModelPricing columns). Reset the
  # memoized price index so the next classify() rebuilds it with this row present.
  def price!(model_id, input_per_1k, provider_type: "anthropic")
    Ai::ModelPricing.create!(
      model_id: model_id, provider_type: provider_type,
      input_per_1k: input_per_1k, output_per_1k: input_per_1k,
      source: "litellm", last_synced_at: Time.current
    )
    described_class.reset_price_cache!
  end

  describe ".classify prefix tiers (no pricing rows ⇒ prefix floor)" do
    it "classifies claude-sonnet as :standard (the everyday workhorse — moved off reasoning)" do
      expect(described_class.classify("claude-sonnet-5")).to eq(:standard)
      expect(described_class.classify("claude-sonnet-4-20250514")).to eq(:standard)
    end

    it "classifies claude-opus as :reasoning" do
      expect(described_class.classify("claude-opus-4-8")).to eq(:reasoning)
    end

    it "classifies claude-fable-5 as :frontier" do
      expect(described_class.classify("claude-fable-5")).to eq(:frontier)
    end

    it "classifies claude-mythos-5 as :frontier" do
      expect(described_class.classify("claude-mythos-5")).to eq(:frontier)
    end

    it "classifies claude-haiku as :light (Haiku-class)" do
      expect(described_class.classify("claude-haiku-4-5")).to eq(:light)
    end

    # HIER-P1C item 2: the model ids a Claude Code session reports through
    # platform.record_agent_execution (the CC frontmatter aliases opus /
    # sonnet / haiku / fable resolve to these families) classify onto the
    # ladder by family prefix — no per-version literal is needed.
    it "classifies every Claude Code model family a run can report" do
      expect(described_class.classify("claude-opus-5")).to eq(:reasoning)
      expect(described_class.classify("claude-sonnet-5")).to eq(:standard)
      expect(described_class.classify("claude-haiku-4-5")).to eq(:light)
      expect(described_class.classify("claude-fable-5-1")).to eq(:frontier)
    end

    it "classifies gpt-4o as :reasoning" do
      expect(described_class.classify("gpt-4o")).to eq(:reasoning)
    end

    it "classifies gpt-4.1 and gpt-4.1-mini as :standard" do
      expect(described_class.classify("gpt-4.1")).to eq(:standard)
      expect(described_class.classify("gpt-4.1-mini")).to eq(:standard)
    end

    it "classifies gpt-4o-mini as :light via the longest prefix (not :reasoning via gpt-4o)" do
      expect(described_class.classify("gpt-4o-mini")).to eq(:light)
    end

    it "classifies o3 / o3-pro as :reasoning and o3-mini as :standard (longest prefix)" do
      expect(described_class.classify("o3")).to eq(:reasoning)
      expect(described_class.classify("o3-pro")).to eq(:reasoning)
      expect(described_class.classify("o3-mini")).to eq(:standard)
    end

    it "classifies grok-4 / grok-3 as :reasoning and grok-3-mini as :standard (longest prefix)" do
      expect(described_class.classify("grok-4")).to eq(:reasoning)
      expect(described_class.classify("grok-3")).to eq(:reasoning)
      expect(described_class.classify("grok-3-mini")).to eq(:standard)
    end

    it "classifies an llama id as :light" do
      expect(described_class.classify("llama-3.1-70b")).to eq(:light)
    end

    it "defaults an unknown id to :standard" do
      expect(described_class.classify("totally-unknown-model-xyz")).to eq(:standard)
    end

    it "defaults nil to :standard (nil-safe via to_s)" do
      expect(described_class.classify(nil)).to eq(:standard)
    end
  end

  describe ".classify pricing-informed classification" do
    context "unknown families are driven purely by price band" do
      it "maps a frontier-priced unknown model to :frontier" do
        price!("mystery-x", 0.010)
        expect(described_class.classify("mystery-x")).to eq(:frontier)
      end

      it "maps a reasoning-priced unknown model to :reasoning" do
        price!("mystery-x", 0.005)
        expect(described_class.classify("mystery-x")).to eq(:reasoning)
      end

      it "maps a standard-priced unknown model to :standard" do
        price!("mystery-x", 0.002)
        expect(described_class.classify("mystery-x")).to eq(:standard)
      end

      it "maps a light-priced unknown model to :light" do
        price!("mystery-x", 0.0005)
        expect(described_class.classify("mystery-x")).to eq(:light)
      end

      it "resolves price via longest-prefix match against known pricing ids" do
        price!("acme-llm", 0.009)
        expect(described_class.classify("acme-llm-turbo-2026")).to eq(:frontier)
      end
    end

    context "the prefix tier is a FLOOR — price may only escalate a known family" do
      it "rebalances claude-sonnet UP to :reasoning when its price rises 50% (no deploy)" do
        expect(described_class.classify("claude-sonnet-5")).to eq(:standard)
        price!("claude-sonnet-5", 0.0045) # +50% over ~$3/MTok
        expect(described_class.classify("claude-sonnet-5")).to eq(:reasoning)
      end

      it "does NOT demote a known reasoning family when a cheap price row exists" do
        price!("claude-opus-4-8", 0.0005) # bogus/cheap price band ⇒ :light
        expect(described_class.classify("claude-opus-4-8")).to eq(:reasoning)
      end

      it "does NOT demote a known family when the price row is zero" do
        price!("claude-opus-4-8", 0)
        expect(described_class.classify("claude-opus-4-8")).to eq(:reasoning)
      end

      it "keeps a frontier family at :frontier even priced below the frontier band" do
        price!("claude-fable-5", 0.005) # reasoning-band price
        expect(described_class.classify("claude-fable-5")).to eq(:frontier)
      end
    end
  end

  describe ".id_for" do
    it "extracts the id from a Hash with an \"id\" key" do
      expect(described_class.id_for({ "id" => "gpt-4o", "name" => "GPT-4o" })).to eq("gpt-4o")
    end

    it "falls back to the \"name\" key when \"id\" is absent" do
      expect(described_class.id_for({ "name" => "gpt-4o" })).to eq("gpt-4o")
    end

    it "returns a bare String unchanged" do
      expect(described_class.id_for("claude-sonnet-4")).to eq("claude-sonnet-4")
    end

    it "returns nil for an unusable Hash (no id/name)" do
      expect(described_class.id_for({ "context_length" => 4096 })).to be_nil
    end

    it "returns nil for nil" do
      expect(described_class.id_for(nil)).to be_nil
    end
  end

  describe ".max_tier (now including :frontier)" do
    it "picks :frontier over :reasoning" do
      expect(described_class.max_tier(:reasoning, :frontier)).to eq(:frontier)
    end

    it "picks :reasoning over :standard" do
      expect(described_class.max_tier(:reasoning, :standard)).to eq(:reasoning)
    end

    it "picks :standard over :light" do
      expect(described_class.max_tier(:standard, :light)).to eq(:standard)
    end

    it "is order-independent (more capable wins regardless of arg position)" do
      expect(described_class.max_tier(:standard, :frontier)).to eq(:frontier)
    end

    it "returns the non-nil tier when the first is nil" do
      expect(described_class.max_tier(nil, :standard)).to eq(:standard)
    end

    it "returns the non-nil tier when the second is nil" do
      expect(described_class.max_tier(:frontier, nil)).to eq(:frontier)
    end

    it "returns nil when both are nil" do
      expect(described_class.max_tier(nil, nil)).to be_nil
    end

    it "coerces String tiers to symbols" do
      expect(described_class.max_tier("light", "frontier")).to eq(:frontier)
    end
  end

  describe ".from_label / .to_label (router/finops label mapping for inc2)" do
    it "maps economy/standard/premium labels to base ladder tiers" do
      expect(described_class.from_label("economy")).to eq(:light)
      expect(described_class.from_label("standard")).to eq(:standard)
      expect(described_class.from_label("premium")).to eq(:reasoning)
    end

    it "defaults an unknown label to :standard" do
      expect(described_class.from_label("nonsense")).to eq(:standard)
      expect(described_class.from_label(nil)).to eq(:standard)
    end

    it "maps ladder tiers back to labels (frontier folds into premium)" do
      expect(described_class.to_label(:light)).to eq("economy")
      expect(described_class.to_label(:standard)).to eq("standard")
      expect(described_class.to_label(:reasoning)).to eq("premium")
      expect(described_class.to_label(:frontier)).to eq("premium")
    end

    it "accepts string tiers and defaults an unknown/nil tier to standard" do
      expect(described_class.to_label("reasoning")).to eq("premium")
      expect(described_class.to_label(nil)).to eq("standard")
    end
  end
end
