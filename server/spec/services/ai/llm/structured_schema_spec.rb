# frozen_string_literal: true

require "rails_helper"

# Every structured request goes out in strict form: closed objects, every
# property required (nullable where it was optional), unsupported bounds
# dropped. An open map raises instead of being silently closed. Mirrors
# worker/spec/services/ai/llm/structured_schema_spec.rb.
RSpec.describe Ai::Llm::StructuredSchema do
  let(:loose) do
    {
      type: "object",
      properties: {
        confidence: { type: "number", minimum: 0.0, maximum: 1.0 },
        mode: { type: "string", enum: %w[fast safe] }
      },
      required: %w[confidence]
    }
  end

  it "closes objects, requires every property, nulls the optional ones and drops unsupported bounds" do
    strict = described_class.normalize(loose, provider: :anthropic)

    expect(strict).to eq(
      "type" => "object",
      "additionalProperties" => false,
      "required" => %w[confidence mode],
      "properties" => {
        "confidence" => { "type" => "number" },
        "mode" => { "type" => %w[string null], "enum" => [ "fast", "safe", nil ] }
      }
    )
  end

  it "raises on an open map instead of closing it" do
    schema = { type: "object", properties: { output: { type: "object", additionalProperties: true } } }
    expect { described_class.normalize(schema, provider: :openai) }.to raise_error(described_class::OpenMapError)
  end

  # The C7 reasoning schemas (and every other in-app schema) were written loose:
  # no additionalProperties false, numeric bounds. They pass through normalized.
  describe "in-app schemas" do
    schemas = {
      "ChainOfThought" => Ai::Reasoning::ChainOfThoughtService::REASONING_SCHEMA,
      "Reflection" => Ai::Reasoning::ReflectionService::REFLECTION_SCHEMA,
      "StarReasoning" => Ai::Reasoning::StarReasoningService::STAR_SCHEMA,
      "KnowledgeGraph extraction" => Ai::KnowledgeGraph::ExtractionService::EXTRACTION_SCHEMA,
      "Mesh consensus" => Ai::TeamStrategies::MeshStrategy::CONSENSUS_SCHEMA,
      "Task decomposition" => Ai::Planning::TaskDecompositionService::DECOMPOSITION_SCHEMA,
      "RAG reranking" => Ai::Rag::RerankingService::RERANKING_SCHEMA,
      "LLM judge" => Ai::Learning::LlmJudgeService::VERDICT_SCHEMA,
      "PRD" => Ai::Missions::PrdGenerationService::PRD_SCHEMA,
      "Intent brief" => Ai::Provisioning::IntentCaptureService::BRIEF_JSON_SCHEMA
    }
    schemas["OutputEvaluator"] = Ai::Reasoning::OutputEvaluatorService.new(account: nil).send(:build_schema, %w[accuracy])

    schemas.each do |label, wrapper|
      it "#{label} normalizes for Anthropic and OpenAI, closed and fully required" do
        inner = wrapper[:schema] || wrapper
        %i[anthropic openai].each do |provider|
          strict = described_class.normalize(inner, provider: provider)
          expect(strict["additionalProperties"]).to be(false)
          expect(strict["required"]).to match_array(strict["properties"].keys)
          expect(strict.to_s).not_to match(/"(minimum|maximum|minLength|maxLength)"/)
        end
      end
    end
  end

  describe "on the wire" do
    let(:schema) { { name: "r", schema: loose } }
    let(:messages) { [ { role: "user", content: "x" } ] }

    it "the Anthropic adapter sends the strict schema" do
      adapter = Ai::Llm::Adapters::AnthropicAdapter.new(api_key: "k", base_url: "https://api.anthropic.com/v1",
                                                        provider_name: "anthropic")
      body = nil
      allow(adapter).to receive(:http_post) { |_path, b| body = b; [ 200, { "content" => [] }, {} ] }
      adapter.complete_structured(messages: messages, schema: schema, model: "claude-fable-5", max_tokens: 100)
      expect(body.dig(:output_config, :format, :schema)).to eq(described_class.normalize(loose, provider: :anthropic))
    end

    it "the OpenAI adapter sends the strict schema" do
      adapter = Ai::Llm::Adapters::OpenaiAdapter.new(api_key: "k", base_url: "https://api.openai.com/v1")
      body = nil
      allow(adapter).to receive(:http_post) { |_path, b| body = b; [ 200, { "choices" => [] }, {} ] }
      adapter.complete_structured(messages: messages, schema: schema, model: "gpt-test")
      expect(body.dig(:response_format, :json_schema, :schema)).to eq(described_class.normalize(loose, provider: :openai))
    end
  end
end
