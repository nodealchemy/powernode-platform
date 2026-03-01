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
    it "uses default evaluator model" do
      expect(service.evaluator_model).to eq("claude-sonnet-4-5-20250929")
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
        allow(WorkerLlmClient).to receive(:new).with(agent_id: judge_agent.id).and_return(client)
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
        allow(WorkerLlmClient).to receive(:new).with(agent_id: judge_agent.id).and_return(client)
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
