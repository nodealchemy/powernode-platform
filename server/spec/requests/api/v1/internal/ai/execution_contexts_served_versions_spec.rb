# frozen_string_literal: true

require "rails_helper"

# D5 — the worker path's producer. AiAgentExecutionJob owns an
# Ai::AgentExecution row but asks this endpoint for its system prompt, so this
# is where the skill versions that prompt served are known. The job names its
# row; the versions are stamped onto it for the judge to credit.
RSpec.describe "Internal::Ai execution_contexts stamps the served skill versions", type: :request do
  include_context "internal api auth"

  let(:agent) { create(:ai_agent, account: internal_account) }
  let(:path) { "/api/v1/internal/ai/execution_contexts" }
  let(:skill) do
    create(:ai_skill, account: internal_account, status: "active", is_enabled: true, system_prompt: "the active text")
  end
  let!(:active) do
    create(:ai_skill_version, account: internal_account, ai_skill: skill, version: "1.0.0",
                              is_active: true, system_prompt: "the active text")
  end
  let(:execution) { create(:ai_agent_execution, account: internal_account, agent: agent) }

  before do
    Ai::AgentSkill.create!(ai_agent_id: agent.id, ai_skill_id: skill.id, is_active: true, priority: 1)
  end

  def served_on(row)
    (row.reload.execution_context || {})[Ai::SkillVersion::SERVED_CONTEXT_KEY]
  end

  it "stamps the versions whose prompts it served onto the execution the worker named" do
    post path, params: { agent_id: agent.id, input: "hi", agent_execution_id: execution.id }.to_json,
               headers: service_headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "system_prompt")).to include("the active text")
    expect(served_on(execution)).to eq([ active.id ])
  end

  it "stamps nothing when no execution is named, and still builds the prompt" do
    post path, params: { agent_id: agent.id, input: "hi" }.to_json, headers: service_headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "system_prompt")).to include("the active text")
    expect(served_on(execution)).to be_nil
  end

  it "never stamps an execution that belongs to a different agent" do
    other = create(:ai_agent_execution, account: internal_account,
                                        agent: create(:ai_agent, account: internal_account))

    post path, params: { agent_id: agent.id, input: "hi", agent_execution_id: other.id }.to_json,
               headers: service_headers

    expect(response).to have_http_status(:ok)
    expect(served_on(other)).to be_nil
  end
end
