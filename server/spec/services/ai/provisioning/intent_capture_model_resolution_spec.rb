# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, E3 review F1 + F2 — IntentCaptureService#resolve_model.
#
# E3 removed the literal fallback and returned nil. The review found nil was
# not a refusal: WorkerLlmClient#build_payload ends in `params.compact`, so the
# model key vanished from the request and the worker guessed. It now RAISES
# Ai::Provisioning::NoModelConfiguredError, and #safe_complete reports that on
# the capture/refine result the way the cost-cap refusal already is.
#
# The resolving arms: a configured default, the lightest-tier catalog model
# when none is configured, and a blank configured default falling through to
# that same tier rule (E3b). The tier rule's own oracle, including the
# expensive-first catalog, is spec/models/ai/provider_default_model_spec.rb.
RSpec.describe Ai::Provisioning::IntentCaptureService, "model resolution" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  subject(:service) { described_class.new(account: account, user: user) }

  def bind(provider)
    create(:ai_provider_credential, account: account, provider: provider, is_active: true)
    provider
  end

  # A `custom` provider, deliberately. For "openai" and "anthropic",
  # Ai::Provider::Configurable#set_default_configuration_from_type (a
  # before_validation) OVERWRITES configuration_schema with a hardcoded
  # default_model on create, so for those two types Provider#default_model
  # ALWAYS resolves and the refusal cannot be reached at all. That is a real
  # property of the model, recorded in the E3 review report — not something a
  # spec should paper over by picking the one type where it happens to hold.
  let(:provider) { create(:ai_provider, account: account) }

  describe "#resolve_model" do
    def resolved = service.send(:resolve_model)

    it "uses the credential provider's configured default_model" do
      bind(provider).update_columns(configuration_schema: provider.configuration_schema.merge("default_model" => "configured-model-1"))
      expect(resolved).to eq("configured-model-1")
    end

    it "uses the lightest-tier catalog id when nothing is configured (ties keep catalog order)" do
      bind(provider)
      expect(resolved).to eq("test-model-1")
    end

    it "falls through to the catalog tier rule for a blank-but-present configured default" do
      bind(provider).update_columns(configuration_schema: provider.configuration_schema.merge("default_model" => ""))
      expect(provider.reload.default_model).to eq("test-model-1")
      expect(resolved).to eq("test-model-1")
    end

    it "RAISES when the provider names no model, instead of returning nil" do
      bind(provider).update_columns(supported_models: [])
      expect { resolved }.to raise_error(::Ai::Provisioning::NoModelConfiguredError, /no model configured for account=#{account.id}/)
    end

    it "RAISES when the account has no active credential at all" do
      expect { resolved }.to raise_error(::Ai::Provisioning::NoModelConfiguredError)
    end
  end

  # The part the review said was asserted-but-not-built: the caller REPORTS it.
  describe "#capture reporting" do
    let(:client) { double("llm client") }

    before do
      allow(service).to receive(:llm_client).and_return(client)
      allow(service).to receive(:tracking_agent).and_return(nil)
      allow(::Ai::Provisioning::CostCapGuard).to receive(:allow?).and_return(double(cap_exceeded?: false))
    end

    it "surfaces no_model_configured on the result and makes NO LLM call — both arms" do
      bind(provider).update_columns(supported_models: [])
      expect(client).not_to receive(:complete)

      result = service.capture(natural_language: "three postgres nodes")

      expect(result).to include(no_model_configured: true, reason: "no_model_configured")
      expect(result[:detail]).to include("no model configured")
      expect(result[:brief]).to be_a(Hash), "the refusal must not cost the caller its prior brief"
    end

    it "does not report it when a model resolves, and sends that model" do
      bind(provider)
      sent = nil
      allow(client).to receive(:complete) do |**opts|
        sent = opts[:model]
        double(success?: true, content: "{}")
      end

      result = service.capture(natural_language: "three postgres nodes")

      expect(sent).to eq("test-model-1")
      expect(result).not_to have_key(:no_model_configured)
      expect(result).not_to have_key(:reason)
    end

    it "clears a previous refusal on the next call rather than carrying it forward" do
      bind(provider).update_columns(supported_models: [])
      expect(service.capture(natural_language: "a")).to have_key(:no_model_configured)

      provider.update_columns(supported_models: [ { "id" => "test-model-9", "name" => "test-model-9" } ])
      allow(client).to receive(:complete).and_return(double(success?: true, content: "{}"))
      expect(service.capture(natural_language: "b")).not_to have_key(:no_model_configured)
    end
  end
end
