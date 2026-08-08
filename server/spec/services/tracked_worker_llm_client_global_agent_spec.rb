# frozen_string_literal: true

require "rails_helper"

# TrackedWorkerLlmClient must record executions for GLOBAL agents.
#
# A global Ai::Agent (account_id nil) is shared platform-wide; an account "uses"
# it via #using_account, which is how AgentBackedService#resolve_service_agent
# returns it. But create_execution_record built the row with
# `account: @agent.account` — nil for a global agent — so the create! failed
# "Validation failed: Account must exist" and the decorator's own rescue
# swallowed it to nil. Tracking then silently no-ops: no Ai::AgentExecution, no
# cost_usd, no tokens, no performance_metrics, and no budget debit, while the
# LLM call itself proceeds normally.
#
# Observed live on ops-hub 2026-08-08 after wiring the provisioning services
# through this decorator: build_llm_client correctly returned a
# TrackedWorkerLlmClient and resolve_tracking_agent correctly returned
# system-topology-designer, yet ai_agent_executions stayed at ZERO across the
# whole run. The rails log carried
#   [TrackedWorkerLlmClient] Failed to create execution record:
#     Validation failed: Account must exist
#
# This is not specific to the provisioning path — EVERY global agent reaching
# this decorator (including via #build_agent_client) has been silently
# untracked for the same reason.
RSpec.describe TrackedWorkerLlmClient, "global agent attribution", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # A GLOBAL agent: no account of its own.
  let(:global_agent) do
    create(:ai_agent, account: account, creator: user, status: "active").tap do |a|
      a.update_columns(account_id: nil)
      a.reload
    end
  end

  let(:response) do
    instance_double(
      "WorkerLlmResponse",
      content: "ok", prompt_tokens: 10, completion_tokens: 5, cached_tokens: 0,
      total_tokens: 15, model: "gpt-4o-mini", provider: "openai"
    )
  end

  let(:inner) { instance_double(::WorkerLlmClient) }

  before { allow(inner).to receive(:complete).and_return(response) }

  it "the agent really is global (guards the premise)" do
    expect(global_agent.account_id).to be_nil
    expect(global_agent.account).to be_nil
  end

  context "when an explicit account is supplied" do
    subject(:client) do
      described_class.new(inner_client: inner, agent: global_agent, account: account,
                          execution_context_type: "service:Spec")
    end

    it "creates an AgentExecution instead of silently dropping it" do
      expect { client.complete(messages: [{ role: "user", content: "hi" }], model: "gpt-4o-mini") }
        .to change { Ai::AgentExecution.count }.by(1)
    end

    it "attributes the execution to the USING account, not the agent's nil account" do
      client.complete(messages: [{ role: "user", content: "hi" }], model: "gpt-4o-mini")
      expect(Ai::AgentExecution.last.account_id).to eq(account.id)
      expect(Ai::AgentExecution.last.ai_agent_id).to eq(global_agent.id)
    end

    it "still records tokens so the context/cost oracles have something to read" do
      client.complete(messages: [{ role: "user", content: "hi" }], model: "gpt-4o-mini")
      exec = Ai::AgentExecution.last
      expect(exec.tokens_used).to eq(15)
      expect(exec.performance_metrics["prompt_tokens"]).to eq(10)
    end
  end

  context "when the agent is account-owned (unchanged behaviour)" do
    let(:owned_agent) { create(:ai_agent, account: account, creator: user, status: "active") }
    subject(:client) { described_class.new(inner_client: inner, agent: owned_agent) }

    it "still falls back to the agent's own account" do
      expect { client.complete(messages: [{ role: "user", content: "hi" }], model: "gpt-4o-mini") }
        .to change { Ai::AgentExecution.count }.by(1)
      expect(Ai::AgentExecution.last.account_id).to eq(account.id)
    end
  end
end
