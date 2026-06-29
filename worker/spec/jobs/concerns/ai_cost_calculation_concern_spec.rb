# frozen_string_literal: true

require 'spec_helper'
require 'active_support/concern'
require_relative '../../../app/jobs/concerns/ai_cost_calculation_concern'

RSpec.describe AiCostCalculationConcern do
  let(:host) { Class.new { include AiCostCalculationConcern }.new }

  describe '#token_cost (single source of truth for the cached-aware cost formula)' do
    it 'prices uncached input + output per 1K' do
      expect(host.send(:token_cost, input_tokens: 1000, output_tokens: 500, cached_tokens: 0,
                                    input_per_1k: 3.0, output_per_1k: 15.0, cached_per_1k: 0.0))
        .to be_within(1e-9).of(10.5)
    end

    it 'splits cached vs non-cached input when a cached rate is set' do
      # non_cached=600 → 0.6*3 + 0.4*0.3 = 1.8 + 0.12 = 1.92
      expect(host.send(:token_cost, input_tokens: 1000, output_tokens: 0, cached_tokens: 400,
                                    input_per_1k: 3.0, output_per_1k: 15.0, cached_per_1k: 0.3))
        .to be_within(1e-9).of(1.92)
    end

    it 'ignores cached tokens when the cached rate is zero' do
      expect(host.send(:token_cost, input_tokens: 1000, output_tokens: 0, cached_tokens: 400,
                                    input_per_1k: 3.0, output_per_1k: 15.0, cached_per_1k: 0.0))
        .to be_within(1e-9).of(3.0)
    end

    it 'clamps non-cached input at zero when cached exceeds input' do
      # non_cached=0 → 0 + 0.5*0.3 = 0.15
      expect(host.send(:token_cost, input_tokens: 100, output_tokens: 0, cached_tokens: 500,
                                    input_per_1k: 3.0, output_per_1k: 0.0, cached_per_1k: 0.3))
        .to be_within(1e-9).of(0.15)
    end
  end

  describe 'provider cost methods delegate to #token_cost (no formula drift)' do
    it 'calculate_anthropic_cost matches token_cost' do
      allow(host).to receive(:resolve_pricing).with('anthropic', 'claude').and_return(input: 3.0, output: 15.0, cached: 0.3)
      data = { 'usage' => { 'input_tokens' => 1000, 'output_tokens' => 500, 'cache_read_input_tokens' => 400 } }
      expect(host.send(:calculate_anthropic_cost, data, 'claude')).to eq(
        host.send(:token_cost, input_tokens: 1000, output_tokens: 500, cached_tokens: 400,
                               input_per_1k: 3.0, output_per_1k: 15.0, cached_per_1k: 0.3))
    end

    it 'calculate_openai_cost matches token_cost' do
      allow(host).to receive(:resolve_pricing).with('openai', 'gpt').and_return(input: 2.5, output: 10.0, cached: 1.25)
      data = { 'usage' => { 'prompt_tokens' => 800, 'completion_tokens' => 200, 'cached_tokens' => 300 } }
      expect(host.send(:calculate_openai_cost, data, 'gpt')).to eq(
        host.send(:token_cost, input_tokens: 800, output_tokens: 200, cached_tokens: 300,
                               input_per_1k: 2.5, output_per_1k: 10.0, cached_per_1k: 1.25))
    end

    it 'calculate_generic_cost matches token_cost' do
      allow(host).to receive(:fetch_model_pricing).with('openai', 'gpt').and_return(
        'input_per_1k' => 2.5, 'output_per_1k' => 10.0, 'cached_input_per_1k' => 1.25)
      provider = { 'provider_type' => 'OpenAI' }
      response = { prompt_tokens: 800, completion_tokens: 200, cached_tokens: 300, model: 'gpt' }
      expect(host.send(:calculate_generic_cost, provider, {}, response)).to eq(
        host.send(:token_cost, input_tokens: 800, output_tokens: 200, cached_tokens: 300,
                               input_per_1k: 2.5, output_per_1k: 10.0, cached_per_1k: 1.25))
    end
  end
end
