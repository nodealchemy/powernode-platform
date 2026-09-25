# frozen_string_literal: true

require 'spec_helper'

# Every structured request goes out in strict form: closed objects, every
# property required (nullable where it was optional), unsupported bounds
# dropped. An open map raises instead of being silently closed. Mirrors
# server/spec/services/ai/llm/structured_schema_spec.rb.
RSpec.describe Ai::Llm::StructuredSchema do
  let(:loose) do
    {
      type: 'object',
      properties: {
        steps: {
          type: 'array', minItems: 1,
          items: { type: 'object', properties: { n: { type: 'integer' }, note: { type: 'string', maxLength: 80 } },
                   required: %w[n] }
        },
        confidence: { type: 'number', minimum: 0.0, maximum: 1.0 },
        mode: { type: 'string', enum: %w[fast safe] }
      },
      required: %w[steps confidence]
    }
  end

  subject(:strict) { described_class.normalize(loose, provider: :anthropic) }

  it 'closes every object and requires every property' do
    item = strict.dig('properties', 'steps', 'items')
    expect(strict['additionalProperties']).to be(false)
    expect(strict['required']).to eq(%w[steps confidence mode])
    expect(item['additionalProperties']).to be(false)
    expect(item['required']).to eq(%w[n note])
  end

  it 'makes a formerly optional property nullable, enum included' do
    expect(strict.dig('properties', 'mode')).to eq('type' => %w[string null], 'enum' => ['fast', 'safe', nil])
    expect(strict.dig('properties', 'steps', 'items', 'properties', 'note')).to eq('type' => %w[string null])
    expect(strict.dig('properties', 'steps', 'items', 'properties', 'n')).to eq('type' => 'integer')
  end

  it 'drops bounds the provider does not support' do
    expect(strict.dig('properties', 'confidence')).to eq('type' => 'number')
    expect(strict.dig('properties', 'steps')).not_to have_key('minItems')
  end

  it 'keeps bounds for a provider that supports them' do
    expect(described_class.normalize(loose, provider: :ollama).dig('properties', 'confidence')).to include('minimum' => 0.0)
  end

  it 'wraps a typeless optional property in anyOf with null' do
    schema = { type: 'object', properties: { x: { anyOf: [{ type: 'string' }, { type: 'integer' }] } } }
    expect(described_class.normalize(schema, provider: :openai).dig('properties', 'x'))
      .to eq('anyOf' => [{ 'anyOf' => [{ 'type' => 'string' }, { 'type' => 'integer' }] }, { 'type' => 'null' }])
  end

  it 'leaves an already strict schema unchanged' do
    expect(described_class.normalize(strict, provider: :anthropic)).to eq(strict)
  end

  it 'raises on an explicitly open map instead of closing it' do
    schema = { type: 'object', properties: { params: { type: 'object', additionalProperties: true } } }
    expect { described_class.normalize(schema, provider: :anthropic) }
      .to raise_error(described_class::OpenMapError, /\$\.params/)
  end

  it 'raises on a schema-valued additionalProperties and on a property-less object' do
    typed_map = { type: 'object', properties: { m: { type: 'object', additionalProperties: { type: 'string' } } } }
    bare = { type: 'object', properties: { m: { type: 'object' } } }
    expect { described_class.normalize(typed_map, provider: :openai) }.to raise_error(described_class::OpenMapError)
    expect { described_class.normalize(bare, provider: :openai) }.to raise_error(described_class::OpenMapError)
  end

  describe 'on the wire' do
    let(:schema) { { name: 'r', schema: loose } }

    def captured_body(provider)
      client = Ai::Llm::Client.new(provider_type: provider, api_key: 'k')
      captured = {}
      allow(client).to receive(:http_post) do |_url, body|
        captured[:body] = body
        [200, provider == 'anthropic' ? { 'content' => [], 'stop_reason' => 'end_turn' } : { 'choices' => [] }, {}]
      end
      client.complete_structured(messages: [{ role: 'user', content: 'x' }], schema: schema, model: 'm', max_tokens: 100)
      captured[:body]
    end

    it 'sends the strict schema to Anthropic' do
      sent = captured_body('anthropic').dig(:output_config, :format, :schema)
      expect(sent).to eq(described_class.normalize(loose, provider: :anthropic))
    end

    it 'sends the strict schema to OpenAI' do
      sent = captured_body('openai').dig(:response_format, :json_schema, :schema)
      expect(sent).to eq(described_class.normalize(loose, provider: :openai))
    end
  end
end
