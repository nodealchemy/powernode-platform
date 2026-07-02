# frozen_string_literal: true

require "rails_helper"

# inc6: benefit measurement. A RoutingDecision created by the McpAgentExecutor seam
# is linked to its Ai::AgentExecution (agent_execution_id). When the execution
# reaches a terminal state, its outcome/cost/latency/tokens are fed back onto the
# decision via the existing RoutingDecision#record_outcome! — reusing the data the
# execution already collected (alongside #record_model_performance), NOT duplicating
# collection.
RSpec.describe Ai::AgentExecution, "routing-decision outcome feedback" do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider, agent_type: "code_assistant") }
  let(:execution) { create(:ai_agent_execution, :running, account: account, agent: agent, provider: provider) }

  let!(:decision) do
    create(:ai_routing_decision, account: account, agent_execution: execution,
           model_tier: "reasoning", outcome: nil, rationale: { "decision" => "escalate" })
  end

  it "records a succeeded outcome with cost/latency/tokens on completion" do
    execution.update!(status: "completed", completed_at: Time.current, duration_ms: 1234,
                      tokens_used: 900, cost_usd: 0.0125)

    decision.reload
    expect(decision.outcome).to eq("succeeded")
    expect(decision.actual_cost_usd).to be_within(0.0001).of(0.0125)
    expect(decision.actual_latency_ms).to eq(1234)
    expect(decision.actual_tokens_used).to eq(900)
    # Latency semantics tag: this seam records AgentExecution duration_ms.
    expect(decision.rationale["latency_seam"]).to eq("agent_execution")
  end

  it "records a failed outcome when the execution fails" do
    execution.update!(status: "failed", error_message: "boom", completed_at: Time.current, duration_ms: 100)

    expect(decision.reload.outcome).to eq("failed")
  end

  it "passes through quality_score from performance_metrics when present" do
    execution.update!(status: "completed", completed_at: Time.current, duration_ms: 500,
                      performance_metrics: { "quality_score" => 0.83 })

    expect(decision.reload.quality_score.to_f).to be_within(0.001).of(0.83)
  end

  it "does not overwrite an already-recorded outcome" do
    decision.update!(outcome: "succeeded", actual_cost_usd: 0.5)
    execution.update!(status: "failed", error_message: "late", completed_at: Time.current, duration_ms: 100)

    expect(decision.reload.outcome).to eq("succeeded")
    expect(decision.actual_cost_usd).to be_within(0.0001).of(0.5)
  end

  it "no-ops cleanly when the execution has no linked routing decision" do
    other = create(:ai_agent_execution, :running, account: account, agent: agent, provider: provider)

    expect {
      other.update!(status: "completed", completed_at: Time.current, duration_ms: 100)
    }.not_to raise_error
  end
end
