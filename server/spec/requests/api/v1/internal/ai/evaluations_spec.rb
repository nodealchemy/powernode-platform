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
    # D5: the judge's switch is the SiteSetting ai.evaluation.enabled, and an
    # absent row means ON — so no switch is set here, and every example below
    # runs against the ruled default rather than against a stub.
  end

  describe "POST /api/v1/internal/ai/evaluations/run" do
    it "reports EvaluationDisabled while ai.evaluation.enabled is false, without touching the judge" do
      SiteSetting.set(Ai::Learning::EvaluationService::ENABLED_SETTING, "false", setting_type: "boolean")
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

    # D4 review F2 — tenancy. The calling worker's own account is the only
    # scope. A missing execution and another account's execution answer the
    # SAME 404, so the door discloses nothing about rows it will not serve;
    # AgentEvaluationJob treats that 404 as terminal, so neither retries.
    def post_run(execution_id:, account_id: account.id)
      post "/api/v1/internal/ai/evaluations/run",
           params: { account_id: account_id, execution_id: execution_id },
           headers: worker_headers
    end

    def foreign_execution
      other = create(:account)
      create(:ai_agent_execution, :completed, account: other, agent: create(:ai_agent, account: other),
                                              output_data: { "result" => "account B private transcript" })
    end

    it "404s an execution that was never recorded, and writes nothing" do
      post_run(execution_id: SecureRandom.uuid)

      expect(response).to have_http_status(:not_found)
      expect(Ai::EvaluationResult.count).to eq(0)
    end

    it "404s another account's execution exactly as it 404s a missing one, and never judges it" do
      foreign = foreign_execution
      missing_id = SecureRandom.uuid
      expect(Ai::Learning::LlmJudgeService).not_to receive(:new)

      post_run(execution_id: missing_id)
      missing_body = response.body.gsub(missing_id, "ID")
      post_run(execution_id: foreign.id)

      expect(response).to have_http_status(:not_found)
      expect(response.body.gsub(foreign.id, "ID")).to eq(missing_body)
      expect(response.body).not_to include("account B private transcript")
      expect(response.body).not_to include(foreign.id)
      expect(Ai::EvaluationResult.count).to eq(0)
    end

    it "404s an account_id that is not the calling worker's own" do
      foreign = foreign_execution
      expect(Ai::Learning::LlmJudgeService).not_to receive(:new)

      post_run(execution_id: foreign.id, account_id: foreign.account_id)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("account B private transcript")
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
