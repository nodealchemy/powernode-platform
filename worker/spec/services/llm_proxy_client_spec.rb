# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LlmProxyClient, type: :service do
  before { mock_powernode_worker_config }

  describe '#build_llm_client credential logging' do
    # CLAUDE.md cryptographic-material safety is ABSOLUTE: the decrypted
    # provider API key must never be logged in any form, not even a prefix.
    it 'never logs the decrypted API key, not even a prefix' do
      logger = instance_double(Logger)
      logged = []
      allow(logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(logger).to receive(:debug)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:error)
      allow(PowernodeWorker.application).to receive(:logger).and_return(logger)

      client = described_class.new(->(*) {})
      fake_key = 'sk-DEADBEEFsupersecret0123456789'
      allow(client.instance_variable_get(:@credential_resolver))
        .to receive(:resolve).and_return({ 'api_key' => fake_key })
      allow(Ai::Llm::Client).to receive(:for_credentials).and_return(double('llm_client'))

      client.send(:build_llm_client, {
        'provider_type' => 'openai',
        'provider_credential_id' => 'cred-abc-123def456',
        'provider_base_url' => 'https://api.example.com',
        'provider_name' => 'OpenAI'
      })

      joined = logged.join("\n")
      expect(joined).not_to include(fake_key)
      expect(joined).not_to include(fake_key[0, 8])
    end
  end

  # Same formula as the server's Ai::CostCalculationService: cache reads and
  # writes are subsets of prompt_tokens, each at its own catalog rate.
  describe '#calculate_response_cost' do
    it 'prices cache writes at the catalog write rate' do
      client = described_class.new(->(*) {})
      allow(client).to receive(:resolve_pricing).and_return(
        'input_per_1k' => 3.0, 'output_per_1k' => 15.0, 'cached_input_per_1k' => 0.3, 'cache_write_per_1k' => 3.75
      )
      response = Ai::Llm::Response.new(model: 'm', usage: { prompt_tokens: 1500, completion_tokens: 100,
                                                             cached_tokens: 400, cache_creation_tokens: 100 })

      expect(client.send(:calculate_response_cost, response)).to be_within(1e-6).of(3.0 + 0.12 + 0.375 + 1.5)
    end
  end
end
