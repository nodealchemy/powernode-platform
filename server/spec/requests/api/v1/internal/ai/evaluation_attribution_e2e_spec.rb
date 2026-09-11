# frozen_string_literal: true

require "rails_helper"

# D5 — the completion oracle, end to end, through real code at every link:
#
#   the worker asks for its prompt, naming its execution row
#     -> the served skill version is stamped on that row        (producer 2)
#   the executor completes its task, naming the same run
#     -> the task carries the run, and the judge is enqueued     (producer 1)
#   the worker posts the enqueued ids back to the judge route
#     -> the REAL judge runs, its provider stubbed at the HTTP layer
#     -> an evaluation is persisted, and the skill version that SERVED —
#        an A/B variant, drawn at serve time — is the one credited.
#
# Stubbed and nothing else: the router's random draw (so the served version is
# known), semantic discovery (so the judge resolves the llm-judge agent by
# slug), and the worker's HTTP — the enqueue is CAPTURED from its real
# string-keyed body and replayed, as AgentEvaluationJob would post it, rather
# than handed over as a symbol-keyed double.
RSpec.describe "D5 outcome attribution, end to end", type: :request do
  include_context "internal api auth"

  let(:account) { internal_account }
  let(:user) { create(:user, account: account) }
  let(:executor_agent) { create(:ai_agent, account: account) }
  let!(:judge_agent) { create(:ai_agent, account: account, name: "LLM Judge", slug: "llm-judge", status: "active") }

  let(:skill) do
    create(:ai_skill, account: account, status: "active", is_enabled: true, system_prompt: "the active text")
  end
  let!(:active) do
    create(:ai_skill_version, account: account, ai_skill: skill, version: "1.0.0",
                              is_active: true, system_prompt: "the active text")
  end
  let!(:variant) do
    create(:ai_skill_version, account: account, ai_skill: skill, version: "2.0.0",
                              is_active: false, is_ab_variant: true, ab_traffic_pct: 0.5,
                              system_prompt: "the variant text")
  end

  let(:execution) do
    create(:ai_agent_execution, :completed, account: account, agent: executor_agent,
                                            output_data: { "result" => "the agent's answer" })
  end
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "d5-e2e-loop") }
  let!(:task) { create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "D5-E2E") }
  let(:tool) { Ai::Tools::DevLoopTool.new(account: account, user: user) }

  let(:enqueued) { [] }
  let(:verdict) do
    { scores: { correctness: 4, completeness: 4, helpfulness: 4, safety: 5 }, overall: 4, rationale: "sound" }.to_json
  end

  before do
    Ai::AgentSkill.create!(ai_agent_id: executor_agent.id, ai_skill_id: skill.id, is_active: true, priority: 1)

    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
    allow_any_instance_of(Ai::Tools::SemanticToolDiscoveryService).to receive(:discover).and_return([])
    # No switch is set: ai.evaluation.enabled is absent, and absent means ON,
    # so this example also proves the ruled default end to end.

    # The draw lands inside the variant's 0.5 share.
    allow(Ai::SkillGraph::EvolutionService).to receive(:route_served_versions).and_wrap_original do |original, ids, **|
      original.call(ids, random: instance_double(Random, rand: 0.1))
    end

    # Worker HTTP: capture every job enqueue from its real body...
    stub_request(:post, %r{/api/v1/jobs}).to_return do |request|
      enqueued << JSON.parse(request.body)
      { status: 200, body: { success: true, job_id: SecureRandom.uuid }.to_json,
        headers: { "Content-Type" => "application/json" } }
    end
    # ...and answer the judge's LLM call the way the worker's proxy does.
    stub_request(:post, %r{/api/v1/llm/complete}).to_return(
      status: 200,
      body: { data: { content: verdict, model: "judge-model", finish_reason: "stop",
                      usage: { prompt_tokens: 40, completion_tokens: 20, total_tokens: 60 } } }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    ralph_loop.update!(status: "running", started_at: Time.current)
    tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
  end

  it "judges the completed task and credits the skill version that actually served it" do
    # 1. The worker builds its prompt, naming its execution row.
    post "/api/v1/internal/ai/execution_contexts",
         params: { agent_id: executor_agent.id, input: "do the task", agent_execution_id: execution.id }.to_json,
         headers: service_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "system_prompt")).to include("the variant text")
    expect(execution.reload.execution_context[Ai::SkillVersion::SERVED_CONTEXT_KEY]).to eq([ variant.id ])

    # 2. The executor completes its task, naming the same run.
    result = tool.execute(params: {
      action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "D5-E2E",
      outcome: "passed", summary: "done", agent_execution_id: execution.id
    })
    expect(result[:success]).not_to be(false)
    key = Ai::Tools::DevLoopTool.const_get(:EVALUABLE_EXECUTION_METADATA_KEY)
    expect(task.reload.metadata[key]).to eq(execution.id)

    job = enqueued.find { |body| body["job_class"] == "AgentEvaluationJob" }
    expect(job).to be_present
    args = job["args"].first
    expect(args).to eq("account_id" => account.id, "execution_id" => execution.id, "task_id" => task.id)

    # 3. The worker posts those ids back; the real judge runs.
    expect {
      post "/api/v1/internal/ai/evaluations/run", params: args.to_json, headers: service_headers
    }.to change(Ai::EvaluationResult, :count).by(1)

    expect(response).to have_http_status(:ok)
    data = response.parsed_body["data"]
    expect(data["status"]).to eq("evaluated")
    expect(data.dig("skill_outcome", "skill_version_ids")).to eq([ variant.id ])
    expect(WebMock).to have_requested(:post, %r{/api/v1/llm/complete}).once

    evaluation = Ai::EvaluationResult.find_by!(execution_id: execution.id, task_id: task.id)
    expect(evaluation.scores).to include("correctness" => 4, "safety" => 5)

    # 4. The served version is credited; the one that did not serve is not.
    expect(variant.reload.success_count).to eq(1)
    expect(active.reload.usage_count).to eq(0)
  end
end
