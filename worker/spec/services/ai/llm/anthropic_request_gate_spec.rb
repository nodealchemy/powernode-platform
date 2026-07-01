# frozen_string_literal: true

require 'spec_helper'

# The Anthropic request gate (sampling params / thinking / effort) used to be
# re-implemented inline at every worker call site, so a new site could silently
# bypass it and 400 on an adaptive-only model. It now lives in ONE place —
# Ai::Llm::ModelCapabilities.apply_anthropic_request_gate! — and every worker
# Anthropic body-builder funnels through it. This spec pins the gate semantics
# and asserts each builder delegates to it.
RSpec.describe Ai::Llm::ModelCapabilities, '.apply_anthropic_request_gate!' do
  it 'omits sampling params for an adaptive-only model' do
    body = {}
    described_class.apply_anthropic_request_gate!(body, 'claude-fable-5', temperature: 0.7, top_p: 0.9)
    expect(body).not_to have_key(:temperature)
    expect(body).not_to have_key(:top_p)
  end

  it 'passes sampling params for a permissive model' do
    body = {}
    described_class.apply_anthropic_request_gate!(body, 'claude-opus-4-6', temperature: 0.7, top_p: 0.9)
    expect(body[:temperature]).to eq(0.7)
    expect(body[:top_p]).to eq(0.9)
  end

  it 'emits a thinking block only when surface_reasoning is asked on an adaptive-only model' do
    plain = {}
    described_class.apply_anthropic_request_gate!(plain, 'claude-fable-5', effort: 'high')
    expect(plain).not_to have_key(:thinking)

    surfaced = {}
    described_class.apply_anthropic_request_gate!(surfaced, 'claude-fable-5', surface_reasoning: true)
    expect(surfaced[:thinking]).to eq(type: 'adaptive', display: 'summarized')
  end

  it 'never emits a thinking block for a permissive model even when surface_reasoning is asked' do
    body = {}
    described_class.apply_anthropic_request_gate!(body, 'claude-opus-4-6', surface_reasoning: true)
    expect(body).not_to have_key(:thinking)
  end

  it 'sets output_config.effort only for effort-capable models' do
    adaptive = {}
    described_class.apply_anthropic_request_gate!(adaptive, 'claude-fable-5', effort: 'high')
    expect(adaptive[:output_config]).to eq(effort: 'high')

    permissive = {}
    described_class.apply_anthropic_request_gate!(permissive, 'claude-opus-4-6', effort: 'high')
    expect(permissive).not_to have_key(:output_config)
  end

  it 'merges effort into an existing output_config without clobbering it' do
    body = { output_config: { format: { type: 'json_schema' } } }
    described_class.apply_anthropic_request_gate!(body, 'claude-fable-5', effort: 'high')
    expect(body[:output_config]).to eq(format: { type: 'json_schema' }, effort: 'high')
  end

  describe 'every worker Anthropic body-builder funnels through the gate' do
    let(:messages) { [{ role: 'user', content: 'hi' }] }

    let(:harness) do
      Class.new do
        include ChatStreamingConcern
        include ChatFallbackProvidersConcern
        def make_http_request(*_args, **_kwargs); nil; end
        def parse_anthropic_response(*_args); {}; end
        def stream_sse_request(*_args); nil; end
        def log_info(*_args, **_kwargs); nil; end
        def log_error(*_args, **_kwargs); nil; end
      end.new
    end

    it 'Ai::Llm::Client#build_anthropic_body' do
      client = Ai::Llm::Client.new(provider_type: 'anthropic', api_key: 'k')
      expect(described_class).to receive(:apply_anthropic_request_gate!).at_least(:once).and_call_original
      client.send(:build_anthropic_body, messages, 'claude-fable-5', temperature: 0.7)
    end

    it 'ChatFallbackProvidersConcern#call_anthropic_non_streaming' do
      allow(harness).to receive(:make_http_request).and_return(nil)
      expect(described_class).to receive(:apply_anthropic_request_gate!).at_least(:once).and_call_original
      harness.send(:call_anthropic_non_streaming, 'k', nil, 'claude-fable-5', messages, 0.7, 100)
    end

    it 'ChatStreamingConcern#call_anthropic_streaming' do
      allow(harness).to receive(:stream_sse_request) do |_uri, _body, _headers, &blk|
        blk.call({ 'type' => 'content_block_delta', 'delta' => { 'text' => 'hi' } })
        true
      end
      expect(described_class).to receive(:apply_anthropic_request_gate!).at_least(:once).and_call_original
      harness.send(:call_anthropic_streaming, 'k', nil, 'claude-fable-5', messages, 0.7, 100)
    end
  end
end
