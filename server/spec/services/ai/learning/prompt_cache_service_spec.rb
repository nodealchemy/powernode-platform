# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Learning::PromptCacheService, type: :service do
  let(:mock_redis) { instance_double(Redis) }

  let(:system_prompt) { 'You are a helpful assistant.' }
  let(:user_prompt) { 'Explain quantum computing.' }
  let(:model_name) { 'gpt-4' }
  let(:temperature) { 0.7 }
  let(:cached_response) { { 'content' => 'Quantum computing uses qubits...', 'model' => 'gpt-4' } }

  before do
    # Reset class-level redis instance variable between tests
    described_class.instance_variable_set(:@redis, nil)
    allow(Redis).to receive(:new).and_return(mock_redis)

    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe '.lookup' do
    context 'when feature flag is disabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:prompt_caching).and_return(false)
      end

      it 'returns nil without hitting Redis' do
        expect(mock_redis).not_to receive(:get)

        result = described_class.lookup(
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          model_name: model_name,
          temperature: temperature
        )

        expect(result).to be_nil
      end
    end

    context 'when feature flag is enabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:prompt_caching).and_return(true)
      end

      context 'when cache hit' do
        before do
          allow(mock_redis).to receive(:get).and_return(cached_response.to_json)
          allow(mock_redis).to receive(:incr)
        end

        it 'returns the parsed cached response' do
          result = described_class.lookup(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            model_name: model_name,
            temperature: temperature
          )

          expect(result).to eq(cached_response)
        end

        it 'records a cache hit metric' do
          expect(mock_redis).to receive(:incr).with('prompt_cache_metrics:hits')
          expect(mock_redis).to receive(:incr).with("prompt_cache_metrics:hits:#{model_name}")

          described_class.lookup(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            model_name: model_name,
            temperature: temperature
          )
        end
      end

      context 'when cache miss' do
        before do
          allow(mock_redis).to receive(:get).and_return(nil)
          allow(mock_redis).to receive(:incr)
        end

        it 'returns nil' do
          result = described_class.lookup(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            model_name: model_name,
            temperature: temperature
          )

          expect(result).to be_nil
        end

        it 'records a cache miss metric' do
          expect(mock_redis).to receive(:incr).with('prompt_cache_metrics:misses')
          expect(mock_redis).to receive(:incr).with("prompt_cache_metrics:misses:#{model_name}")

          described_class.lookup(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            model_name: model_name,
            temperature: temperature
          )
        end
      end

      context 'when Redis raises an error' do
        before do
          allow(mock_redis).to receive(:get).and_raise(Redis::ConnectionError, 'Connection refused')
        end

        it 'returns nil' do
          result = described_class.lookup(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            model_name: model_name,
            temperature: temperature
          )

          expect(result).to be_nil
        end

        it 'logs the error' do
          expect(Rails.logger).to receive(:error).with(/Lookup failed/)

          described_class.lookup(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            model_name: model_name,
            temperature: temperature
          )
        end
      end
    end
  end

  describe '.store' do
    let(:response) { { 'content' => 'Stored response data' } }

    context 'when feature flag is disabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:prompt_caching).and_return(false)
      end

      it 'does not store anything in Redis' do
        expect(mock_redis).not_to receive(:setex)

        described_class.store(
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          model_name: model_name,
          temperature: temperature,
          response: response
        )
      end
    end

    context 'when feature flag is enabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:prompt_caching).and_return(true)
        allow(mock_redis).to receive(:setex)
      end

      it 'stores the response in Redis with default TTL' do
        expect(mock_redis).to receive(:setex).with(
          an_instance_of(String),
          300, # 5.minutes.to_i
          response.to_json
        )

        described_class.store(
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          model_name: model_name,
          temperature: temperature,
          response: response
        )
      end

      it 'accepts a custom TTL' do
        custom_ttl = 10.minutes

        expect(mock_redis).to receive(:setex).with(
          an_instance_of(String),
          custom_ttl.to_i,
          response.to_json
        )

        described_class.store(
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          model_name: model_name,
          temperature: temperature,
          response: response,
          ttl: custom_ttl
        )
      end

      it 'uses consistent cache keys for same inputs' do
        keys = []
        allow(mock_redis).to receive(:setex) do |key, _ttl, _value|
          keys << key
        end

        2.times do
          described_class.store(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            model_name: model_name,
            temperature: temperature,
            response: response
          )
        end

        expect(keys.uniq.length).to eq(1)
      end

      context 'when Redis raises an error' do
        before do
          allow(mock_redis).to receive(:setex).and_raise(Redis::ConnectionError, 'Connection refused')
        end

        it 'does not raise the error' do
          expect {
            described_class.store(
              system_prompt: system_prompt,
              user_prompt: user_prompt,
              model_name: model_name,
              temperature: temperature,
              response: response
            )
          }.not_to raise_error
        end

        it 'logs the error' do
          expect(Rails.logger).to receive(:error).with(/Store failed/)

          described_class.store(
            system_prompt: system_prompt,
            user_prompt: user_prompt,
            model_name: model_name,
            temperature: temperature,
            response: response
          )
        end
      end
    end
  end

  describe '.invalidate' do
    before do
      allow(mock_redis).to receive(:del)
    end

    it 'deletes the cache key from Redis' do
      expect(mock_redis).to receive(:del).with(an_instance_of(String))

      described_class.invalidate(
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        model_name: model_name,
        temperature: temperature
      )
    end

    it 'uses the same cache key as lookup and store' do
      stored_key = nil
      invalidated_key = nil

      allow(mock_redis).to receive(:setex) { |key, _ttl, _val| stored_key = key }
      allow(mock_redis).to receive(:del) { |key| invalidated_key = key }

      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:prompt_caching).and_return(true)

      described_class.store(
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        model_name: model_name,
        temperature: temperature,
        response: cached_response
      )

      described_class.invalidate(
        system_prompt: system_prompt,
        user_prompt: user_prompt,
        model_name: model_name,
        temperature: temperature
      )

      expect(stored_key).to eq(invalidated_key)
    end
  end

  describe '.metrics' do
    before do
      allow(mock_redis).to receive(:get).with('prompt_cache_metrics:hits').and_return('150')
      allow(mock_redis).to receive(:get).with('prompt_cache_metrics:misses').and_return('50')
    end

    it 'returns hits count' do
      expect(described_class.metrics[:hits]).to eq(150)
    end

    it 'returns misses count' do
      expect(described_class.metrics[:misses]).to eq(50)
    end

    it 'returns total requests' do
      expect(described_class.metrics[:total]).to eq(200)
    end

    it 'calculates hit rate percentage' do
      # 150 / 200 * 100 = 75.0
      expect(described_class.metrics[:hit_rate]).to eq(75.0)
    end

    it 'calculates estimated savings in USD' do
      # 150 * 0.01 = 1.50
      expect(described_class.metrics[:estimated_savings_usd]).to eq(1.50)
    end

    context 'when no metrics exist' do
      before do
        allow(mock_redis).to receive(:get).with('prompt_cache_metrics:hits').and_return(nil)
        allow(mock_redis).to receive(:get).with('prompt_cache_metrics:misses').and_return(nil)
      end

      it 'returns zeros for all metrics' do
        metrics = described_class.metrics
        expect(metrics[:hits]).to eq(0)
        expect(metrics[:misses]).to eq(0)
        expect(metrics[:total]).to eq(0)
        expect(metrics[:hit_rate]).to eq(0)
        expect(metrics[:estimated_savings_usd]).to eq(0.0)
      end
    end

    context 'when only hits exist (no misses)' do
      before do
        allow(mock_redis).to receive(:get).with('prompt_cache_metrics:hits').and_return('10')
        allow(mock_redis).to receive(:get).with('prompt_cache_metrics:misses').and_return(nil)
      end

      it 'calculates hit rate as 100%' do
        expect(described_class.metrics[:hit_rate]).to eq(100.0)
      end
    end
  end

  describe '.reset_metrics!' do
    it 'deletes both hits and misses keys from Redis' do
      expect(mock_redis).to receive(:del).with('prompt_cache_metrics:hits')
      expect(mock_redis).to receive(:del).with('prompt_cache_metrics:misses')

      described_class.reset_metrics!
    end
  end

  describe 'cache key generation (private)' do
    it 'produces different keys for different inputs' do
      key_a = described_class.send(:build_cache_key, 'prompt_a', 'user_a', 'gpt-4', 0.7)
      key_b = described_class.send(:build_cache_key, 'prompt_b', 'user_b', 'gpt-4', 0.7)

      expect(key_a).not_to eq(key_b)
    end

    it 'produces different keys for different temperatures' do
      key_a = described_class.send(:build_cache_key, system_prompt, user_prompt, model_name, 0.7)
      key_b = described_class.send(:build_cache_key, system_prompt, user_prompt, model_name, 0.9)

      expect(key_a).not_to eq(key_b)
    end

    it 'produces different keys for different models' do
      key_a = described_class.send(:build_cache_key, system_prompt, user_prompt, 'gpt-4', 0.7)
      key_b = described_class.send(:build_cache_key, system_prompt, user_prompt, 'claude-3', 0.7)

      expect(key_a).not_to eq(key_b)
    end

    it 'prefixes keys with the REDIS_NAMESPACE' do
      key = described_class.send(:build_cache_key, system_prompt, user_prompt, model_name, temperature)
      expect(key).to start_with('prompt_cache:')
    end

    it 'uses SHA256 hash in the key' do
      key = described_class.send(:build_cache_key, system_prompt, user_prompt, model_name, temperature)
      hash_part = key.split(':').last
      expect(hash_part).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe 'DEFAULT_TTL' do
    it 'is set to 5 minutes' do
      expect(described_class::DEFAULT_TTL).to eq(5.minutes)
    end
  end

  describe 'REDIS_NAMESPACE' do
    it 'is set to prompt_cache' do
      expect(described_class::REDIS_NAMESPACE).to eq('prompt_cache')
    end
  end

  describe 'METRICS_NAMESPACE' do
    it 'is set to prompt_cache_metrics' do
      expect(described_class::METRICS_NAMESPACE).to eq('prompt_cache_metrics')
    end
  end
end
