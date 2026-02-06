# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Guardrails::Pipeline, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  describe '#initialize' do
    it 'loads agent-specific config when agent is provided' do
      agent_config = create(:ai_guardrail_config, account: account, agent: agent)
      pipeline = described_class.new(account: account, agent: agent)

      # Verify by running a check and seeing config is applied
      result = pipeline.check_input(text: "hello")
      expect(result[:allowed]).to be true
    end

    it 'falls back to global config when no agent config exists' do
      global_config = create(:ai_guardrail_config, :global, account: account,
                             input_rails: [{ "type" => "token_limit", "max_tokens" => 10 }])
      pipeline = described_class.new(account: account, agent: agent)

      result = pipeline.check_input(text: "a" * 100)
      expect(result[:violations]).to be_present
    end

    it 'prefers agent-specific config over global config' do
      _global_config = create(:ai_guardrail_config, :global, account: account,
                              input_rails: [{ "type" => "token_limit", "max_tokens" => 1 }])
      _agent_config = create(:ai_guardrail_config, account: account, agent: agent,
                             input_rails: [])

      pipeline = described_class.new(account: account, agent: agent)
      result = pipeline.check_input(text: "a" * 1000)
      # Agent config has no rails, so everything passes
      expect(result[:allowed]).to be true
    end

    it 'handles nil config gracefully when no configs exist' do
      pipeline = described_class.new(account: account)
      result = pipeline.check_input(text: "hello")
      expect(result[:allowed]).to be true
    end
  end

  describe '#check_input' do
    context 'when no config exists' do
      it 'returns allow_result' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_input(text: "anything")

        expect(result).to eq({
          allowed: true,
          violations: [],
          violation_count: 0,
          blocked: false
        })
      end
    end

    context 'when config is inactive' do
      it 'returns allow_result' do
        create(:ai_guardrail_config, :inactive, account: account,
               input_rails: [{ "type" => "token_limit", "max_tokens" => 1 }])

        pipeline = described_class.new(account: account)
        result = pipeline.check_input(text: "a" * 1000)

        expect(result[:allowed]).to be true
        expect(result[:violations]).to be_empty
      end
    end

    context 'when all rails pass' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               input_rails: [
                 { "type" => "token_limit", "max_tokens" => 100_000 },
                 { "type" => "prompt_injection", "sensitivity" => "medium" }
               ])
      end

      it 'returns allow_result with no violations' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_input(text: "What is the weather today?")

        expect(result[:allowed]).to be true
        expect(result[:violations]).to be_empty
        expect(result[:violation_count]).to eq(0)
        expect(result[:blocked]).to be false
      end

      it 'records the check as not blocked' do
        pipeline = described_class.new(account: account)
        pipeline.check_input(text: "Hello world")

        config.reload
        expect(config.total_checks).to eq(1)
        expect(config.total_blocks).to eq(0)
      end
    end

    context 'when a rail fails with critical severity' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               input_rails: [
                 { "type" => "token_limit", "max_tokens" => 5 }
               ])
      end

      it 'blocks the request' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_input(text: "a" * 100)

        expect(result[:blocked]).to be true
        expect(result[:allowed]).to be false
        expect(result[:stage]).to eq(:input)
        expect(result[:violations]).to be_present
      end

      it 'records the check as blocked' do
        pipeline = described_class.new(account: account)
        pipeline.check_input(text: "a" * 100)

        config.reload
        expect(config.total_checks).to eq(1)
        expect(config.total_blocks).to eq(1)
      end
    end

    context 'when a rail fails with warning severity and block_on_failure is false' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               block_on_failure: false,
               input_rails: [
                 { "type" => "topic_restriction", "blocked_topics" => ["politics"] }
               ])
      end

      it 'allows the request but includes violations' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_input(text: "Tell me about politics in America")

        expect(result[:allowed]).to be true
        expect(result[:blocked]).to be false
        expect(result[:violations]).to be_present
        expect(result[:violation_count]).to eq(1)
      end
    end

    context 'when a rail fails with warning severity and block_on_failure is true' do
      let!(:config) do
        create(:ai_guardrail_config, :global, :block_on_failure, account: account,
               input_rails: [
                 { "type" => "topic_restriction", "blocked_topics" => ["politics"] }
               ])
      end

      it 'blocks the request' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_input(text: "Tell me about politics")

        expect(result[:blocked]).to be true
        expect(result[:allowed]).to be false
      end
    end

    context 'with multiple rail failures' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               input_rails: [
                 { "type" => "topic_restriction", "blocked_topics" => ["violence"] },
                 { "type" => "pii_detection", "pii_types" => ["email"] }
               ])
      end

      it 'collects all violations' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_input(text: "violence contact@example.com")

        expect(result[:violation_count]).to eq(2)
        expect(result[:violations].map { |v| v[:rail] }).to contain_exactly("topic_restriction", "pii_detection")
      end
    end
  end

  describe '#check_output' do
    context 'when no config exists' do
      it 'returns allow_result' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_output(text: "anything")

        expect(result[:allowed]).to be true
        expect(result[:violations]).to be_empty
      end
    end

    context 'when config is inactive' do
      it 'returns allow_result' do
        create(:ai_guardrail_config, :inactive, account: account,
               output_rails: [{ "type" => "credential_leak" }])

        pipeline = described_class.new(account: account)
        result = pipeline.check_output(text: "api_key: sk-abc123def456ghi789jkl012mno345pqr678stu901vwx234")

        expect(result[:allowed]).to be true
      end
    end

    context 'when all rails pass' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               output_rails: [
                 { "type" => "toxicity" },
                 { "type" => "credential_leak" }
               ])
      end

      it 'returns allow_result' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_output(text: "Here is the summary of your request.")

        expect(result[:allowed]).to be true
        expect(result[:violations]).to be_empty
      end
    end

    context 'when output contains violations' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               output_rails: [
                 { "type" => "credential_leak" }
               ])
      end

      it 'detects credential leaks and blocks' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_output(text: "Your API key is api_key: sk-abcdefghijklmnopqrstuvwxyz123456789012345678901234")

        expect(result[:blocked]).to be true
        expect(result[:stage]).to eq(:output)
      end
    end

    context 'with input_text for hallucination check' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               output_rails: [
                 { "type" => "hallucination_check" }
               ])
      end

      it 'passes input_text to the output rail' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_output(
          text: "I'm 100% certain this is correct",
          input_text: "What is the capital of France?"
        )

        expect(result[:violations]).to be_present
        expect(result[:violations].first[:rail]).to eq("hallucination_check")
      end
    end
  end

  describe '#check_retrieval' do
    context 'when no config exists' do
      it 'returns allow_result' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_retrieval(documents: ["doc1", "doc2"])

        expect(result[:allowed]).to be true
      end
    end

    context 'with content_filter rail' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               retrieval_rails: [
                 { "type" => "content_filter", "blocked_patterns" => ["classified", "top\\s+secret"] }
               ])
      end

      it 'blocks documents matching blocked patterns' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_retrieval(
          documents: [
            { content: "This is a normal document" },
            { content: "This contains classified information" }
          ]
        )

        expect(result[:violations]).to be_present
        expect(result[:violations].first[:message]).to include("Document 1")
      end

      it 'allows clean documents' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_retrieval(
          documents: [
            { content: "Normal document" },
            { content: "Another clean document" }
          ]
        )

        expect(result[:allowed]).to be true
        expect(result[:violations]).to be_empty
      end

      it 'handles string documents' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_retrieval(
          documents: ["normal text", "top secret document"]
        )

        expect(result[:violations]).to be_present
      end

      it 'handles documents with string keys' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_retrieval(
          documents: [{ "content" => "classified stuff" }]
        )

        expect(result[:violations]).to be_present
      end
    end

    context 'with relevance_check rail' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               retrieval_rails: [
                 { "type" => "relevance_check", "min_relevance" => 0.3 }
               ])
      end

      it 'passes all documents through relevance check' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_retrieval(documents: ["doc1", "doc2"])

        expect(result[:allowed]).to be true
        expect(result[:violations]).to be_empty
      end
    end

    context 'with unknown rail type' do
      let!(:config) do
        create(:ai_guardrail_config, :global, account: account,
               retrieval_rails: [
                 { "type" => "unknown_rail" }
               ])
      end

      it 'passes unknown rails' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_retrieval(documents: ["doc1"])

        expect(result[:allowed]).to be true
      end
    end

    context 'with multiple retrieval rails and multiple documents' do
      let!(:config) do
        create(:ai_guardrail_config, :global, :block_on_failure, account: account,
               retrieval_rails: [
                 { "type" => "relevance_check", "min_relevance" => 0.3 },
                 { "type" => "content_filter", "blocked_patterns" => ["forbidden"] }
               ])
      end

      it 'checks all documents against all rails' do
        pipeline = described_class.new(account: account)
        result = pipeline.check_retrieval(
          documents: [
            { content: "good document" },
            { content: "forbidden content" },
            { content: "another forbidden item" }
          ]
        )

        expect(result[:violations].size).to eq(2)
        expect(result[:blocked]).to be true
      end
    end
  end

  describe 'allow_result' do
    it 'has consistent structure' do
      pipeline = described_class.new(account: account)
      result = pipeline.check_input(text: "hello")

      expect(result).to have_key(:allowed)
      expect(result).to have_key(:violations)
      expect(result).to have_key(:violation_count)
      expect(result).to have_key(:blocked)
    end
  end

  describe 'GuardrailViolation error' do
    it 'includes rail_name, severity, and details' do
      error = Ai::Guardrails::Pipeline::GuardrailViolation.new(
        "Test violation",
        rail_name: "token_limit",
        severity: :critical,
        details: { max: 1000, actual: 5000 }
      )

      expect(error.message).to eq("Test violation")
      expect(error.rail_name).to eq("token_limit")
      expect(error.severity).to eq(:critical)
      expect(error.details).to eq({ max: 1000, actual: 5000 })
    end

    it 'defaults severity to warning' do
      error = Ai::Guardrails::Pipeline::GuardrailViolation.new(
        "Test", rail_name: "test"
      )

      expect(error.severity).to eq(:warning)
      expect(error.details).to eq({})
    end
  end

  describe 'record_and_build_result behavior' do
    let!(:config) do
      create(:ai_guardrail_config, :global, account: account,
             block_on_failure: false,
             input_rails: [
               { "type" => "token_limit", "max_tokens" => 5 }
             ])
    end

    it 'blocks when any violation has critical severity regardless of block_on_failure' do
      pipeline = described_class.new(account: account)
      result = pipeline.check_input(text: "a" * 100)

      # token_limit violations have :critical severity
      expect(result[:blocked]).to be true
    end

    it 'tracks total checks and blocks across multiple calls' do
      pipeline = described_class.new(account: account)

      pipeline.check_input(text: "short")   # passes
      pipeline.check_input(text: "a" * 100) # fails (critical)
      pipeline.check_input(text: "ok")      # passes

      config.reload
      expect(config.total_checks).to eq(3)
      expect(config.total_blocks).to eq(1)
    end
  end
end
