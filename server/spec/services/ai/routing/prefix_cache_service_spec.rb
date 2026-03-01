# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Routing::PrefixCacheService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  let(:messages_with_system) do
    [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Hello, how are you?" }
    ]
  end

  let(:long_messages) do
    messages = [
      { role: "system", content: "You are an expert." }
    ]
    10.times do |i|
      messages << { role: "user", content: "Question #{i}: " + ("detailed context " * 50) }
      messages << { role: "assistant", content: "Answer #{i}: " + ("detailed response " * 50) }
    end
    messages
  end

  let(:short_messages) do
    [{ role: "user", content: "Hi" }]
  end

  describe '#cache_key_for' do
    it 'generates a deterministic hash' do
      key1 = service.cache_key_for(messages: messages_with_system, model: "claude-sonnet-4")
      key2 = service.cache_key_for(messages: messages_with_system, model: "claude-sonnet-4")

      expect(key1).to eq(key2)
      expect(key1).to match(/\A[a-f0-9]{64}\z/) # SHA256 hex
    end

    it 'generates different keys for different models' do
      key1 = service.cache_key_for(messages: messages_with_system, model: "claude-sonnet-4")
      key2 = service.cache_key_for(messages: messages_with_system, model: "gpt-4.1")

      expect(key1).not_to eq(key2)
    end

    it 'generates different keys for different messages' do
      key1 = service.cache_key_for(messages: messages_with_system, model: "claude-sonnet-4")
      key2 = service.cache_key_for(messages: short_messages, model: "claude-sonnet-4")

      expect(key1).not_to eq(key2)
    end
  end

  describe '#should_cache?' do
    context 'with Anthropic models' do
      it 'returns true when system prompt is present' do
        expect(service.should_cache?(messages: messages_with_system, model: "claude-sonnet-4")).to be true
      end

      it 'returns false for short messages without system prompt' do
        expect(service.should_cache?(messages: short_messages, model: "claude-sonnet-4")).to be false
      end
    end

    context 'with OpenAI models' do
      it 'returns true for long prompts' do
        expect(service.should_cache?(messages: long_messages, model: "gpt-4.1")).to be true
      end

      it 'returns false for short prompts' do
        expect(service.should_cache?(messages: short_messages, model: "gpt-4.1")).to be false
      end
    end

    context 'with Ollama models' do
      it 'always returns true' do
        expect(service.should_cache?(messages: short_messages, model: "llama-3")).to be true
      end
    end
  end

  describe '#cache_config_for' do
    context 'for Anthropic' do
      it 'returns breakpoints configuration' do
        config = service.cache_config_for(provider_type: "anthropic", messages: messages_with_system)

        expect(config[:caching_enabled]).to be true
        expect(config[:provider]).to eq("anthropic")
        expect(config[:breakpoints]).to be_an(Array)
        expect(config[:max_breakpoints]).to eq(4)
      end

      it 'includes system message breakpoints' do
        config = service.cache_config_for(provider_type: "anthropic", messages: messages_with_system)

        system_breakpoints = config[:breakpoints].select { |b| b[:type] == "system" }
        expect(system_breakpoints).not_to be_empty
      end

      it 'respects max breakpoints limit' do
        config = service.cache_config_for(provider_type: "anthropic", messages: long_messages)

        expect(config[:breakpoints].length).to be <= 4
      end
    end

    context 'for OpenAI' do
      it 'returns automatic caching config' do
        config = service.cache_config_for(provider_type: "openai", messages: long_messages)

        expect(config[:provider]).to eq("openai")
        expect(config[:automatic]).to be true
        expect(config[:min_tokens]).to eq(1024)
      end

      it 'indicates when caching is not applicable' do
        config = service.cache_config_for(provider_type: "openai", messages: short_messages)

        expect(config[:caching_enabled]).to be false
      end
    end

    context 'for Ollama' do
      it 'returns keep_alive configuration' do
        config = service.cache_config_for(provider_type: "ollama", messages: messages_with_system)

        expect(config[:caching_enabled]).to be true
        expect(config[:provider]).to eq("ollama")
        expect(config[:keep_alive]).to eq("15m")
      end
    end

    context 'for unsupported provider' do
      it 'returns disabled config' do
        config = service.cache_config_for(provider_type: "unknown", messages: messages_with_system)

        expect(config[:caching_enabled]).to be false
        expect(config[:reason]).to eq("unsupported_provider")
      end
    end
  end

  describe '#estimate_cache_savings' do
    context 'for Anthropic' do
      it 'estimates savings with 90% discount on cached reads' do
        savings = service.estimate_cache_savings(messages: long_messages, provider_type: "anthropic")

        expect(savings[:total_tokens]).to be > 0
        expect(savings[:cacheable_tokens]).to be > 0
        expect(savings[:potential_savings_ratio]).to eq(0.9)
        expect(savings[:estimated_savings_per_request]).to be > 0
      end
    end

    context 'for OpenAI' do
      it 'estimates savings with 50% discount on cached prompts' do
        savings = service.estimate_cache_savings(messages: long_messages, provider_type: "openai")

        expect(savings[:potential_savings_ratio]).to eq(0.5)
        expect(savings[:cache_write_overhead]).to eq(0)
      end
    end

    context 'for unsupported provider' do
      it 'returns zero savings' do
        savings = service.estimate_cache_savings(messages: long_messages, provider_type: "unknown")

        expect(savings[:cacheable_tokens]).to eq(0)
        expect(savings[:potential_savings_ratio]).to eq(0)
      end
    end
  end
end
