# frozen_string_literal: true

require 'spec_helper'

# The interactive-chat paths build their own Anthropic request bodies (bypassing
# Ai::Llm::Client#build_anthropic_body), so they must independently gate sampling
# params or Fable / Opus 4.7+ / Sonnet 5 would 400 on every chat turn.
RSpec.describe 'Anthropic chat sampling-param gating (worker concerns)' do
  let(:harness) do
    Class.new do
      include ChatStreamingConcern
      include ChatFallbackProvidersConcern
      # Boundary stubs so the concern methods build a body without real HTTP.
      def make_http_request(*_args, **_kwargs); nil; end
      def parse_anthropic_response(*_args); {}; end
      def stream_sse_request(*_args); nil; end
      def log_info(*_args, **_kwargs); nil; end
      def log_error(*_args, **_kwargs); nil; end
    end.new
  end

  let(:messages) { [{ role: 'user', content: 'hi' }] }

  # Capture the JSON body the fallback (non-streaming) Anthropic call would POST.
  def non_streaming_body(model)
    captured = nil
    allow(harness).to receive(:make_http_request) { |*_a, **kw| captured = kw[:body]; nil }
    harness.send(:call_anthropic_non_streaming, 'key', nil, model, messages, 0.7, 1024)
    JSON.parse(captured)
  end

  # Capture the JSON body the streaming Anthropic call would POST (yield one delta
  # so the happy path returns without falling back to non-streaming).
  def streaming_body(model)
    captured = nil
    allow(harness).to receive(:stream_sse_request) do |_uri, body, _headers, &blk|
      captured = body
      blk.call({ 'type' => 'content_block_delta', 'delta' => { 'text' => 'hi' } })
      true
    end
    harness.send(:call_anthropic_streaming, 'key', nil, model, messages, 0.7, 1024)
    JSON.parse(captured)
  end

  describe 'restricted models omit temperature' do
    %w[claude-fable-5 claude-opus-4-8].each do |model|
      it "non-streaming #{model}" do
        expect(non_streaming_body(model)).not_to have_key('temperature')
      end

      it "streaming #{model}" do
        expect(streaming_body(model)).not_to have_key('temperature')
      end
    end
  end

  describe 'permissive model still includes temperature (no regression)' do
    it 'non-streaming claude-opus-4-6' do
      expect(non_streaming_body('claude-opus-4-6')['temperature']).to eq(0.7)
    end

    it 'streaming claude-opus-4-6' do
      expect(streaming_body('claude-opus-4-6')['temperature']).to eq(0.7)
    end
  end
end
