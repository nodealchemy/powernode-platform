# frozen_string_literal: true

require 'rails_helper'

# Campaign 01a08c9b, E3 review F2 — AiResponseJobConcern#call_provider_streaming.
#
# E3 removed `|| 'gpt-4'` (retired, and the wrong provider's id for anything
# not OpenAI). The concern works off JSON hashes from the backend API, so —
# unlike the server copies — its chain really is three arms, plus the refusal:
#
#   agent['model'] → provider['default_model'] → first supported_models id → error
#
# This concern had no spec at all; the review found every one of those arms
# untested.
RSpec.describe AiResponseJobConcern, '#call_provider_streaming model resolution' do
  before { mock_powernode_worker_config }

  let(:job) { AiChatResponseJob.new }
  let(:messages) { [ { role: 'user', content: 'hi' } ] }
  let(:provider) { { 'provider_type' => 'openai', 'default_model' => 'provider-default-1', 'supported_models' => [ { 'id' => 'catalog-first-1' } ] } }

  def stream(provider:, agent:)
    sent = :no_call
    allow(job).to receive(:resolve_provider_credentials).and_return([ 'k', 'https://api.example.test' ])
    allow(job).to receive(:call_openai_streaming) do |_key, _url, model, *_rest|
      sent = model
      { success: true }
    end
    [ job.send(:call_provider_streaming, provider, {}, agent, messages), sent ]
  end

  it "sends the agent's own model pin first" do
    _, sent = stream(provider: provider, agent: { 'model' => 'agent-pin-1' })
    expect(sent).to eq('agent-pin-1')
  end

  it "falls back to the provider's default_model when the agent has no pin" do
    _, sent = stream(provider: provider, agent: { 'model' => '' })
    expect(sent).to eq('provider-default-1')
  end

  it "falls back to the first supported_models id — hash or string entry — when neither is set" do
    _, sent = stream(provider: provider.merge('default_model' => nil), agent: {})
    expect(sent).to eq('catalog-first-1')

    _, sent = stream(provider: provider.merge('default_model' => nil, 'supported_models' => [ 'catalog-string-1' ]), agent: {})
    expect(sent).to eq('catalog-string-1')
  end

  it "returns the no-model error and makes NO provider call when nothing resolves" do
    result, sent = stream(provider: provider.merge('default_model' => nil, 'supported_models' => []), agent: {})

    expect(result).to eq(success: false, error: 'No model configured for this agent or its provider')
    expect(sent).to eq(:no_call)
  end
end
