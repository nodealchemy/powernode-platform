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
        steps: [{ id: "step1", tool: "platform_list_agents", params: {} }],
        output: {}
      }.to_json
    end

    before do
      discovery = instance_double(Ai::Tools::SemanticToolDiscoveryService)
      allow(Ai::Tools::SemanticToolDiscoveryService).to receive(:new).and_return(discovery)
      allow(discovery).to receive(:discover)
        .and_return([{ name: "platform_list_agents", description: "List all agents" }])

      allow(WorkerLlmClient).to receive(:for_account).and_return(llm)
      allow(llm).to receive(:complete) do |model:, **|
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
end
