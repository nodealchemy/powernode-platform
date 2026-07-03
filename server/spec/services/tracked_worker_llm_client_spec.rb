# frozen_string_literal: true

require "rails_helper"

# Bug: create_execution_record recorded the agent's RAW `provider` association
# on the created AgentExecution instead of the RESOLVED provider that actually
# serves the call (Ai::Agent#resolved_provider). See
# app/models/concerns/ai/agent/execution.rb for the sibling bug/fix.
RSpec.describe TrackedWorkerLlmClient do
  let(:account) { create(:account) }
  let(:creator) { create(:user, account: account) }
  let(:raw_provider) { create(:ai_provider, account: account, name: "stale-ollama") }
  let(:resolved_provider) { create(:ai_provider, account: account, name: "actual-anthropic") }
  let(:agent) { create(:ai_agent, account: account, provider: raw_provider, creator: creator, status: "active") }

  let(:inner_response) do
    Ai::Llm::Response.new(
      content: "hi",
      model: "claude-x",
      provider: "anthropic",
      usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 }
    )
  end

  let(:inner_client) { instance_double(WorkerLlmClient) }
  subject(:tracked_client) { described_class.new(inner_client: inner_client, agent: agent) }

  before do
    allow(agent).to receive(:resolved_provider).and_return(resolved_provider)
    allow(inner_client).to receive(:complete).and_return(inner_response)
  end

  it "records the RESOLVED provider's id on the created execution, not the raw association's" do
    tracked_client.complete(messages: [{ role: "user", content: "hi" }], model: "claude-x")

    execution = Ai::AgentExecution.order(:created_at).last
    expect(execution.ai_provider_id).to eq(resolved_provider.id)
    expect(execution.ai_provider_id).not_to eq(raw_provider.id)
  end

  it "falls back to the raw provider association when resolution returns nil" do
    allow(agent).to receive(:resolved_provider).and_return(nil)

    tracked_client.complete(messages: [{ role: "user", content: "hi" }], model: "claude-x")

    execution = Ai::AgentExecution.order(:created_at).last
    expect(execution.ai_provider_id).to eq(raw_provider.id)
  end
end
