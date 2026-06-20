# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::ProviderCredentialState do
  let(:account) { create(:account) }

  describe ".category_states" do
    it "returns the three provider categories with state shape" do
      states = described_class.category_states(account)

      expect(states.keys).to contain_exactly(:ai, :cloud, :git)
      states.each_value { |s| expect(s).to include(:has_credentials, :count, :available) }
    end

    it "reports has_credentials false for a fresh account" do
      states = described_class.category_states(account)
      expect(states.values.map { |s| s[:has_credentials] }).to all(be(false))
    end
  end

  describe ".has_credentials?" do
    it "is false for a fresh account in every category" do
      %i[ai cloud git].each do |category|
        expect(described_class.has_credentials?(account, category)).to be(false)
      end
    end

    it "is false for an unknown category" do
      expect(described_class.has_credentials?(account, :nope)).to be(false)
    end

    it "treats an absent association (core mode) as no credentials" do
      allow(account).to receive(:respond_to?).and_call_original
      allow(account).to receive(:respond_to?).with(:ai_provider_credentials).and_return(false)

      expect(described_class.has_credentials?(account, :ai)).to be(false)
    end
  end
end
