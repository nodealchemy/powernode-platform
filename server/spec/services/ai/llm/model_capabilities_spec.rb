# frozen_string_literal: true

require "rails_helper"

# Pure unit specs for the model-capability resolver. Stateless module, no DB.
# Mirrors worker/spec/services/ai/llm/model_capabilities_spec.rb — keep in sync.
RSpec.describe Ai::Llm::ModelCapabilities do
  describe "adaptive-only reasoning models" do
    %w[claude-fable-5 claude-mythos-5 claude-opus-4-7 claude-opus-4-8 claude-sonnet-5].each do |model|
      it "classifies #{model} as sampling-forbidden, adaptive-only, effort-capable, prefill-forbidden" do
        expect(described_class.supports_sampling_params?(model)).to be(false)
        expect(described_class.thinking_mode(model)).to eq(:adaptive_only)
        expect(described_class.supports_effort?(model)).to be(true)
        expect(described_class.supports_prefill?(model)).to be(false)
        expect(described_class.max_output_tokens(model)).to eq(128_000)
        expect(described_class.context_window(model)).to eq(1_000_000)
      end
    end

    it "matches dated / point-release ids by prefix" do
      expect(described_class.supports_sampling_params?("claude-fable-5-20260701")).to be(false)
      expect(described_class.thinking_mode("claude-opus-4-8-20260101")).to eq(:adaptive_only)
    end
  end

  describe "permissive / legacy models" do
    %w[claude-opus-4-6 claude-sonnet-4-6 claude-haiku-4-5 claude-3-5-sonnet gpt-4o grok-3].each do |model|
      it "keeps today's permissive behavior for #{model}" do
        expect(described_class.supports_sampling_params?(model)).to be(true)
        expect(described_class.thinking_mode(model)).to eq(:configurable)
        expect(described_class.supports_effort?(model)).to be(false)
        expect(described_class.supports_prefill?(model)).to be(true)
      end
    end

    it "does not misclassify sonnet-4-x as the sonnet-5 reasoning tier" do
      expect(described_class.thinking_mode("claude-sonnet-4-5")).to eq(:configurable)
    end
  end

  describe ".refusal_capable? (adapt→fallback framework gate)" do
    %w[claude-fable-5 claude-mythos-5 claude-fable-5-20260701].each do |model|
      it "is true for the refusal-classifier model #{model}" do
        expect(described_class.refusal_capable?(model)).to be(true)
      end
    end

    %w[claude-opus-4-8 claude-opus-4-7 claude-sonnet-5 claude-opus-4-6 gpt-4o].each do |model|
      it "is false for #{model}" do
        expect(described_class.refusal_capable?(model)).to be(false)
      end
    end
  end
end
