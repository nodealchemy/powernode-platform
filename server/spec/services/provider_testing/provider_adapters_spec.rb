# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, E3 + E3 review F2/F3.
#
# WHAT THIS FILE USED TO TEST IS GONE. It exercised the `test_*_connection`
# family, reachable only through `#perform_test`, which had zero callers in
# app/, spec/ or extensions/ (E3 review F3). The live entry point is
# `#perform_connection_test` (ConnectionTesting#test_connection), and it is
# the family E3 actually changed — so the old green tallies were green on
# code E3 never touched.
#
# What is tested now is the one behaviour E3 changed on the LIVE family: the
# model a connection test sends comes from the credential or the provider,
# never a literal, and nothing configured is a configuration_error with NO
# request sent. Four resolving arms:
#
#   1. the credential's own `model` override;
#   2. the provider's configured default (configuration_schema["default_model"]);
#   3. no configured default: Ai::Provider#default_model picks the LIGHTEST-tier
#      catalog model itself, catalog order breaking ties (E3b ruling);
#   4. a BLANK-but-present configured default is treated as absent and falls
#      through to the same tier rule. There is deliberately no
#      `|| available_models.first` arm any more: that is catalog[0], which sync
#      orders most-expensive-first. The tier rule's own oracle is
#      spec/models/ai/provider_default_model_spec.rb.
RSpec.describe ProviderTesting::ProviderAdapters do
  let(:account) { create(:account) }

  def service_for(provider, credentials: { "api_key" => "sk-test-key" })
    credential = create(:ai_provider_credential, provider: provider, account: account,
                                                 is_active: true, credentials: credentials)
    Ai::ProviderManagementService.new(credential)
  end

  # Runs the live tester with the HTTP layer stubbed, and returns the result
  # plus the model the tester PUT ON THE WIRE (nil when no request was made).
  def run(service, method)
    sent = :no_request
    allow(service).to receive(:make_http_request) do |_url, **opts|
      sent = JSON.parse(opts[:body])["model"]
      double("response", success?: false, code: 401, message: "Unauthorized",
                         body: { error: { message: "bad key" } }.to_json)
    end
    [ service.send(method, service.credential.credentials), sent ]
  end

  # A `custom` provider, deliberately. For "openai" and "anthropic",
  # Ai::Provider::Configurable#set_default_configuration_from_type (a
  # before_validation) OVERWRITES configuration_schema with a hardcoded
  # default_model on create, so for those two types Provider#default_model
  # ALWAYS resolves and the refusal cannot be reached at all. That is a real
  # property of the model, recorded in the E3 review report — not something a
  # spec should paper over by picking the one type where it happens to hold.
  # The testers never read provider_type, so one custom provider serves both.
  %i[perform_openai_connection_test perform_anthropic_connection_test].each do |tester|
    describe "##{tester}" do
      let(:provider) { create(:ai_provider, account: account) }

      it "sends the credential's own model override first" do
        _, sent = run(service_for(provider, credentials: { "api_key" => "sk-test-key-0123456789", "model" => "override-model-1" }), tester)
        expect(sent).to eq("override-model-1")
      end

      it "sends the provider's configured default_model" do
        provider.update_columns(configuration_schema: provider.configuration_schema.merge("default_model" => "configured-model-1"))
        _, sent = run(service_for(provider), tester)
        expect(sent).to eq("configured-model-1")
      end

      it "sends the lightest-tier catalog id when nothing is configured (ties keep catalog order)" do
        _, sent = run(service_for(provider), tester)
        expect(sent).to eq("test-model-1")
      end

      it "falls through to the catalog tier rule for a blank-but-present configured default" do
        provider.update_columns(configuration_schema: provider.configuration_schema.merge("default_model" => ""))
        expect(provider.reload.default_model).to eq("test-model-1"), "a blank configured default must fall through to the tier rule"

        _, sent = run(service_for(provider), tester)
        expect(sent).to eq("test-model-1")
      end

      it "returns a configuration_error and sends NOTHING when no model resolves" do
        provider.update_columns(supported_models: [])
        result, sent = run(service_for(provider), tester)

        expect(result).to include(success: false, error_type: "configuration_error")
        expect(result[:error_details]).to match(/no model configured/i)
        expect(sent).to eq(:no_request), "a request went out with no model on it"
      end
    end
  end

  # E3b (c): the Ollama chat fallback used to end in `|| "llama2"`. It now
  # resolves like the other testers. Three arms, because the tags check must
  # stay model-free: an Ollama server that answers /api/tags is reachable
  # whether or not the platform knows a model name for it.
  describe "#perform_ollama_connection_test" do
    let(:provider) { create(:ai_provider, account: account, provider_type: "ollama") }
    let(:ollama_creds) { { "base_url" => "http://ollama.example.test:11434" } }

    # Every request the tester makes, and the model on each (nil for a GET).
    def run_ollama(service, tags_ok:)
      calls = []
      allow(service).to receive(:make_http_request) do |url, **opts|
        calls << { url: url, model: opts[:body] && JSON.parse(opts[:body])["model"] }
        if url.end_with?("/api/tags")
          double("tags", success?: tags_ok, code: tags_ok ? 200 : 404, message: "tags",
                         body: { models: [] }.to_json)
        else
          double("chat", success?: false, code: 500, message: "chat failed", body: {}.to_json)
        end
      end
      [ service.send(:perform_ollama_connection_test, service.credential.credentials), calls ]
    end

    it "sends the provider's catalog model on the chat fallback, never a literal" do
      _, calls = run_ollama(service_for(provider, credentials: ollama_creds), tags_ok: false)
      expect(calls.filter_map { |c| c[:model] }).to eq([ "test-model-1" ])
    end

    it "returns a configuration_error and makes NO chat request when no model resolves" do
      provider.update_columns(supported_models: [])
      result, calls = run_ollama(service_for(provider, credentials: ollama_creds), tags_ok: false)

      expect(result).to include(success: false, error_type: "configuration_error")
      expect(calls.map { |c| c[:url] }).to all(end_with("/api/tags")), "a chat request went out with no model"
    end

    it "still passes on /api/tags alone, which needs no model" do
      provider.update_columns(supported_models: [])
      result, calls = run_ollama(service_for(provider, credentials: ollama_creds), tags_ok: true)

      expect(result[:success]).to be true
      expect(calls.size).to eq(1)
    end
  end

  it "no longer defines the dead perform_test family (E3 review F3)" do
    methods = described_class.private_instance_methods(false)
    expect(methods).to include(:perform_connection_test)
    expect(methods.grep(/\A(?:perform_test|test_[a-z]+_connection)\z/)).to be_empty
  end
end
