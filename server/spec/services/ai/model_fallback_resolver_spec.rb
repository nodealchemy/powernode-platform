# frozen_string_literal: true

require "rails_helper"

# Dynamically resolves a NON-Fable reasoning-tier fallback for a refused Fable
# request — never a hardcoded model id.
RSpec.describe Ai::ModelFallbackResolver do
  let(:account) { create(:account) }

  let!(:provider) do
    create(:ai_provider, account: account, is_active: true,
           capabilities: %w[text_generation chat],
           supported_models: [
             { "id" => "claude-fable-5", "capabilities" => %w[text_generation chat] },
             { "id" => "claude-opus-4-8", "capabilities" => %w[text_generation chat] },
             { "id" => "gpt-4o-mini", "capabilities" => %w[text_generation chat] }
           ])
  end

  it "returns non-Fable reasoning models, excluding the refused model and Fable/Mythos" do
    result = described_class.reasoning_fallbacks(account: account, agent_type: "code_assistant", exclude: "claude-fable-5")
    expect(result).to include("claude-opus-4-8")
    expect(result).not_to include("claude-fable-5") # would just re-trigger a refusal
    expect(result).not_to include("gpt-4o-mini")     # not reasoning tier
  end

  it "never returns the excluded (refused) model" do
    result = described_class.reasoning_fallbacks(account: account, exclude: "claude-opus-4-8")
    expect(result).not_to include("claude-opus-4-8")
  end

  it "excludes Fable/Mythos even when they are the only reasoning models" do
    acct = create(:account)
    create(:ai_provider, account: acct, is_active: true, capabilities: %w[text_generation chat],
           supported_models: [{ "id" => "claude-fable-5", "capabilities" => %w[text_generation chat] }])
    expect(described_class.reasoning_fallbacks(account: acct, exclude: "claude-fable-5")).to eq([])
  end

  it "is empty for a nil account" do
    expect(described_class.reasoning_fallbacks(account: nil, exclude: "claude-fable-5")).to eq([])
  end
end
