# frozen_string_literal: true

require "rails_helper"

# The standalone Sidekiq worker (AiAgentExecutionJob) fetches an execution via
# GET /api/v1/internal/ai/executions/:id and reads `@agent_execution['account_id']`
# to honor the per-account AI kill switch (bail_if_ai_suspended!). The worker-facing
# serializer MUST emit account_id at the top level or the bail fails open.
RSpec.describe "Internal::Ai::AgentExecutions", type: :request do
  include_context "internal api auth"

  let(:execution) { create(:ai_agent_execution, account: internal_account) }
  let(:path) { "/api/v1/internal/ai/executions/#{execution.id}" }

  it "includes account_id in the worker-facing payload (kill-switch read location)" do
    get path, headers: service_headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("data", "agent_execution", "account_id")).to eq(execution.account_id)
  end
end
