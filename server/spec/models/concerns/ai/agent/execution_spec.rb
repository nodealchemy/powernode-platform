# frozen_string_literal: true

require "rails_helper"

# Bug: Ai::Agent::Execution#execute recorded the agent's RAW `provider`
# association on the created AgentExecution instead of the RESOLVED provider
# that actually serves the call for unpinned agents (Ai::Agent#resolved_provider,
# computed by Ai::AgentModelSelector). That misattributed spend in
# platform_cost_analysis (e.g. Fable spend credited to a stale Ollama provider).
RSpec.describe Ai::Agent::Execution do
  let(:account) { create(:account) }
  let(:raw_provider) { create(:ai_provider, account: account, name: "stale-ollama") }
  let(:resolved_provider) { create(:ai_provider, account: account, name: "actual-anthropic") }
  let(:agent) { create(:ai_agent, account: account, provider: raw_provider, status: "active") }
  let(:user) { create(:user, account: account) }

  before do
    # Prior-art idiom (spec/services/ai/ralph/task_executor_spec.rb): stub
    # resolved_provider directly rather than the raw `provider` association —
    # resolved_provider re-queries the DB each time so stubbing `provider`
    # would not affect it.
    allow(agent).to receive(:resolved_provider).and_return(resolved_provider)

    executor = instance_double(Ai::McpAgentExecutor)
    allow(Ai::McpAgentExecutor).to receive(:new).and_return(executor)
    allow(executor).to receive(:execute).and_return(
      "result" => { "output" => "ok", "metadata" => {} },
      "telemetry" => { "tokens_used" => 1 }
    )
  end

  describe "#execute" do
    it "records the RESOLVED provider's id on the created execution, not the raw association's" do
      execution = agent.execute({ "input" => "hi" }, user: user)

      expect(execution.ai_provider_id).to eq(resolved_provider.id)
      expect(execution.ai_provider_id).not_to eq(raw_provider.id)
    end

    it "honors an explicit caller-specified provider override even when resolution differs" do
      explicit_provider = create(:ai_provider, account: account, name: "explicit-pin")

      execution = agent.execute({ "input" => "hi" }, user: user, provider: explicit_provider)

      expect(execution.ai_provider_id).to eq(explicit_provider.id)
    end

    it "falls back to the raw provider association when resolution returns nil" do
      allow(agent).to receive(:resolved_provider).and_return(nil)

      execution = agent.execute({ "input" => "hi" }, user: user)

      expect(execution.ai_provider_id).to eq(raw_provider.id)
    end
  end
end
