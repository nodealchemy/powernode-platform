# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Routing::EffortMapper do
  let(:account) { create(:account) }
  let(:effort_model) { "claude-fable-5" }      # adaptive-only → supports_effort?
  let(:legacy_model) { "claude-3-5-sonnet" }   # permissive → no effort param

  it "returns nil for a model that does not accept output_config.effort" do
    result = described_class.resolve(
      account: account, model: legacy_model, messages: [{ role: "user", content: "hi" }]
    )
    expect(result).to be_nil
  end

  it "honors an explicit pin over derivation and default" do
    result = described_class.resolve(
      account: account, model: effort_model, pinned_effort: "max",
      messages: [{ role: "user", content: "trivial hi" }]
    )
    expect(result).to eq("max")
  end

  it "ignores an invalid pin and falls through to the default" do
    result = described_class.resolve(
      account: account, model: effort_model, pinned_effort: "bogus", messages: []
    )
    expect(result).to eq("high")
  end

  it "defaults to high when there is nothing to classify" do
    expect(described_class.resolve(account: account, model: effort_model, messages: [])).to eq("high")
  end

  it "derives a high-end effort from a complex/expert task" do
    heavy = "Analyze, evaluate and optimize the security architecture; refactor for " \
            "scalability and reason about the performance trade-offs. " * 20
    result = described_class.resolve(
      account: account, model: effort_model, task_type: "critical_decision",
      messages: [{ role: "user", content: heavy }]
    )
    expect(%w[high xhigh max]).to include(result)
  end

  it "derives a low-end effort from a trivial task" do
    result = described_class.resolve(
      account: account, model: effort_model, task_type: "classification",
      messages: [{ role: "user", content: "list yes" }]
    )
    expect(%w[low medium]).to include(result)
  end

  it "does NOT persist a TaskComplexityAssessment (classify_preview, no DB write)" do
    expect do
      described_class.resolve(
        account: account, model: effort_model, task_type: "analysis",
        messages: [{ role: "user", content: "analyze this thing please" }]
      )
    end.not_to change(Ai::TaskComplexityAssessment, :count)
  end

  it "maps every complexity level to a valid effort" do
    described_class::COMPLEXITY_TO_EFFORT.each_value do |effort|
      expect(described_class::VALID_EFFORTS).to include(effort)
    end
  end
end
