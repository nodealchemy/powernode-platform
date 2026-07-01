# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ModelRefusalEvent do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }

  describe ".record!" do
    it "appends a refusal event with recovery metadata" do
      ev = described_class.record!(
        account_id: account.id, provider_id: provider.id,
        model: "claude-fable-5", agent_type: "code_assistant", phase: "pre_output",
        category: "cyber", reframed: true, fell_back: true, served_by_model: "claude-opus-4-8"
      )
      expect(ev).to be_persisted
      expect(ev.model).to eq("claude-fable-5")
      expect(ev.fell_back).to be true
      expect(ev.served_by_model).to eq("claude-opus-4-8")
    end

    it "returns nil (never raises) when attribution is incomplete" do
      expect(
        described_class.record!(account_id: nil, provider_id: provider.id,
                                model: "m", agent_type: "t", phase: "pre_output")
      ).to be_nil
    end
  end

  it "requires model, agent_type, and phase" do
    ev = described_class.new(account: account, provider: provider)
    expect(ev).not_to be_valid
    expect(ev.errors.attribute_names).to include(:model, :agent_type, :phase)
  end
end
