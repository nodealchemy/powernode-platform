# frozen_string_literal: true

require "rails_helper"

# Pure unit specs for the model capability-tier classifier + supported_models
# entry normalizer. No DB records needed — Ai::ModelTiers is a stateless module
# (the single home for tier data + Hash-vs-String handling shared by the
# selector, Ai::Agent, and Devops::AiConfig).
RSpec.describe Ai::ModelTiers do
  describe ".classify" do
    it "classifies a claude-sonnet id as :reasoning" do
      expect(described_class.classify("claude-sonnet-4-20250514")).to eq(:reasoning)
    end

    it "classifies a claude-opus id as :reasoning" do
      expect(described_class.classify("claude-opus-4-20250514")).to eq(:reasoning)
    end

    it "classifies claude-fable-5 as :reasoning" do
      expect(described_class.classify("claude-fable-5")).to eq(:reasoning)
    end

    it "classifies claude-mythos-5 as :reasoning" do
      expect(described_class.classify("claude-mythos-5")).to eq(:reasoning)
    end

    it "classifies a gpt-4o id as :reasoning" do
      expect(described_class.classify("gpt-4o")).to eq(:reasoning)
    end

    it "classifies a gpt-4.1-mini id as :standard" do
      expect(described_class.classify("gpt-4.1-mini")).to eq(:standard)
    end

    it "classifies a gpt-4o-mini id as :light" do
      expect(described_class.classify("gpt-4o-mini")).to eq(:light)
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

  describe ".max_tier" do
    it "picks :reasoning over :standard" do
      expect(described_class.max_tier(:reasoning, :standard)).to eq(:reasoning)
    end

    it "picks :standard over :light" do
      expect(described_class.max_tier(:standard, :light)).to eq(:standard)
    end

    it "picks :reasoning over :light" do
      expect(described_class.max_tier(:light, :reasoning)).to eq(:reasoning)
    end

    it "is order-independent (more capable wins regardless of arg position)" do
      expect(described_class.max_tier(:standard, :reasoning)).to eq(:reasoning)
    end

    it "returns the non-nil tier when the first is nil" do
      expect(described_class.max_tier(nil, :standard)).to eq(:standard)
    end

    it "returns the non-nil tier when the second is nil" do
      expect(described_class.max_tier(:light, nil)).to eq(:light)
    end

    it "returns nil when both are nil" do
      expect(described_class.max_tier(nil, nil)).to be_nil
    end

    it "coerces String tiers to symbols" do
      expect(described_class.max_tier("light", "reasoning")).to eq(:reasoning)
    end
  end
end
