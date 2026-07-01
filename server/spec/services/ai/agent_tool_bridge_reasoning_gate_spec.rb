# frozen_string_literal: true

require "rails_helper"

# A1 (Fable 5 optimization): Fable/Mythos run a reasoning_extraction safety
# classifier and think natively (always-on adaptive thinking), so the
# chain_of_thought / star scaffolds — which make the model emit its reasoning as
# text and inject it back as an assistant turn — are both redundant and a refusal
# trigger there. execute_with_reasoning must SKIP those scaffolds for the
# refusal-classifier family (Ai::Llm::ModelCapabilities.refusal_capable?) while
# leaving every other model (incl. Opus/Sonnet, which also think natively but do
# not run the classifier) unchanged. plan_and_execute produces subtasks, not a
# reasoning transcript, so it is intentionally out of scope. See
# guidance-fable5-compliance.
RSpec.describe Ai::AgentToolBridgeService, "reasoning-scaffold gate (Fable/Mythos)" do
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
      llm_client: llm, messages: [{ role: "user", content: "hi" }],
      model: model, reasoning_mode: reasoning_mode
    )
  end

  context "when the model runs the reasoning_extraction classifier (Fable/Mythos)" do
    before do
      allow(Ai::Reasoning::ChainOfThoughtService).to receive(:new)
      allow(Ai::Reasoning::StarReasoningService).to receive(:new)
    end

    it "skips the chain_of_thought scaffold for claude-fable-5" do
      run(model: "claude-fable-5", reasoning_mode: :chain_of_thought)
      expect(Ai::Reasoning::ChainOfThoughtService).not_to have_received(:new)
    end

    it "skips the star scaffold for claude-mythos-5" do
      run(model: "claude-mythos-5", reasoning_mode: :star)
      expect(Ai::Reasoning::StarReasoningService).not_to have_received(:new)
    end
  end

  context "when the model has no reasoning_extraction classifier (Opus/Sonnet/other)" do
    it "still runs the chain_of_thought scaffold for claude-opus-4-8" do
      cot = instance_double(Ai::Reasoning::ChainOfThoughtService, reason: { reasoning_steps: [] })
      allow(Ai::Reasoning::ChainOfThoughtService).to receive(:new).and_return(cot)

      run(model: "claude-opus-4-8", reasoning_mode: :chain_of_thought)

      expect(Ai::Reasoning::ChainOfThoughtService).to have_received(:new)
    end
  end
end
