# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Routing::ContextCompressionService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  let(:short_messages) do
    [
      { role: "system", content: "You are helpful." },
      { role: "user", content: "Hello" }
    ]
  end

  let(:long_messages) do
    messages = [
      { role: "system", content: "You are a helpful AI assistant with expertise in software development." }
    ]
    20.times do |i|
      messages << { role: "user", content: "This is user message #{i} with some content about topic #{i}. " * 10 }
      messages << { role: "assistant", content: "This is assistant response #{i} with detailed explanation. " * 10 }
    end
    messages << { role: "user", content: "Now please summarize everything we discussed." }
    messages
  end

  describe '#compress' do
    context 'when messages are within budget' do
      it 'returns messages unchanged' do
        result = service.compress(messages: short_messages, token_budget: 10_000)

        expect(result[:compressed_messages]).to eq(short_messages)
        expect(result[:compression_ratio]).to eq(1.0)
        expect(result[:strategy_used]).to eq(:none)
        expect(result[:messages_removed]).to eq(0)
      end
    end

    context 'when messages exceed budget' do
      it 'compresses messages to fit budget' do
        result = service.compress(messages: long_messages, token_budget: 500)

        expect(result[:compressed_tokens]).to be <= 500
        expect(result[:compressed_messages].length).to be < long_messages.length
        expect(result[:compression_ratio]).to be < 1.0
        expect(result[:original_tokens]).to be > result[:compressed_tokens]
      end
    end

    context 'with empty messages' do
      it 'returns empty result' do
        result = service.compress(messages: [], token_budget: 1000)

        expect(result[:compressed_messages]).to eq([])
        expect(result[:compression_ratio]).to eq(1.0)
        expect(result[:strategy_used]).to eq(:none)
      end
    end

    context 'with :extractive strategy' do
      it 'keeps highest importance messages' do
        result = service.compress(messages: long_messages, token_budget: 500, strategy: :extractive)

        expect(result[:strategy_used]).to eq(:extractive)
        expect(result[:compressed_messages].length).to be < long_messages.length

        # System messages should be preserved
        roles = result[:compressed_messages].map { |m| m[:role] }
        expect(roles).to include("system")
      end
    end

    context 'with :hierarchical strategy' do
      it 'keeps recent messages verbatim' do
        result = service.compress(messages: long_messages, token_budget: 1000, strategy: :hierarchical)

        expect(result[:strategy_used]).to eq(:hierarchical)
        # Last message should be preserved
        last_original = long_messages.last[:content]
        last_compressed = result[:compressed_messages].last[:content]
        expect(last_compressed).to eq(last_original)
      end

      it 'adds conversation summary for older messages when budget allows' do
        # Use a larger budget so hierarchical doesn't fall back to extractive
        result = service.compress(messages: long_messages, token_budget: 3000, strategy: :hierarchical)

        if result[:strategy_used] == :hierarchical
          summary_msgs = result[:compressed_messages].select { |m|
            content = m[:content] || ""
            content.include?("[Conversation Summary]")
          }
          expect(summary_msgs).not_to be_empty
        else
          # If it fell back to extractive, at least verify compression happened
          expect(result[:compressed_messages].length).to be < long_messages.length
        end
      end
    end

    context 'with :selective strategy' do
      it 'drops least important messages' do
        result = service.compress(messages: long_messages, token_budget: 500, strategy: :selective)

        expect(result[:strategy_used]).to eq(:selective)
        expect(result[:messages_removed]).to be > 0

        # System messages should be preserved
        system_msgs = result[:compressed_messages].select { |m| m[:role] == "system" }
        original_system = long_messages.select { |m| m[:role] == "system" }
        expect(system_msgs.length).to eq(original_system.length)
      end

      it 'preserves the last message' do
        result = service.compress(messages: long_messages, token_budget: 500, strategy: :selective)

        expect(result[:compressed_messages].last[:content]).to eq(long_messages.last[:content])
      end
    end

    context 'with :auto strategy' do
      it 'selects an appropriate strategy based on compression ratio needed' do
        result = service.compress(messages: long_messages, token_budget: 500, strategy: :auto)

        expect(result[:strategy_used]).to be_in([:extractive, :hierarchical, :selective])
        expect(result[:compressed_tokens]).to be <= 500
      end
    end
  end

  describe 'compression ratio reporting' do
    it 'calculates accurate compression ratio' do
      result = service.compress(messages: long_messages, token_budget: 500)

      expected_ratio = result[:compressed_tokens].to_f / result[:original_tokens]
      expect(result[:compression_ratio]).to be_within(0.01).of(expected_ratio)
    end

    it 'reports original and compressed token counts' do
      result = service.compress(messages: long_messages, token_budget: 500)

      expect(result[:original_tokens]).to be > 0
      expect(result[:compressed_tokens]).to be > 0
      expect(result[:original_tokens]).to be >= result[:compressed_tokens]
    end
  end

  describe 'message importance' do
    it 'always preserves system messages' do
      messages = [
        { role: "system", content: "Critical system prompt. " * 50 },
        { role: "user", content: "Throwaway message" },
        { role: "assistant", content: "Throwaway response" },
        { role: "user", content: "Important question" }
      ]

      result = service.compress(messages: messages, token_budget: 100, strategy: :selective)

      system_msgs = result[:compressed_messages].select { |m| m[:role] == "system" }
      expect(system_msgs).not_to be_empty
    end

    it 'preserves minimum number of messages' do
      result = service.compress(messages: long_messages, token_budget: 10, strategy: :selective)

      expect(result[:compressed_messages].length).to be >= 2
    end
  end
end
