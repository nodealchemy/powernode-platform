# frozen_string_literal: true

require "rails_helper"

# Selection-logic specs for the shared (provider, model) recommender. These use
# REAL provider/credential records (no empirical AgentModelPerformance rows, so
# scoring stays on deterministic cold-start priors) to prove the candidate-
# provider gating: credentialed-only when any credential exists, all-active as a
# graceful fallback, and provider-constrained when a provider is passed.
RSpec.describe Ai::AgentModelSelector do
  let(:account) { create(:account) }

  describe ".recommend" do
    it "returns a Hash carrying :provider and :model" do
      provider = create(:ai_provider, :openai, account: account)
      create(:ai_provider_credential, account: account, provider: provider)

      result = described_class.recommend(account: account, agent_type: "assistant")

      expect(result).to be_a(Hash)
      expect(result).to include(:provider, :model)
      expect(result[:provider]).to be_a(Ai::Provider)
      expect(result[:model]).to be_present
    end

    context "with no provider argument" do
      it "only considers providers that have an active credential" do
        # Two active providers; only the openai one is credentialed. The selector
        # must confine itself to the credentialed provider even though the other
        # is active and has scorable models.
        credentialed = create(:ai_provider, :openai, account: account)
        _uncredentialed = create(:ai_provider, :anthropic, account: account)
        create(:ai_provider_credential, account: account, provider: credentialed)

        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:provider]).to eq(credentialed)
      end

      it "falls back to all active providers when none are credentialed" do
        # No credentials anywhere — a fresh account should still get a usable
        # recommendation rather than nil.
        provider = create(:ai_provider, :openai, account: account)

        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:provider]).to eq(provider)
        expect(result[:model]).to be_present
      end

      it "does not consider another account's credentialed providers" do
        other_account = create(:account)
        other_provider = create(:ai_provider, :openai, account: other_account)
        create(:ai_provider_credential, account: other_account, provider: other_provider)

        mine = create(:ai_provider, :anthropic, account: account)
        create(:ai_provider_credential, account: account, provider: mine)

        result = described_class.recommend(account: account, agent_type: "assistant")

        expect(result[:provider]).to eq(mine)
      end
    end

    context "with a provider: argument (Ai::Provider)" do
      it "constrains the result to exactly that provider" do
        constrained = create(:ai_provider, :anthropic, account: account)
        # A second, credentialed provider that would otherwise be eligible —
        # the constraint must win and selection must NOT cross to it.
        other = create(:ai_provider, :openai, account: account)
        create(:ai_provider_credential, account: account, provider: other)

        result = described_class.recommend(
          account: account, agent_type: "assistant", provider: constrained
        )

        expect(result[:provider]).to eq(constrained)
      end

      it "picks a model from the constrained provider's own catalog" do
        constrained = create(:ai_provider, :anthropic, account: account)

        result = described_class.recommend(
          account: account, agent_type: "assistant", provider: constrained
        )

        catalog_ids = constrained.supported_models.map { |m| m["id"] || m["name"] }
        expect(catalog_ids).to include(result[:model])
      end

      it "never crosses to another provider even when the constrained one is uncredentialed" do
        constrained = create(:ai_provider, :anthropic, account: account)
        other = create(:ai_provider, :openai, account: account)
        create(:ai_provider_credential, account: account, provider: other)

        result = described_class.recommend(
          account: account, agent_type: "assistant", provider: constrained
        )

        expect(result[:provider]).to eq(constrained)
        expect(result[:provider]).not_to eq(other)
      end
    end
  end
end
