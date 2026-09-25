# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skills::DesignSkillFromIntentExecutor, type: :service do
  let(:account) { create(:account) }
  subject(:executor) { described_class.new(account: account) }

  describe "designer model resolution" do
    let(:provider) { instance_double(Ai::Provider, default_model: "claude-haiku-4-5") }
    let(:llm) { instance_double(WorkerLlmClient, provider: provider) }
    let(:captured_models) { [] }
    let(:recipe_json) do
      {
        name: "List agents",
        description: "Lists all agents",
        inputs: [],
        steps: [ { id: "step1", tool: "platform_list_agents", params: [], capture: nil, require_approval: nil } ],
        output: []
      }.to_json
    end

    before do
      discovery = instance_double(Ai::Tools::SemanticToolDiscoveryService)
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).and_return(discovery)
      allow(discovery).to receive(:discover)
        .and_return([{ name: "platform_list_agents", description: "List all agents" }])

      allow(WorkerLlmClient).to receive(:for_account).and_return(llm)
      allow(llm).to receive(:complete_structured) do |model:, **|
        captured_models << model
        double(success?: true, content: recipe_json)
      end
    end

    it "resolves the designer model from the bound provider's default, never a hardcoded OpenAI id" do
      result = executor.execute(intent: "list all agents")

      expect(result[:success]).to be(true)
      expect(captured_models).to eq(["claude-haiku-4-5"])
      expect(captured_models).not_to include(a_string_matching(/\Agpt-/))
    end
  end

  # C8: structured output. params and output are maps with arbitrary keys,
  # which strict structured output cannot express, so they travel as
  # [{name, value}] pairs and fold back into hashes.
  describe "structured recipe design" do
    it "has a schema the strict normalizer accepts (no open maps)" do
      schema = executor.send(:recipe_design_schema)
      strict = Ai::Llm::StructuredSchema.normalize(schema, provider: :anthropic)
      step = strict.dig("properties", "steps", "items")
      expect(step["additionalProperties"]).to be(false)
      expect(step.dig("properties", "params", "type")).to eq("array")
    end

    it "folds name/value pairs back into the recipe's hashes and drops null optionals" do
      design = {
        "name" => "Provision cheapest", "description" => "d",
        "inputs" => [ { "name" => "region", "type" => "string", "required" => true, "description" => nil } ],
        "steps" => [ { "id" => "step1", "tool" => "t", "capture" => "found", "require_approval" => nil,
                       "params" => [ { "name" => "region", "value" => "{{ inputs.region }}" },
                                     { "name" => "limit", "value" => 3 } ] } ],
        "output" => [ { "name" => "id", "value" => "{{ found.id }}" } ]
      }

      recipe = executor.send(:recipe_from_design, design)

      expect(recipe["steps"].first).to eq("id" => "step1", "tool" => "t", "capture" => "found",
                                          "params" => { "region" => "{{ inputs.region }}", "limit" => 3 })
      expect(recipe["output"]).to eq("id" => "{{ found.id }}")
      expect(recipe["inputs"].first).not_to have_key("description")
    end
  end
end
