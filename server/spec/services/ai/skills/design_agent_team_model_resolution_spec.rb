# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, E3 review F2 — DesignAgentTeamFromIntentExecutor had NO
# spec anywhere, so E3's change to how it picks a model was untested.
#
# The model must come from the provider the account's client is bound to. Three resolving arms and the
# refusal; a blank configured default falls through to Provider#default_model's
# lightest-tier rule, and there is no catalog[0] arm (E3b).
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
    allow(llm).to receive(:complete_structured) do |**opts|
      sent = opts[:model]
      double(success?: true, content: '{"members": [], "output": []}', finish_reason: "stop")
    end
    [ executor.send(:generate_team_design, "a support team", [], "Support", 3, "auto"), sent ]
  end

  it "sends the provider's configured default_model" do
    result, sent = design_with(provider_with(schema_extra: { "default_model" => "configured-model-1" }))
    expect(sent).to eq("configured-model-1")
    expect(result).to have_key(:spec)
  end

  it "sends the lightest-tier catalog id when nothing is configured (ties keep catalog order)" do
    _, sent = design_with(provider_with)
    expect(sent).to eq("test-model-1")
  end

  it "falls through to the catalog tier rule for a blank-but-present configured default" do
    provider = provider_with(schema_extra: { "default_model" => "" })
    expect(provider.default_model).to eq("test-model-1")

    _, sent = design_with(provider)
    expect(sent).to eq("test-model-1")
  end

  it "returns the no-model error and makes NO call when nothing resolves" do
    result, sent = design_with(provider_with(supported_models: []))

    expect(result).to eq(error: "No model configured for the account's LLM provider")
    expect(sent).to eq(:no_call)
  end

  # C8: structured output. output is a map with arbitrary keys, which strict
  # structured output cannot express, so it travels as [{name, value}] pairs.
  describe "structured team design" do
    it "has a schema the strict normalizer accepts (no open maps)" do
      strict = Ai::Llm::StructuredSchema.normalize(executor.send(:team_design_schema), provider: :openai)
      member = strict.dig("properties", "members", "items")
      expect(member["required"]).to include("agent_slug", "agent_spec")
      expect(member.dig("properties", "agent_spec", "type")).to eq(%w[object null])
    end

    it "folds output pairs into a hash and drops each member's null alternative" do
      spec = executor.send(:spec_from_design,
                           "members" => [ { "role" => "r", "agent_slug" => "a", "agent_spec" => nil,
                                            "priority" => 1, "required" => true } ],
                           "output" => [ { "name" => "summary", "value" => "{{ r.text }}" } ])

      expect(spec["members"].first).to eq("role" => "r", "agent_slug" => "a", "priority" => 1, "required" => true)
      expect(spec["output"]).to eq("summary" => "{{ r.text }}")
    end
  end
end
