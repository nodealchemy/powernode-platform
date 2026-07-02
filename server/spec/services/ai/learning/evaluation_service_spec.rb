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

  describe "#evaluate_execution" do
    let(:agent) { create(:ai_agent, account: account) }
    let(:execution) do
      create(:ai_agent_execution, :completed, account: account, agent: agent)
    end

    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:agent_evaluation).and_return(false)
      end

      it "returns nil without evaluating" do
        expect(Ai::Learning::LlmJudgeService).not_to receive(:new)

        result = service.evaluate_execution(execution: execution, output: "test output")
        expect(result).to be_nil
      end
    end

    context "when execution has no agent" do
      let(:agentless_execution) { double("Execution", respond_to?: true, agent: nil) }

      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:agent_evaluation).and_return(true)
        allow(agentless_execution).to receive(:respond_to?).with(:agent).and_return(true)
      end

      it "returns nil" do
        result = service.evaluate_execution(execution: agentless_execution, output: "test")
        expect(result).to be_nil
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:agent_evaluation).and_return(true)
      end

      it "spawns a thread for async evaluation" do
        judge = instance_double(Ai::Learning::LlmJudgeService)
        allow(Ai::Learning::LlmJudgeService).to receive(:new).and_return(judge)
        allow(judge).to receive(:evaluator_model).and_return("claude-sonnet-4-5-20250929")
        allow(judge).to receive(:evaluate).and_return({
          scores: { "correctness" => 4, "completeness" => 4, "helpfulness" => 4, "safety" => 5 },
          feedback: "Good output"
        })

        thread = service.evaluate_execution(
          execution: execution,
          output: "Agent generated output"
        )

        expect(thread).to be_a(Thread)
        thread.join(5)
      end

      it "persists the result with the model the judge actually used" do
        # Run the evaluation block inline: a real Thread gets its own DB
        # connection outside the test transaction and cannot see fixtures.
        allow(Thread).to receive(:new) { |&blk| blk.call }
        judge = instance_double(Ai::Learning::LlmJudgeService)
        allow(Ai::Learning::LlmJudgeService).to receive(:new).and_return(judge)
        allow(judge).to receive(:evaluator_model).and_return("resolved-model-x")
        allow(judge).to receive(:evaluate).and_return({
          scores: { "correctness" => 4, "completeness" => 4, "helpfulness" => 4, "safety" => 5 },
          feedback: "Good output"
        })

        service.evaluate_execution(execution: execution, output: "out")

        expect(Ai::EvaluationResult.last.evaluator_model).to eq("resolved-model-x")
      end

      it "still persists a result when the judge could not resolve a model (evaluator_model nil)" do
        # LlmJudgeService no longer hardcodes a default model; when no evaluator
        # agent is discoverable, evaluate returns default scores and
        # evaluator_model stays nil — the record must not be silently dropped
        # by the presence validation on Ai::EvaluationResult#evaluator_model.
        allow(Thread).to receive(:new) { |&blk| blk.call }
        judge = instance_double(Ai::Learning::LlmJudgeService)
        allow(Ai::Learning::LlmJudgeService).to receive(:new).and_return(judge)
        allow(judge).to receive(:evaluator_model).and_return(nil)
        allow(judge).to receive(:evaluate).and_return({
          scores: { "correctness" => 3, "completeness" => 3, "helpfulness" => 3, "safety" => 5 },
          feedback: "Default scores applied (evaluation unavailable)"
        })

        expect {
          service.evaluate_execution(execution: execution, output: "out")
        }.to change(Ai::EvaluationResult, :count).by(1)

        expect(Ai::EvaluationResult.last.evaluator_model).to eq("unresolved")
      end
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
end
