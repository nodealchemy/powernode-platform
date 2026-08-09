# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::LlmJudgeService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe "#initialize" do
    it "has no hardcoded default — the model derives from the evaluator agent at call time" do
      expect(service.evaluator_model).to be_nil
    end

    it "accepts custom evaluator model" do
      custom = described_class.new(account: account, evaluator_model: "gpt-4")
      expect(custom.evaluator_model).to eq("gpt-4")
    end
  end

  describe "#evaluate" do
    context "when agent is available" do
      let(:user) { create(:user, account: account) }
      let(:provider) { create(:ai_provider, :anthropic, account: account) }
      let(:judge_agent) { create(:ai_agent, account: account, provider: provider, creator: user, name: "LLM Judge") }
      let(:client) { instance_double(WorkerLlmClient) }

      before do
        judge_agent # ensure created
        allow(WorkerLlmClient).to receive(:new).with(hash_including(agent_id: judge_agent.id)).and_return(client)
      end

      it "parses valid JSON evaluation response" do
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '{"correctness": 4, "completeness": 5, "helpfulness": 4, "safety": 5, "feedback": "Well done"}',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )

        result = service.evaluate(agent_output: "Test output", task_description: "Write code")

        expect(result[:scores]["correctness"]).to eq(4)
        expect(result[:scores]["completeness"]).to eq(5)
        expect(result[:scores]["helpfulness"]).to eq(4)
        expect(result[:scores]["safety"]).to eq(5)
        expect(result[:feedback]).to eq("Well done")
      end

      it "handles response with surrounding text" do
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: 'Here is my evaluation: {"correctness": 3, "completeness": 3, "helpfulness": 3, "safety": 4, "feedback": "OK"} That is all.',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )

        result = service.evaluate(agent_output: "Test")

        expect(result[:scores]["correctness"]).to eq(3)
      end

      it "clamps scores to 1-5 range" do
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '{"correctness": 0, "completeness": 10, "helpfulness": -1, "safety": 6, "feedback": "edge"}',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )

        result = service.evaluate(agent_output: "Test")

        expect(result[:scores]["correctness"]).to eq(1)
        expect(result[:scores]["completeness"]).to eq(5)
        expect(result[:scores]["helpfulness"]).to eq(1)
        expect(result[:scores]["safety"]).to eq(5)
      end

      it "includes expected output section when provided" do
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '{"correctness": 4, "completeness": 4, "helpfulness": 4, "safety": 5, "feedback": "ok"}',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )

        service.evaluate(
          agent_output: "Result",
          task_description: "Task",
          expected_output: "Expected result"
        )
      end

      it "truncates long agent output" do
        long_output = "x" * 10_000
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '{"correctness": 3, "completeness": 3, "helpfulness": 3, "safety": 5, "feedback": "ok"}',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )

        service.evaluate(agent_output: long_output)
      end
    end

    context "when no agent is available" do
      it "returns default scores" do
        result = service.evaluate(agent_output: "Test")

        expect(result[:scores]["correctness"]).to eq(3)
        expect(result[:scores]["safety"]).to eq(5)
        expect(result[:feedback]).to include("Default scores")
      end
    end

    context "when client call raises an error" do
      let(:user) { create(:user, account: account) }
      let(:provider) { create(:ai_provider, :anthropic, account: account) }
      let(:judge_agent) { create(:ai_agent, account: account, provider: provider, creator: user, name: "LLM Judge") }

      before do
        judge_agent
        allow(WorkerLlmClient).to receive(:new).and_raise(StandardError, "connection error")
      end

      it "returns default scores with error message" do
        result = service.evaluate(agent_output: "Test")

        expect(result[:scores]["correctness"]).to eq(3)
        expect(result[:feedback]).to include("Default scores")
      end
    end

    context "when response is unparseable" do
      let(:user) { create(:user, account: account) }
      let(:provider) { create(:ai_provider, :anthropic, account: account) }
      let(:judge_agent) { create(:ai_agent, account: account, provider: provider, creator: user, name: "LLM Judge") }

      before do
        judge_agent
        client = instance_double(WorkerLlmClient)
        allow(WorkerLlmClient).to receive(:new).with(hash_including(agent_id: judge_agent.id)).and_return(client)
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "This is not JSON at all", usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )
      end

      it "returns default scores" do
        result = service.evaluate(agent_output: "Test")
        expect(result[:scores]["correctness"]).to eq(3)
        expect(result[:feedback]).to include("Default scores")
      end
    end
  end

  describe "governed tier routing (campaign 019f2163 inc4)" do
    let(:user) { create(:user, account: account) }
    let(:provider) { create(:ai_provider, :anthropic, account: account) }
    let(:judge_agent) { create(:ai_agent, account: account, provider: provider, creator: user, name: "LLM Judge") }
    let(:client) { instance_double(WorkerLlmClient) }

    before do
      judge_agent
      allow(WorkerLlmClient).to receive(:new).with(hash_including(agent_id: judge_agent.id)).and_return(client)
    end

    context "gate OFF (default)" do
      it "never invokes the tier resolver and uses the evaluator agent's resolved model as baseline" do
        derived_default = judge_agent.resolved_model
        expect(derived_default).to be_present # sanity: derivation must yield a model
        expect(Ai::Routing::TaskTierResolver).not_to receive(:resolve)
        expect(client).to receive(:complete).with(hash_including(model: derived_default)).and_return(
          Ai::Llm::Response.new(content: '{"correctness": 4, "completeness": 4, "helpfulness": 4, "safety": 5, "feedback": "ok"}',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )
        service.evaluate(agent_output: "Test output")
        # The reader reflects the model actually used (audited by EvaluationService)
        expect(service.evaluator_model).to eq(derived_default)
      end
    end

    context "gate ON, no explicit evaluator_model pin" do
      before { account.update!(settings: { "ai_task_tier_routing_enabled" => true }) }

      it "classifies with the explicit analysis task_type and lands on a cheap (light/standard) tier" do
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '{"correctness": 4, "completeness": 4, "helpfulness": 4, "safety": 5, "feedback": "ok"}',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )
        expect_any_instance_of(Ai::Routing::TaskComplexityClassifierService)
          .to receive(:classify_preview)
          .with(hash_including(task_type: "analysis"))
          .and_return(
            complexity_level: "moderate", complexity_score: 0.3, recommended_tier: "standard",
            signals: { token_density: 0.3, tool_complexity: 0.0, conversation_depth: 0.0,
                       content_complexity: 0.0, task_type_baseline: 0.5,
                       raw: { token_count: 80, tool_count: 0, message_count: 1 } },
            classifier_version: "1.0.0"
          )

        service.evaluate(agent_output: "Test output", task_description: "Write code")

        decision = Ai::RoutingDecision.last
        expect(decision).to be_present
        expect(%w[light standard]).to include(decision.model_tier)
        expect(decision.rationale["decision"]).not_to eq("escalate")
        expect(decision.rationale.dig("complexity", "task_type")).to eq("analysis")
      end

      it "links the persisted RoutingDecision to the AgentExecution TrackedWorkerLlmClient creates, so the outcome can be recorded" do
        allow(client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: '{"correctness": 4, "completeness": 4, "helpfulness": 4, "safety": 5, "feedback": "ok"}',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )
        allow_any_instance_of(Ai::Routing::TaskComplexityClassifierService)
          .to receive(:classify_preview)
          .and_return(
            complexity_level: "moderate", complexity_score: 0.3, recommended_tier: "standard",
            signals: { token_density: 0.3, tool_complexity: 0.0, conversation_depth: 0.0,
                       content_complexity: 0.0, task_type_baseline: 0.5,
                       raw: { token_count: 80, tool_count: 0, message_count: 1 } },
            classifier_version: "1.0.0"
          )

        service.evaluate(agent_output: "Test output", task_description: "Write code")

        decision = Ai::RoutingDecision.last
        execution = Ai::AgentExecution.last
        expect(execution).to be_present
        expect(decision.agent_execution_id).to eq(execution.id)
      end
    end

    # The judge's output contract is strict JSON scores parsed by
    # #parse_evaluation — a reasoning-tier substitution that answers in prose
    # silently degrades every score to the 3/3/3/5 defaults. A SUBSTITUTING
    # resolution is therefore declined (baseline model sent, decision annotated
    # considered-but-not-applied), mirroring IntentCaptureService.
    context "gate ON with a SUBSTITUTING resolution (JSON-output guard)" do
      before { account.update!(settings: { "ai_task_tier_routing_enabled" => true }) }

      let(:judge_response) do
        Ai::Llm::Response.new(content: '{"correctness": 4, "completeness": 4, "helpfulness": 4, "safety": 5, "feedback": "ok"}',
                               usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
      end
      let(:derived_default) { judge_agent.resolved_model }
      let(:resolution) do
        instance_double(Ai::Routing::TaskTierResolver::Resolution,
                        model: "some-reasoning-model", effort: "high", tier: :reasoning,
                        baseline_model: derived_default)
      end

      before do
        allow(service).to receive(:resolve_task_tier).and_return(resolution)
        allow(service).to receive(:routing_decision_id).and_return("rd-9")
        allow(service).to receive(:annotate_unapplied_resolution!)
      end

      it "declines the substitution — judges with the baseline model and reflects it in evaluator_model" do
        expect(client).to receive(:complete) do |**opts|
          expect(opts[:model]).to eq(derived_default)
          expect(opts[:effort]).to be_nil
          judge_response
        end
        service.evaluate(agent_output: "Test output")
        expect(service.evaluator_model).to eq(derived_default)
      end

      it "annotates the decision as considered-but-not-applied, with the delivered model" do
        allow(client).to receive(:complete).and_return(judge_response)
        expect(service).to receive(:annotate_unapplied_resolution!) do |id, reason:, delivered_model:|
          expect(id).to eq("rd-9")
          expect(reason).to match(/json/i)
          expect(delivered_model).to eq(derived_default)
        end
        service.evaluate(agent_output: "Test output")
      end
    end

    context "gate ON but the caller explicitly pinned evaluator_model" do
      before { account.update!(settings: { "ai_task_tier_routing_enabled" => true }) }

      it "honors the pin — never invokes the tier resolver" do
        pinned_service = described_class.new(account: account, evaluator_model: "gpt-4")
        expect(Ai::Routing::TaskTierResolver).not_to receive(:resolve)
        expect(client).to receive(:complete).with(hash_including(model: "gpt-4")).and_return(
          Ai::Llm::Response.new(content: '{"correctness": 4, "completeness": 4, "helpfulness": 4, "safety": 5, "feedback": "ok"}',
                                 usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 })
        )
        pinned_service.evaluate(agent_output: "Test output")
      end
    end
  end

  describe "parse misses are loud" do
    # "A silently-unparseable judge degrades learning invisibly" — when the
    # response yields no parseable JSON the neutral 3/3/3/5 defaults are
    # applied, which is invisible in every downstream metric. The defaults
    # stay (fail-soft is correct here) but the miss must be logged.
    it "warns when the judge response contains no JSON object" do
      expect(Rails.logger).to receive(:warn).with(/no JSON|parse/i).at_least(:once)
      allow(Rails.logger).to receive(:warn).and_call_original
      result = service.send(:parse_evaluation, "I think this output is quite good overall.")
      expect(result[:scores]["correctness"]).to eq(3)
    end

    it "warns when the JSON fails to parse" do
      expect(Rails.logger).to receive(:warn).with(/no JSON|parse/i).at_least(:once)
      allow(Rails.logger).to receive(:warn).and_call_original
      result = service.send(:parse_evaluation, '{"correctness": broken')
      expect(result[:scores]["correctness"]).to eq(3)
    end
  end

  describe "FALLBACK_PROMPT" do
    it "includes all four dimensions" do
      prompt = described_class::FALLBACK_PROMPT
      expect(prompt).to include("Correctness")
      expect(prompt).to include("Completeness")
      expect(prompt).to include("Helpfulness")
      expect(prompt).to include("Safety")
    end

    it "requests JSON format response" do
      expect(described_class::FALLBACK_PROMPT).to include("JSON format")
    end
  end
end
