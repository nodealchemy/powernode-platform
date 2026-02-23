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
    context "when provider is available" do
      let(:provider) { create(:ai_provider, :anthropic, account: account) }
      let(:credential) { create(:ai_provider_credential, :default, account: account, provider: provider) }
      let(:client) { double("ProviderClientService") }

      before do
        allow(Ai::Provider).to receive(:where).and_return(Ai::Provider.where(id: provider.id))
        allow(Ai::ProviderCredential).to receive(:where).and_return(
          double(active: double(healthy: double(first: credential)))
        )
        allow(Ai::ProviderClientService).to receive(:new).and_return(client)
      end

      it "parses valid JSON evaluation response" do
        response = {
          content: '{"correctness": 4, "completeness": 5, "helpfulness": 4, "safety": 5, "feedback": "Well done"}'
        }
        allow(client).to receive(:chat).and_return(response)

        result = service.evaluate(agent_output: "Test output", task_description: "Write code")

        expect(result[:scores]["correctness"]).to eq(4)
        expect(result[:scores]["completeness"]).to eq(5)
        expect(result[:scores]["helpfulness"]).to eq(4)
        expect(result[:scores]["safety"]).to eq(5)
        expect(result[:feedback]).to eq("Well done")
      end

      it "handles response with surrounding text" do
        response = {
          content: 'Here is my evaluation: {"correctness": 3, "completeness": 3, "helpfulness": 3, "safety": 4, "feedback": "OK"} That is all.'
        }
        allow(client).to receive(:chat).and_return(response)

        result = service.evaluate(agent_output: "Test")

        expect(result[:scores]["correctness"]).to eq(3)
      end

      it "clamps scores to 1-5 range" do
        response = {
          content: '{"correctness": 0, "completeness": 10, "helpfulness": -1, "safety": 6, "feedback": "edge"}'
        }
        allow(client).to receive(:chat).and_return(response)

        result = service.evaluate(agent_output: "Test")

        expect(result[:scores]["correctness"]).to eq(1)
        expect(result[:scores]["completeness"]).to eq(5)
        expect(result[:scores]["helpfulness"]).to eq(1)
        expect(result[:scores]["safety"]).to eq(5)
      end

      it "includes expected output section when provided" do
        allow(client).to receive(:chat) do |args|
          prompt = args[:messages].first[:content]
          expect(prompt).to include("Expected Output:")
          { content: '{"correctness": 4, "completeness": 4, "helpfulness": 4, "safety": 5, "feedback": "ok"}' }
        end

        service.evaluate(
          agent_output: "Result",
          task_description: "Task",
          expected_output: "Expected result"
        )
      end

      it "truncates long agent output" do
        long_output = "x" * 10_000
        allow(client).to receive(:chat) do |args|
          prompt = args[:messages].first[:content]
          expect(prompt.length).to be < 10_000
          { content: '{"correctness": 3, "completeness": 3, "helpfulness": 3, "safety": 5, "feedback": "ok"}' }
        end

        service.evaluate(agent_output: long_output)
      end
    end

    context "when no provider is available" do
      before do
        allow(Ai::Provider).to receive(:where).and_return(Ai::Provider.none)
      end

      it "returns default scores" do
        result = service.evaluate(agent_output: "Test")

        expect(result[:scores]["correctness"]).to eq(3)
        expect(result[:scores]["safety"]).to eq(5)
        expect(result[:feedback]).to include("Default scores")
      end
    end

    context "when provider call raises an error" do
      before do
        provider = create(:ai_provider, :anthropic, account: account)
        credential = create(:ai_provider_credential, :default, account: account, provider: provider)

        allow(Ai::Provider).to receive(:where).and_return(Ai::Provider.where(id: provider.id))
        allow(Ai::ProviderCredential).to receive(:where).and_return(
          double(active: double(healthy: double(first: credential)))
        )
        allow(Ai::ProviderClientService).to receive(:new).and_raise(StandardError, "connection error")
      end

      it "returns default scores with error message" do
        result = service.evaluate(agent_output: "Test")

        expect(result[:scores]["correctness"]).to eq(3)
        expect(result[:feedback]).to include("Default scores")
      end
    end

    context "when response is unparseable" do
      before do
        provider = create(:ai_provider, :anthropic, account: account)
        credential = create(:ai_provider_credential, :default, account: account, provider: provider)

        allow(Ai::Provider).to receive(:where).and_return(Ai::Provider.where(id: provider.id))
        allow(Ai::ProviderCredential).to receive(:where).and_return(
          double(active: double(healthy: double(first: credential)))
        )

        client = double("ProviderClientService")
        allow(Ai::ProviderClientService).to receive(:new).and_return(client)
        allow(client).to receive(:chat).and_return({ content: "This is not JSON at all" })
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
