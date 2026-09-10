# frozen_string_literal: true

require "rails_helper"

# D4 — the worker→server surface of the LLM judge. This route IS the judge's
# only production entry point: AgentEvaluationJob posts here and the evaluation
# runs synchronously inside this request, replacing a bare Thread.new that ran
# inside a Puma request and had no callers at all.
RSpec.describe "Api::V1::Internal::Ai::Evaluations", type: :request do
  let(:account)       { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end
  let(:agent) { create(:ai_agent, account: account) }
  let(:execution) do
    create(:ai_agent_execution, :completed, account: account, agent: agent,
           output_data: { "result" => "the agent's answer" })
  end
  let(:judge) { instance_double(Ai::Learning::LlmJudgeService) }

  def stub_judge!
    allow(Ai::Learning::LlmJudgeService).to receive(:new).and_return(judge)
    allow(judge).to receive(:evaluator_model).and_return("resolved-model-x")
    allow(judge).to receive(:evaluate).and_return(
      scores: { "correctness" => 4, "completeness" => 4, "helpfulness" => 4, "safety" => 5 },
      feedback: "Good output"
    )
  end

  before do
    allow(Ai::Autonomy::TrustEngineService).to receive(:new)
      .and_return(instance_double(Ai::Autonomy::TrustEngineService, evaluate: true))
    # :agent_evaluation is registered OFF, so D4 ships inert until an operator
    # enables it — same activation posture as the closure driver. The arm that
    # pins the off state lives in the service spec; here the flag is on so the
    # ROUTE's own behaviour is what is under test.
    allow(Shared::FeatureFlagService).to receive(:enabled?).and_call_original
    allow(Shared::FeatureFlagService).to receive(:enabled?).with(:agent_evaluation).and_return(true)
  end

  describe "POST /api/v1/internal/ai/evaluations/run" do
    it "reports EvaluationDisabled while the flag is off, without touching the judge" do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:agent_evaluation).and_return(false)
      expect(Ai::Learning::LlmJudgeService).not_to receive(:new)

      post "/api/v1/internal/ai/evaluations/run",
           params: { account_id: account.id, execution_id: execution.id },
           headers: worker_headers

      expect(JSON.parse(response.body)["data"]["reason"]).to eq("EvaluationDisabled")
    end

    it "requires the worker's mTLS identity" do
      post "/api/v1/internal/ai/evaluations/run", params: { account_id: account.id }

      expect(response).to have_http_status(:unauthorized)
    end

    it "evaluates and returns the evaluated arm" do
      stub_judge!

      expect {
        post "/api/v1/internal/ai/evaluations/run",
             params: { account_id: account.id, execution_id: execution.id },
             headers: worker_headers
      }.to change(Ai::EvaluationResult, :count).by(1)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["status"]).to eq("evaluated")
      expect(data["evaluation_id"]).to eq(Ai::EvaluationResult.last.id)
    end

    it "answers not_measured (200, not 404) for an execution that was never recorded" do
      # The other arm of the same door. A 404 would make the worker retry a
      # missing row forever; not_measured is a terminal answer it can log.
      post "/api/v1/internal/ai/evaluations/run",
           params: { account_id: account.id, execution_id: SecureRandom.uuid },
           headers: worker_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["status"]).to eq("not_measured")
      expect(data["reason"]).to eq("NoEvaluableExecution")
      expect(Ai::EvaluationResult.count).to eq(0)
    end

    it "carries task_id through, so a retry of the same completion is idempotent" do
      stub_judge!
      task_id = SecureRandom.uuid

      2.times do
        post "/api/v1/internal/ai/evaluations/run",
             params: { account_id: account.id, execution_id: execution.id, task_id: task_id },
             headers: worker_headers
      end

      expect(Ai::EvaluationResult.where(execution_id: execution.id, task_id: task_id).count).to eq(1)
      expect(JSON.parse(response.body)["data"]["idempotent"]).to be(true)
    end
  end
end
