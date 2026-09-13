# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, E3 review F1 + F2 — AdaptationProposerService#resolve_model.
#
# The review's sharpest finding: this service returned nil for "no model", and
# #safe_complete wraps the call in a BARE `rescue StandardError`, so even a
# raise would have been swallowed into a log line. The fix is two-part and
# both halves are asserted here: #resolve_model raises
# Ai::Provisioning::NoModelConfiguredError, and #safe_complete lets exactly
# that error past its bare rescue so #diff_from_llm can record it as a decline.
RSpec.describe Ai::Provisioning::AdaptationProposerService, "model resolution" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:mission) do
    create(:ai_mission, account: account, created_by: user, mission_type: "infrastructure",
                        custom_phases: [ { "key" => "adapting", "label" => "Adapting", "order" => 0 } ],
                        configuration: { "brief" => { "intent" => "web stack" } })
  end
  subject(:service) { described_class.new(account: account, mission: mission) }

  # A `custom` provider, deliberately. For "openai" and "anthropic",
  # Ai::Provider::Configurable#set_default_configuration_from_type (a
  # before_validation) OVERWRITES configuration_schema with a hardcoded
  # default_model on create, so for those two types Provider#default_model
  # ALWAYS resolves and the refusal cannot be reached at all. That is a real
  # property of the model, recorded in the E3 review report — not something a
  # spec should paper over by picking the one type where it happens to hold.
  let(:provider) { create(:ai_provider, account: account) }

  def bind(provider)
    create(:ai_provider_credential, account: account, provider: provider, is_active: true)
    provider
  end

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

    it "RAISES when nothing resolves, instead of returning nil" do
      bind(provider).update_columns(supported_models: [])
      expect { resolved }.to raise_error(::Ai::Provisioning::NoModelConfiguredError, /AdaptationProposerService/)
    end
  end

  describe "#safe_complete" do
    it "lets NoModelConfiguredError past its bare rescue (the swallow the review found)" do
      client = double("llm client")
      expect(client).not_to receive(:complete)

      expect { service.send(:safe_complete, client, messages: []) }
        .to raise_error(::Ai::Provisioning::NoModelConfiguredError)
    end

    it "still turns an ordinary provider failure into nil — the rescue is narrowed, not removed" do
      bind(provider)
      client = double("llm client")
      allow(client).to receive(:complete).and_raise(StandardError, "upstream 503")

      expect(service.send(:safe_complete, client, messages: [])).to be_nil
    end
  end

  describe "#diff_from_llm reporting" do
    let(:client) { double("llm client") }
    let(:signal) { double("Signal") }

    before do
      allow(service).to receive(:llm_client).and_return(client)
      allow(service).to receive(:build_diff_prompt).and_return("prompt")
    end

    def decline = service.instance_variable_get(:@decline)

    it "records a no_model_configured decline and makes NO LLM call — both arms" do
      expect(client).not_to receive(:complete)

      expect(service.diff_from_llm(signal: signal, change_type: "scale_horizontal")).to be_nil
      expect(decline).to include(reason: "no_model_configured")
      expect(decline[:detail]).to include("no model configured for account=#{account.id}")
    end

    it "does not record it when a model resolves, and sends that model" do
      bind(provider)
      sent = nil
      allow(client).to receive(:complete) do |**opts|
        sent = opts[:model]
        double(success?: true, content: "[]")
      end

      service.diff_from_llm(signal: signal, change_type: "scale_horizontal")

      expect(sent).to eq("test-model-1")
      expect(decline&.dig(:reason)).not_to eq("no_model_configured")
    end
  end
end
