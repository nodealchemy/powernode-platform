# frozen_string_literal: true

require "rails_helper"

# Universal server-side recording: any agent-scoped WorkerLlmClient call whose
# worker response carries a refusal appends a ModelRefusalEvent, records a FAILURE
# for the refused model, and pre-routes past the threshold.
RSpec.describe WorkerLlmClient, "refusal recording" do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:client) { described_class.new(agent_id: "agent-xyz", skip_budget_tracking: true) }

  before do
    agent_double = instance_double(Ai::Agent, account_id: account.id, agent_type: "code_assistant",
                                              resolved_provider: provider, provider: provider)
    allow(Ai::Agent).to receive(:find_by).with(id: "agent-xyz").and_return(agent_double)
  end

  def recovered_response(served_by: "claude-opus-4-8", category: "cyber")
    Ai::Llm::Response.new(
      content: "opus answer", model: "claude-fable-5", served_by: served_by,
      refusal_recovery: { "category" => category, "phase" => "pre_output",
                          "reframed" => true, "fell_back" => true,
                          "served_by" => served_by, "resolved" => true }
    )
  end

  it "appends a ModelRefusalEvent and records a failure for the refused model" do
    expect {
      client.send(:record_refusal!, recovered_response, "claude-fable-5")
    }.to change(Ai::ModelRefusalEvent, :count).by(1)

    perf = Ai::AgentModelPerformance.find_by(account_id: account.id, ai_provider_id: provider.id,
                                             model: "claude-fable-5", agent_type: "code_assistant")
    expect(perf.failed_runs).to eq(1)
    expect(perf.successful_runs).to eq(0)

    ev = Ai::ModelRefusalEvent.last
    expect(ev.served_by_model).to eq("claude-opus-4-8")
    expect(ev.fell_back).to be true
    expect(ev.category).to eq("cyber")
  end

  it "pre-routes the (model, agent_type, category) combo once past the threshold" do
    5.times { client.send(:record_refusal!, recovered_response, "claude-fable-5") }

    rule = Ai::ModelRoutingRule.find_by(account_id: account.id,
                                        name: "fable-refusal-preroute:claude-fable-5:code_assistant:cyber")
    expect(rule).to be_present
    expect(rule.target["model_names"]).to eq(["claude-opus-4-8"])
  end

  it "does NOT pre-route on a reframe-SUCCESS (served_by is the refusing model, not a fallback)" do
    reframe_success = Ai::Llm::Response.new(
      content: "reframed ok", model: "claude-fable-5", served_by: "claude-fable-5",
      refusal_recovery: { "category" => "cyber", "phase" => "pre_output",
                          "reframed" => true, "fell_back" => false,
                          "served_by" => "claude-fable-5", "resolved" => true }
    )
    6.times { client.send(:record_refusal!, reframe_success, "claude-fable-5") }

    expect(Ai::ModelRoutingRule.where("name LIKE 'fable-refusal-preroute:%'").count).to eq(0)
  end
end
