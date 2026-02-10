# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Routing::TaskComplexityClassifierService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  let(:simple_messages) do
    [
      { role: "user", content: "What is 2 + 2?" }
    ]
  end

  let(:moderate_messages) do
    [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Please analyze the following code for potential performance issues and suggest improvements." },
      { role: "assistant", content: "I'll review the code. Could you share it?" },
      { role: "user", content: "def fibonacci(n)\n  return n if n <= 1\n  fibonacci(n-1) + fibonacci(n-2)\nend" }
    ]
  end

  let(:complex_messages) do
    [
      { role: "system", content: "You are an expert software architect specializing in distributed systems." },
      { role: "user", content: "I need you to analyze, compare, and evaluate the trade-offs between three different microservice architectures for our payment processing system. Consider scalability, performance, security implications, and provide a comprehensive proof of concept design with multi-step reasoning about failure modes." },
      { role: "assistant", content: "This is a complex architecture decision. Let me break this down systematically..." },
      { role: "user", content: "Also consider the mathematical optimization of our load balancing algorithm using the formula for weighted round-robin with health check intervals. Calculate the optimal distribution." },
      { role: "assistant", content: "For the load balancing optimization, we need to consider several factors..." },
      { role: "user", content: "```python\nclass LoadBalancer:\n    def __init__(self, servers):\n        self.servers = servers\n        self.weights = [1.0] * len(servers)\n    def route(self, request):\n        # Need optimization here\n        pass\n```\nPlease refactor and optimize this with proper error handling, logging, and thread safety." }
    ]
  end

  describe '#classify' do
    context 'with simple task' do
      it 'classifies as trivial/simple complexity' do
        result = service.classify(task_type: "simple_qa", messages: simple_messages)

        expect(result[:complexity_level]).to be_in(%w[trivial simple])
        expect(result[:recommended_tier]).to eq("economy")
        expect(result[:complexity_score]).to be_between(0.0, 0.4)
        expect(result[:classifier_version]).to eq("1.0.0")
      end

      it 'records an assessment in the database' do
        expect {
          service.classify(task_type: "simple_qa", messages: simple_messages)
        }.to change(Ai::TaskComplexityAssessment, :count).by(1)
      end

      it 'returns an assessment_id' do
        result = service.classify(task_type: "simple_qa", messages: simple_messages)
        expect(result[:assessment_id]).to be_present
      end
    end

    context 'with moderate task' do
      it 'classifies as moderate complexity' do
        result = service.classify(task_type: "code_review", messages: moderate_messages)

        expect(result[:complexity_level]).to be_in(%w[moderate complex])
        expect(result[:recommended_tier]).to be_in(%w[standard premium])
        expect(result[:complexity_score]).to be_between(0.25, 0.8)
      end
    end

    context 'with complex task' do
      it 'classifies as complex/expert complexity' do
        result = service.classify(task_type: "reasoning", messages: complex_messages)

        expect(result[:complexity_level]).to be_in(%w[complex expert])
        expect(result[:recommended_tier]).to eq("premium")
        expect(result[:complexity_score]).to be_between(0.4, 1.0)
      end
    end

    context 'with tools' do
      it 'increases complexity score with many tools' do
        tools = (1..15).map { |i| { name: "tool_#{i}" } }

        result_no_tools = service.classify(task_type: "agent_task", messages: simple_messages, tools: [])
        result_with_tools = service.classify(task_type: "agent_task", messages: simple_messages, tools: tools)

        expect(result_with_tools[:complexity_score]).to be > result_no_tools[:complexity_score]
      end
    end

    context 'with force_tier context' do
      it 'uses the forced tier' do
        result = service.classify(
          task_type: "simple_qa",
          messages: simple_messages,
          context: { force_tier: "premium" }
        )

        expect(result[:recommended_tier]).to eq("premium")
      end
    end

    context 'with unknown task type' do
      it 'falls back to default baseline' do
        result = service.classify(task_type: "unknown_type", messages: simple_messages)

        expect(result[:complexity_level]).to be_present
        expect(result[:recommended_tier]).to be_present
      end
    end

    it 'returns signals hash with raw data' do
      result = service.classify(task_type: "code_review", messages: moderate_messages)

      expect(result[:signals]).to be_a(Hash)
      expect(result[:signals][:token_density]).to be_a(Numeric)
      expect(result[:signals][:tool_complexity]).to be_a(Numeric)
      expect(result[:signals][:conversation_depth]).to be_a(Numeric)
      expect(result[:signals][:content_complexity]).to be_a(Numeric)
      expect(result[:signals][:task_type_baseline]).to be_a(Numeric)
      expect(result[:signals][:raw]).to be_a(Hash)
    end
  end

  describe '#classify_preview' do
    it 'returns result without persisting to database' do
      expect {
        service.classify_preview(task_type: "simple_qa", messages: simple_messages)
      }.not_to change(Ai::TaskComplexityAssessment, :count)
    end

    it 'returns same structure as classify minus assessment_id' do
      result = service.classify_preview(task_type: "simple_qa", messages: simple_messages)

      expect(result[:complexity_level]).to be_present
      expect(result[:complexity_score]).to be_present
      expect(result[:recommended_tier]).to be_present
      expect(result[:classifier_version]).to eq("1.0.0")
      expect(result).not_to have_key(:assessment_id)
    end
  end

  describe 'complexity signal detection' do
    it 'detects code content' do
      code_messages = [{ role: "user", content: "```ruby\ndef hello\n  puts 'world'\nend\n```" }]
      result = service.classify(task_type: "code_generation", messages: code_messages)

      expect(result[:signals][:raw][:has_code]).to be true
    end

    it 'detects math content' do
      math_messages = [{ role: "user", content: "Calculate the integral of x^2 from 0 to 5 using the formula." }]
      result = service.classify(task_type: "reasoning", messages: math_messages)

      expect(result[:signals][:raw][:has_math]).to be true
    end

    it 'counts high complexity keywords' do
      result = service.classify(task_type: "analysis", messages: complex_messages)

      expect(result[:signals][:raw][:high_complexity_keyword_count]).to be > 0
    end
  end
end
