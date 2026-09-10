# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, E3 review F2 — DesignAgentTeamFromIntentExecutor had NO
# spec anywhere, so E3's change to how it picks a model was untested.
#
# `llm` may be the openai client OR the account fallback, so the model must
# come from the provider THAT client is bound to. Three resolving arms and the
# refusal; the blank configured default is the arm that proves the explicit
# `|| available_models&.first` is live (see provider_adapters_spec.rb).
RSpec.describe Ai::Skills::DesignAgentTeamFromIntentExecutor, "model resolution" do
  let(:account) { create(:account) }
  subject(:executor) { described_class.new(account: account) }

  # A built (unsaved) provider: #default_model and #available_models are pure
  # reads of its columns, and the refusal arm needs a catalog the model's
  # validations would reject.
  def provider_with(schema_extra: {}, supported_models: nil)
    attrs = { account: account, provider_type: "openai" }
    attrs[:supported_models] = supported_models unless supported_models.nil?
    build(:ai_provider, **attrs).tap do |p|
      p.configuration_schema = p.configuration_schema.merge(schema_extra)
    end
  end

  def design_with(provider)
    llm = double("WorkerLlmClient", provider: provider)
    allow(::WorkerLlmClient).to receive(:for_account).and_return(llm)
    sent = :no_call
    allow(llm).to receive(:complete) do |**opts|
      sent = opts[:model]
      double(success?: true, content: '{"members": []}', finish_reason: "stop")
    end
    [ executor.send(:generate_team_design, "a support team", [], "Support", 3, "auto"), sent ]
  end

  it "sends the provider's configured default_model" do
    result, sent = design_with(provider_with(schema_extra: { "default_model" => "configured-model-1" }))
    expect(sent).to eq("configured-model-1")
    expect(result).to have_key(:spec)
  end

  it "sends the first catalog id when nothing is configured (through Provider#default_model)" do
    _, sent = design_with(provider_with)
    expect(sent).to eq("test-model-1")
  end

  it "reaches its own available_models.first arm for a blank-but-present configured default" do
    provider = provider_with(schema_extra: { "default_model" => "" })
    expect(provider.default_model).to eq("")

    _, sent = design_with(provider)
    expect(sent).to eq("test-model-1")
  end

  it "returns the no-model error and makes NO call when nothing resolves" do
    result, sent = design_with(provider_with(supported_models: []))

    expect(result).to eq(error: "No model configured for the account's LLM provider")
    expect(sent).to eq(:no_call)
  end
end
