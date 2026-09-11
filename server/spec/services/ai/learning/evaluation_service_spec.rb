# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::EvaluationService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  # D4 — the judge is now driven from a worker job through
  # POST /api/v1/internal/ai/evaluations/run and runs SYNCHRONOUSLY in that
  # request. The Thread.new path is gone, and so are the two examples that
  # pinned it: they asserted a Thread was returned and stubbed Thread.new to
  # run inline, both of which describe an implementation this no longer has.
  #
  # Every arm below asserts the RETURN, because the method's contract is now
  # three explicit statuses rather than nil-or-a-thread.
  describe "#evaluate_execution" do
    let(:agent) { create(:ai_agent, account: account) }
    let(:execution) do
      create(:ai_agent_execution, :completed, account: account, agent: agent,
             output_data: { "result" => "agent generated output" })
    end
    let(:judge) { instance_double(Ai::Learning::LlmJudgeService) }
    # task_id is a uuid COLUMN: Rails casts a non-uuid string to nil silently,
    # which would collapse two distinct evaluations onto one idempotency key.
    # Real ids here so the round-trip is actually exercised.
    let(:task_one) { SecureRandom.uuid }
    let(:task_two) { SecureRandom.uuid }

    def stub_judge!(scores: { "correctness" => 4, "completeness" => 4, "helpfulness" => 4, "safety" => 5 },
                    feedback: "Good output", model: "resolved-model-x", degraded: false)
      allow(Ai::Learning::LlmJudgeService).to receive(:new).and_return(judge)
      allow(judge).to receive(:evaluator_model).and_return(model)
      verdict = { scores: scores, feedback: feedback }
      verdict[:degraded] = true if degraded
      allow(judge).to receive(:evaluate).and_return(verdict)
      judge
    end

    def enable_flag!(enabled)
      allow(Shared::FeatureFlagService).to receive(:enabled?)
        .with(:agent_evaluation).and_return(enabled)
    end

    # ---- arm 1 ----
    context "when the feature flag is off" do
      before { enable_flag!(false) }

      it "reports not_measured with EvaluationDisabled and never builds a judge" do
        expect(Ai::Learning::LlmJudgeService).not_to receive(:new)

        result = service.evaluate_execution(execution: execution, output: "test output")

        expect(result).to eq(status: "not_measured", reason: "EvaluationDisabled")
        expect(Ai::EvaluationResult.count).to eq(0)
      end
    end

    # ---- arm 2 ----
    context "when there is nothing evaluable" do
      before { enable_flag!(true) }

      it "reports AiSuspended while the account's kill switch is engaged" do
        # Both arms of the same setup: an evaluable execution and a working
        # judge, separated only by the halt.
        stub_judge!
        allow(account).to receive(:ai_suspended?).and_return(true)

        result = described_class.new(account: account).evaluate_execution(execution: execution)

        expect(result).to eq(status: "not_measured", reason: "AiSuspended")
        expect(Ai::EvaluationResult.count).to eq(0)
      end

      it "evaluates normally when the kill switch is not engaged" do
        stub_judge!
        allow(account).to receive(:ai_suspended?).and_return(false)

        result = described_class.new(account: account).evaluate_execution(execution: execution)

        expect(result[:status]).to eq("evaluated")
      end

      it "reports NoEvaluableExecution for a nil execution (never recorded)" do
        result = service.evaluate_execution(execution: nil)

        expect(result).to eq(status: "not_measured", reason: "NoEvaluableExecution")
      end

      it "reports NoEvaluableExecution when the execution has no agent" do
        agentless = double("Execution")
        allow(agentless).to receive(:respond_to?).with(:agent).and_return(true)
        allow(agentless).to receive(:agent).and_return(nil)

        result = service.evaluate_execution(execution: agentless)

        expect(result).to eq(status: "not_measured", reason: "NoEvaluableExecution")
      end

      it "reports NoEvaluableExecution when there is no transcript to judge" do
        blank = create(:ai_agent_execution, :completed, account: account, agent: agent, output_data: {})

        result = service.evaluate_execution(execution: blank)

        expect(result).to eq(status: "not_measured", reason: "NoEvaluableExecution")
      end

      it "reports JudgeUnavailable rather than persisting the neutral defaults" do
        # The other arm of the same oracle: a degraded verdict carries the SAME
        # 3/3/3/5 scores a real mediocre evaluation would, so the only thing
        # separating them is the flag. Persisting it would move trust and skill
        # effectiveness on a judge that never answered.
        stub_judge!(scores: { "correctness" => 3, "completeness" => 3, "helpfulness" => 3, "safety" => 5 },
                    feedback: "Default scores applied (evaluation unavailable)", degraded: true)

        result = service.evaluate_execution(execution: execution)

        expect(result).to eq(status: "not_measured", reason: "JudgeUnavailable")
        expect(Ai::EvaluationResult.count).to eq(0)
      end
    end

    # ---- arm 3 ----
    context "when the judge answers" do
      before { enable_flag!(true) }

      it "persists the row and returns the evaluated arm with scores" do
        stub_judge!

        result = nil
        expect {
          result = service.evaluate_execution(execution: execution, task_id: task_one)
        }.to change(Ai::EvaluationResult, :count).by(1)

        record = Ai::EvaluationResult.last
        expect(result[:status]).to eq("evaluated")
        expect(result[:evaluation_id]).to eq(record.id)
        expect(result[:idempotent]).to be(false)
        expect(record.execution_id).to eq(execution.id)
        expect(record.task_id).to eq(task_one)
        expect(record.scores["correctness"]).to eq(4)
      end

      it "reads the transcript from the execution when the caller passes no output" do
        stub_judge!
        expect(judge).to receive(:evaluate).with(hash_including(agent_output: /agent generated output/))

        service.evaluate_execution(execution: execution)
      end

      it "records the model the judge actually used" do
        stub_judge!(model: "resolved-model-x")

        service.evaluate_execution(execution: execution)

        expect(Ai::EvaluationResult.last.evaluator_model).to eq("resolved-model-x")
      end

      it "still persists when the judge could not resolve a model" do
        # No hardcoded default model: when no evaluator agent is discoverable
        # evaluator_model stays nil, and the record must not be dropped by the
        # presence validation on Ai::EvaluationResult#evaluator_model.
        stub_judge!(model: nil)

        expect {
          service.evaluate_execution(execution: execution)
        }.to change(Ai::EvaluationResult, :count).by(1)

        expect(Ai::EvaluationResult.last.evaluator_model).to eq("unresolved")
      end
    end

    # ---- idempotency, both arms ----
    context "idempotency on (execution_id, task_id)" do
      before { enable_flag!(true) }

      it "a retried completion writes ONE evaluation and does not re-run the judge" do
        stub_judge!

        first = service.evaluate_execution(execution: execution, task_id: task_one)
        second = nil
        expect {
          second = service.evaluate_execution(execution: execution, task_id: task_one)
        }.not_to change(Ai::EvaluationResult, :count)

        expect(second[:evaluation_id]).to eq(first[:evaluation_id])
        expect(second[:idempotent]).to be(true)
        expect(first[:idempotent]).to be(false)
        expect(judge).to have_received(:evaluate).once
      end

      it "a DIFFERENT task against the same execution is a different evaluation" do
        stub_judge!

        service.evaluate_execution(execution: execution, task_id: task_one)

        expect {
          service.evaluate_execution(execution: execution, task_id: task_two)
        }.to change(Ai::EvaluationResult, :count).by(1)
      end

      it "the database refuses a duplicate even with the pre-check bypassed" do
        # The find_by only saves an LLM call; the unique index NULLS NOT
        # DISTINCT is the actual guard, including for a nil task_id where
        # Postgres would otherwise treat the rows as distinct.
        stub_judge!
        service.evaluate_execution(execution: execution)

        expect {
          Ai::EvaluationResult.create!(account: account, agent: agent, execution_id: execution.id,
                                       task_id: nil, evaluator_model: "x", scores: { "correctness" => 1 })
        }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    # ---- trust ----
    context "trust quality" do
      before { enable_flag!(true) }

      it "writes quality_score and invokes the trust engine" do
        stub_judge!
        engine = instance_double(Ai::Autonomy::TrustEngineService, evaluate: true)
        allow(Ai::Autonomy::TrustEngineService).to receive(:new).and_return(engine)

        result = service.evaluate_execution(execution: execution)

        # scores average 4.25 on 1-5 -> (4.25 - 1) / 4 = 0.8125
        expect(result[:quality]).to eq(0.8125)
        expect(execution.reload.performance_metrics["quality_score"]).to eq(0.8125)
        expect(engine).to have_received(:evaluate).with(agent: agent, execution: execution)
      end

      it "does not touch trust when nothing was evaluated" do
        enable_flag!(false)
        expect(Ai::Autonomy::TrustEngineService).not_to receive(:new)

        service.evaluate_execution(execution: execution)

        expect(execution.reload.performance_metrics["quality_score"]).to be_nil
      end
    end

    # ---- skill version credit ----
    context "skill version outcome" do
      let(:skill) { create(:ai_skill, account: account) }
      let(:version) { create(:ai_skill_version, account: account, ai_skill: skill) }

      before do
        enable_flag!(true)
        allow(Ai::Autonomy::TrustEngineService).to receive(:new)
          .and_return(instance_double(Ai::Autonomy::TrustEngineService, evaluate: true))
      end

      it "records NoServedVersion when the execution names no skill version" do
        stub_judge!

        result = service.evaluate_execution(execution: execution)

        expect(result[:skill_outcome]).to eq(status: "not_measured", reason: "NoServedVersion")
      end

      it "credits a SUCCESS to the served version when quality clears the threshold" do
        # The other arm: the consumer works the moment attribution exists, so
        # the key is written on the fixture here. Nothing in production writes
        # it yet — that is D5's producer.
        execution.update!(execution_context: { described_class::SKILL_VERSION_CONTEXT_KEY => version.id })
        stub_judge!

        result = service.evaluate_execution(execution: execution)

        expect(result[:skill_outcome]).to include(status: "recorded", skill_version_id: version.id,
                                                  successful: true)
        expect(version.reload.success_count).to eq(1)
        expect(version.usage_count).to eq(1)
      end

      it "credits a FAILURE when quality is below the threshold" do
        execution.update!(execution_context: { described_class::SKILL_VERSION_CONTEXT_KEY => version.id })
        stub_judge!(scores: { "correctness" => 1, "completeness" => 1, "helpfulness" => 1, "safety" => 2 })

        result = service.evaluate_execution(execution: execution)

        expect(result[:skill_outcome]).to include(successful: false)
        expect(version.reload.failure_count).to eq(1)
        expect(version.success_count).to eq(0)
      end

      it "honors the account-level success threshold override" do
        execution.update!(execution_context: { described_class::SKILL_VERSION_CONTEXT_KEY => version.id })
        account.update!(settings: (account.settings || {}).merge(
          described_class::SUCCESS_QUALITY_THRESHOLD_SETTING => 0.95
        ))
        stub_judge!

        result = described_class.new(account: account.reload)
                                .evaluate_execution(execution: execution)

        # 0.8125 clears the 0.6 default but not 0.95 — both arms of the same
        # verdict, separated only by the setting.
        expect(result[:skill_outcome]).to include(successful: false)
      end
    end

    # ---- D4 review F1: a malformed verdict is not a score ----
    # Through the REAL judge, so the parse -> service chain is what is pinned:
    # the provider answers `{"scores": {}}`, and nothing may move.
    context "when the judge answers with a malformed verdict" do
      let(:skill) { create(:ai_skill, account: account) }
      let(:version) { create(:ai_skill_version, account: account, ai_skill: skill) }
      let(:judge_agent) { create(:ai_agent, account: account, name: "LLM Judge", slug: "llm-judge") }
      let(:client) { instance_double(WorkerLlmClient) }

      before do
        enable_flag!(true)
        judge_agent
        allow_any_instance_of(Ai::Tools::SemanticToolDiscoveryService).to receive(:discover).and_return([])
        allow(WorkerLlmClient).to receive(:new).with(hash_including(agent_id: judge_agent.id)).and_return(client)
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '{"scores": {}, "rationale": "empty"}',
                                usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 })
        )
        execution.update!(execution_context: { described_class::SKILL_VERSION_CONTEXT_KEY => version.id })
      end

      it "records not_measured naming the missing dimensions, and moves neither trust nor the version" do
        # The judge's OWN LLM call is tracked as an execution of the judge
        # agent, and that row's model hook evaluates trust for the JUDGE. That
        # is not what F1 is about: the judged execution must never reach trust.
        trust = instance_double(Ai::Autonomy::TrustEngineService, evaluate: true)
        allow(Ai::Autonomy::TrustEngineService).to receive(:new).and_return(trust)

        result = service.evaluate_execution(execution: execution)

        expect(trust).not_to have_received(:evaluate).with(hash_including(execution: execution))

        expect(result[:status]).to eq("not_measured")
        expect(result[:reason]).to eq("JudgeDimensionMissing")
        expect(result[:detail]).to include("correctness", "safety")
        expect(Ai::EvaluationResult.count).to eq(0)
        expect((execution.reload.performance_metrics || {})["quality_score"]).to be_nil
        expect(version.reload.usage_count).to eq(0)
      end
    end

    # ---- D4 review F6: one reason code per cause ----
    it "reports UnscoredEvaluation, not NoServedVersion, for an evaluation with no quality" do
      # A nil quality means the row carried no scores. "No version served" is
      # a different fact about a different thing, and shared one code before.
      expect(service.send(:record_skill_outcome, execution, nil))
        .to eq(status: "not_measured", reason: "UnscoredEvaluation")
    end

    # ---- D4 review F2: tenancy ----
    it "never judges another account's execution" do
      enable_flag!(true)
      other = create(:account)
      foreign = create(:ai_agent_execution, :completed, account: other, agent: create(:ai_agent, account: other),
                                                        output_data: { "result" => "account B private transcript" })
      expect(Ai::Learning::LlmJudgeService).not_to receive(:new)

      result = service.evaluate_execution(execution: foreign)

      expect(result).to eq(status: "not_measured", reason: "NoEvaluableExecution")
      expect(Ai::EvaluationResult.count).to eq(0)
    end
  end

  describe "#agent_score_trends" do
    let(:agent) { create(:ai_agent, account: account) }

    context "when no evaluation results exist" do
      it "returns empty hash" do
        result = service.agent_score_trends(agent.id)
        expect(result).to eq({})
      end
    end

    context "with evaluation results" do
      before do
        create_list(:ai_evaluation_result, 3, :good,
                    account: account, agent: agent)
      end

      it "returns trends with expected keys" do
        result = service.agent_score_trends(agent.id)

        expect(result).to include(
          :count, :average_correctness, :average_completeness,
          :average_helpfulness, :average_safety, :trend
        )
      end

      it "counts evaluations" do
        result = service.agent_score_trends(agent.id)
        expect(result[:count]).to eq(3)
      end

      it "returns stable trend with few results" do
        result = service.agent_score_trends(agent.id)
        expect(result[:trend]).to eq("stable")
      end
    end

    context "with enough results for trend calculation" do
      before do
        # Create 5 older low-scoring results
        5.times do
          create(:ai_evaluation_result, :poor,
                 account: account, agent: agent,
                 created_at: 20.days.ago)
        end

        # Create 5 newer high-scoring results
        5.times do
          create(:ai_evaluation_result, :excellent,
                 account: account, agent: agent,
                 created_at: 1.day.ago)
        end
      end

      it "detects improving trend" do
        result = service.agent_score_trends(agent.id)
        expect(result[:trend]).to eq("improving")
      end
    end

    it "respects the period parameter" do
      create(:ai_evaluation_result, :good,
             account: account, agent: agent,
             created_at: 60.days.ago)

      result = service.agent_score_trends(agent.id, period: 30.days)
      expect(result).to eq({})
    end
  end

  describe "#skill_performance_breakdown" do
    let(:agent) { create(:ai_agent, account: account) }

    it "returns per-skill entries when the evaluated execution's learnings carry skill_node_ids" do
      team_execution = create(:ai_team_execution, account: account)
      create(:ai_compound_learning, account: account,
             source_execution_id: team_execution.id,
             metadata: { "skill_node_ids" => %w[skill-a skill-b] })
      create(:ai_evaluation_result, :good, account: account, agent: agent,
             execution_id: team_execution.id)

      result = service.skill_performance_breakdown(agent_id: agent.id)

      expect(result.keys).to contain_exactly("skill-a", "skill-b")
      expect(result["skill-a"]).to include(:average_score, :evaluation_count, :min_score, :max_score)
      expect(result["skill-a"][:evaluation_count]).to eq(1)
    end

    it "does not raise and does not fabricate data for plain-string feedback with no attribution" do
      create(:ai_evaluation_result, :good, account: account, agent: agent,
             execution_id: SecureRandom.uuid)

      result = nil
      expect {
        result = service.skill_performance_breakdown(agent_id: agent.id)
      }.not_to raise_error

      expect(result).to eq({})
    end
  end
end
