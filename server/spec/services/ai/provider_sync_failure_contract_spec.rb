# frozen_string_literal: true

require "rails_helper"

# What a failed sync leaves behind, on the sweep path and in the text it records.
RSpec.describe "Ai provider sync failure contract" do
  let(:account) { create(:account) }

  describe "the pending sweep disabling a provider" do
    let(:provider) { create(:ai_provider, :ollama, account: account, api_base_url: "http://down.internal:11434") }

    before do
      create(:ai_provider_credential, account: account, provider: provider)
      Ai::ProviderDefaultService.set_default!(provider.reload)
      provider.reload.mark_model_sync_pending!
      stub_request(:get, /down\.internal/).to_return(status: 502, body: "")
    end

    it "heals the account default when its failure deactivates the provider" do
      expect(Ai::ProviderDefaultService).to receive(:heal!).with(account).and_call_original

      Ai::ProviderManagementService.sync_pending_providers

      provider.reload
      expect(provider.is_active).to be(false)
      expect(provider.metadata["is_default"]).to be(false)
    end
  end

  describe "the sweep path for a provider that was already inactive" do
    let(:provider) { create(:ai_provider, :ollama, account: account, api_base_url: "http://down.internal:11434", is_active: false) }

    it "does not heal: nothing it served was taken away" do
      provider.mark_model_sync_pending!
      stub_request(:get, /down\.internal/).to_return(status: 502, body: "")
      expect(Ai::ProviderDefaultService).not_to receive(:heal!)

      Ai::ProviderManagementService.sync_pending_providers
    end
  end

  describe ".redact_sync_error" do
    def redact(text) = Ai::ProviderManagementService.redact_sync_error(text)

    it "drops userinfo, even when the password holds an @" do
      expect(redact("Could not connect to Ollama API at http://ops:p@ss@host:11434/api"))
        .to eq("Could not connect to Ollama API at http://host:11434/api")
    end

    it "drops a URL's query, with or without =" do
      expect(redact("GET https://x.test/v1/models?key=abc&alt=json failed")).to eq("GET https://x.test/v1/models?[FILTERED] failed")
      expect(redact("GET https://x.test/v1/models?sk-bare-token failed")).to eq("GET https://x.test/v1/models?[FILTERED] failed")
    end

    it "keeps prose question marks and @ signs outside a URL" do
      text = "Is the host up? Ask ops@example.test, then retry at http://host:11434."
      expect(redact(text)).to eq(text)
    end
  end
end
