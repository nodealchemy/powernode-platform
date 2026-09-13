# frozen_string_literal: true

require 'rails_helper'

# Campaign 01a08c9b, E3 review F2 — AiResponseJobConcern#call_provider_streaming.
#
# E3 removed `|| 'gpt-4'` (retired, and the wrong provider's id for anything
# not OpenAI). The concern works off JSON hashes from the backend API. Its
# chain is two arms plus the refusal:
#
#   agent['model'] → provider['default_model'] (resolved server-side) → error
#
# E3b removed a third arm, "first supported_models id": catalog[0] is the
# most expensive model, and the tier rule lives on the server
# (Provider#default_model), which now sends its result in the agent payload.
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

  # E3b: the worker must NOT pick from the catalog itself. Mutation: put the
  # old `|| supported_models.first` arm back and this fails.
  it "never picks from supported_models itself — no server-resolved default means refusal" do
    result, sent = stream(provider: provider.merge('default_model' => nil), agent: {})

    expect(result).to eq(success: false, error: 'No model configured for this agent or its provider')
    expect(sent).to eq(:no_call), "the worker chose catalog[0] on its own"
  end

  it "returns the no-model error and makes NO provider call when nothing resolves" do
    result, sent = stream(provider: provider.merge('default_model' => nil, 'supported_models' => []), agent: {})

    expect(result).to eq(success: false, error: 'No model configured for this agent or its provider')
    expect(sent).to eq(:no_call)
  end
end
