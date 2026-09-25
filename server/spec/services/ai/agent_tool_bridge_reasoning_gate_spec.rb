# frozen_string_literal: true

require "rails_helper"

# Adaptive-only models (every Claude model outside the legacy set) think natively,
# and the newest run a reasoning_extraction safety classifier, so the
# chain_of_thought / star scaffolds — which make the model emit its reasoning as
# text and inject it back as an assistant turn — are redundant there and a refusal
# trigger on some. execute_with_reasoning must SKIP those scaffolds whenever
# Ai::Llm::ModelCapabilities.thinking_mode is :adaptive_only, and keep them for
# legacy and non-Claude models. plan_and_execute produces subtasks, not a
# reasoning transcript, so it is intentionally out of scope. See
# guidance-fable5-compliance.
RSpec.describe Ai::AgentToolBridgeService, "reasoning-scaffold gate (adaptive-only models)" do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  subject(:bridge) { described_class.new(agent: agent, account: account) }

  let(:llm) { instance_double(WorkerLlmClient) }

  before do
    allow(bridge).to receive(:tool_definitions_for_llm).and_return([])
    # Isolate Phase 1 — the tool loop itself is out of scope for this gate.
    allow(bridge).to receive(:execute_tool_loop).and_return({ content: "done" })
  end

  def run(model:, reasoning_mode:)
    bridge.send(
      :execute_with_reasoning,
      llm_client: llm, messages: [ { role: "user", content: "hi" } ],
      model: model, reasoning_mode: reasoning_mode
    )
  end

  context "when the model is adaptive-only" do
    before do
      allow(Ai::Reasoning::ChainOfThoughtService).to receive(:new)
      allow(Ai::Reasoning::StarReasoningService).to receive(:new)
    end

    %w[claude-fable-5 claude-opus-4-8 claude-opus-5 claude-opus-5-5 claude-sonnet-5].each do |model|
      it "skips the chain_of_thought scaffold for #{model}" do
        run(model: model, reasoning_mode: :chain_of_thought)
        expect(Ai::Reasoning::ChainOfThoughtService).not_to have_received(:new)
      end
    end

    it "skips the star scaffold for claude-mythos-5" do
      run(model: "claude-mythos-5", reasoning_mode: :star)
      expect(Ai::Reasoning::StarReasoningService).not_to have_received(:new)
    end
  end

  context "when the model is legacy or non-Claude" do
    %w[claude-opus-4-6 gpt-4o].each do |model|
      it "still runs the chain_of_thought scaffold for #{model}" do
        cot = instance_double(Ai::Reasoning::ChainOfThoughtService, reason: { reasoning_steps: [] })
        allow(Ai::Reasoning::ChainOfThoughtService).to receive(:new).and_return(cot)

        run(model: model, reasoning_mode: :chain_of_thought)

        expect(Ai::Reasoning::ChainOfThoughtService).to have_received(:new)
      end
    end
  end
end
