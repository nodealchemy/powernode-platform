# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ModelRefusalPromotionService do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }

  def refuse!(n, category: "cyber", agent_type: "code_assistant", model: "claude-fable-5")
    n.times do
      Ai::ModelRefusalEvent.record!(account_id: account.id, provider_id: provider.id,
                                    model: model, agent_type: agent_type, phase: "pre_output",
                                    category: category)
    end
  end

  def promote(fallback_model: "claude-opus-4-8", category: "cyber")
    described_class.new(account_id: account.id).maybe_promote(
      model: "claude-fable-5", agent_type: "code_assistant", category: category, fallback_model: fallback_model
    )
  end

  it "does not promote below the threshold" do
    refuse!(4)
    expect(promote).to be_nil
    expect(Ai::ModelRoutingRule.count).to eq(0)
  end

  it "promotes a pre-route rule at the default threshold (5)" do
    refuse!(5)
    rule = promote
    expect(rule).to be_persisted
    expect(rule.rule_type).to eq("quality_based")
    expect(rule.target["model_names"]).to eq(["claude-opus-4-8"])
    expect(rule.conditions["request_types"]).to eq(["code_assistant"])
    expect(rule.is_active).to be true
  end

  it "is idempotent — re-promotion updates the same rule" do
    refuse!(6)
    r1 = promote
    r2 = promote
    expect(r2.id).to eq(r1.id)
    expect(Ai::ModelRoutingRule.count).to eq(1)
  end

  it "honors a DB-driven threshold from Account#settings" do
    account.update!(settings: { "fable_refusal_promotion_threshold" => 2 })
    refuse!(2)
    expect(promote).to be_persisted
  end

  it "does not promote without a concrete fallback model" do
    refuse!(6)
    expect(promote(fallback_model: nil)).to be_nil
  end

  it "never pre-routes toward the refused model itself" do
    refuse!(6)
    expect(promote(fallback_model: "claude-fable-5")).to be_nil
    expect(Ai::ModelRoutingRule.count).to eq(0)
  end

  it "keys the rule on the model so distinct models get distinct rules (Fable vs Mythos)" do
    refuse!(5, model: "claude-fable-5")
    refuse!(5, model: "claude-mythos-5")

    described_class.new(account_id: account.id).maybe_promote(
      model: "claude-fable-5", agent_type: "code_assistant", category: "cyber", fallback_model: "claude-opus-4-8"
    )
    described_class.new(account_id: account.id).maybe_promote(
      model: "claude-mythos-5", agent_type: "code_assistant", category: "cyber", fallback_model: "claude-opus-4-8"
    )

    names = Ai::ModelRoutingRule.pluck(:name)
    expect(names).to contain_exactly(
      "fable-refusal-preroute:claude-fable-5:code_assistant:cyber",
      "fable-refusal-preroute:claude-mythos-5:code_assistant:cyber"
    )
  end
end
