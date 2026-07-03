# frozen_string_literal: true

require "rails_helper"

# record_model_performance must credit the model that ACTUALLY served (served_by)
# on a Fable→X fallback, and must SKIP refusal executions (their model accounting
# is owned by WorkerLlmClient#record_refusal!).
RSpec.describe Ai::AgentExecution, "record_model_performance served-by attribution" do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider, agent_type: "code_assistant") }
  let(:execution) { create(:ai_agent_execution, :running, account: account, agent: agent, provider: provider) }

  it "credits the served_by model on a fallback (not the configured model)" do
    execution.update!(status: "completed", completed_at: Time.current, duration_ms: 1000,
                      performance_metrics: { "served_by" => "claude-opus-4-8" })

    perf = Ai::AgentModelPerformance.find_by(account_id: account.id, ai_provider_id: provider.id,
                                             model: "claude-opus-4-8", agent_type: "code_assistant")
    expect(perf&.successful_runs).to eq(1)
  end

  it "skips recording for a refusal execution (owned by WorkerLlmClient)" do
    expect {
      execution.update!(status: "completed", completed_at: Time.current, duration_ms: 1000,
                        performance_metrics: { "refused" => true })
    }.not_to change(Ai::AgentModelPerformance, :count)
  end

  it "credits the actually-served model (output_data.model_used) for an unpinned agent" do
    execution.update!(status: "completed", completed_at: Time.current, duration_ms: 1000,
                      output_data: { "model_used" => "claude-x" })

    perf = Ai::AgentModelPerformance.find_by(account_id: account.id, ai_provider_id: provider.id,
                                             model: "claude-x", agent_type: "code_assistant")
    expect(perf&.successful_runs).to eq(1)
  end

  it "prefers performance_metrics['model'] over output_data.model_used" do
    execution.update!(status: "completed", completed_at: Time.current, duration_ms: 1000,
                      performance_metrics: { "model" => "claude-metrics-model" },
                      output_data: { "model_used" => "claude-output-model" })

    perf = Ai::AgentModelPerformance.find_by(account_id: account.id, ai_provider_id: provider.id,
                                             model: "claude-metrics-model", agent_type: "code_assistant")
    expect(perf&.successful_runs).to eq(1)

    other = Ai::AgentModelPerformance.find_by(account_id: account.id, ai_provider_id: provider.id,
                                              model: "claude-output-model", agent_type: "code_assistant")
    expect(other).to be_nil
  end

  it "still prefers served_by over performance_metrics['model'] and output_data.model_used" do
    execution.update!(status: "completed", completed_at: Time.current, duration_ms: 1000,
                      performance_metrics: { "served_by" => "claude-opus-4-8", "model" => "claude-metrics-model" },
                      output_data: { "model_used" => "claude-output-model" })

    perf = Ai::AgentModelPerformance.find_by(account_id: account.id, ai_provider_id: provider.id,
                                             model: "claude-opus-4-8", agent_type: "code_assistant")
    expect(perf&.successful_runs).to eq(1)
  end

  it "falls back to the agent's pinned model when no served/metrics/output model is present" do
    pinned_agent = create(:ai_agent, account: account, provider: provider, agent_type: "code_assistant")
    pinned_agent.model = "custom-pinned-model"
    pinned_agent.save!
    pinned_execution = create(:ai_agent_execution, :running, account: account, agent: pinned_agent, provider: provider)

    pinned_execution.update!(status: "completed", completed_at: Time.current, duration_ms: 1000)

    perf = Ai::AgentModelPerformance.find_by(account_id: account.id, ai_provider_id: provider.id,
                                             model: "custom-pinned-model", agent_type: "code_assistant")
    expect(perf&.successful_runs).to eq(1)
  end
end
