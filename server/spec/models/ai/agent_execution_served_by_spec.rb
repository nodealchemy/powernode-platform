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
end
