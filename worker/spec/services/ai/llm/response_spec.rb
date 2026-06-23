# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Llm::Response do
  describe '#success?' do
    it 'is true when content is present' do
      expect(described_class.new(content: 'hello').success?).to be(true)
    end

    it 'is true when only tool_calls are present' do
      expect(described_class.new(content: nil, tool_calls: [{ id: 't1' }]).success?).to be(true)
    end

    it 'is false when content is blank and there are no tool_calls' do
      expect(described_class.new(content: nil).success?).to be(false)
      expect(described_class.new(content: '').success?).to be(false)
    end
  end

  describe '#has_tool_calls?' do
    it 'reflects whether tool_calls is non-empty' do
      expect(described_class.new(tool_calls: [{ id: 't1' }]).has_tool_calls?).to be(true)
      expect(described_class.new.has_tool_calls?).to be(false)
    end
  end

  describe 'usage normalization' do
    it 'maps Anthropic-style keys and computes total as the sum when total is absent' do
      r = described_class.new(usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 2 })
      expect(r.prompt_tokens).to eq(10)
      expect(r.completion_tokens).to eq(5)
      expect(r.cached_tokens).to eq(2)
      expect(r.total_tokens).to eq(15)
    end

    it 'prefers an explicit total_tokens over the computed sum' do
      r = described_class.new(usage: { prompt_tokens: 7, completion_tokens: 3, total_tokens: 20 })
      expect(r.prompt_tokens).to eq(7)
      expect(r.completion_tokens).to eq(3)
      expect(r.total_tokens).to eq(20)
    end

    it 'defaults all token counts to 0 for empty usage' do
      r = described_class.new
      expect(r.prompt_tokens).to eq(0)
      expect(r.completion_tokens).to eq(0)
      expect(r.cached_tokens).to eq(0)
      expect(r.total_tokens).to eq(0)
    end
  end

  describe '#to_h' do
    it 'omits nil fields via compact but keeps non-nil defaults' do
      h = described_class.new(content: 'hi').to_h
      expect(h[:content]).to eq('hi')
      expect(h[:tool_calls]).to eq([])
      expect(h[:cost]).to eq(0.0)
      expect(h).to have_key(:usage)
      expect(h).not_to have_key(:model)
      expect(h).not_to have_key(:provider)
      expect(h).not_to have_key(:finish_reason)
    end
  end
end
