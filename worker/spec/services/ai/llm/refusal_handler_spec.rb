# frozen_string_literal: true

require 'spec_helper'

# adapt (one reframe) → visible fallback → respect a fallback refusal.
RSpec.describe Ai::Llm::RefusalHandler do
  let(:messages) { [{ role: 'user', content: 'harden my own infra' }] }

  def refusal_response(category: 'cyber', phase: 'pre_output')
    Ai::Llm::Response.new(content: nil, model: 'claude-fable-5',
                          refusal: { 'stop_reason' => 'refusal', 'category' => category, 'phase' => phase })
  end

  def ok_response(model:, content: 'ok')
    Ai::Llm::Response.new(content: content, model: model, finish_reason: 'end_turn')
  end

  it 'returns the original unchanged when there is no refusal' do
    handler = described_class.new(model: 'claude-fable-5', fallback_models: ['claude-opus-4-8'])
    resp = handler.run(messages: messages) { |m, _msgs| ok_response(model: m) }
    expect(resp.content).to eq('ok')
    expect(resp.refusal_recovery).to be_nil
  end

  it 'does NOT engage the framework for a non-Fable model that refuses' do
    handler = described_class.new(model: 'claude-opus-4-8', fallback_models: ['claude-sonnet-5'])
    calls = 0
    resp = handler.run(messages: messages) { |_m, _msgs| calls += 1; refusal_response }
    expect(calls).to eq(1) # no reframe, no fallback
    expect(resp.refused?).to be true
  end

  it 'adapts: ONE reframe on the same model resolves the refusal' do
    handler = described_class.new(model: 'claude-fable-5', fallback_models: ['claude-opus-4-8'])
    seen_models = []
    last_first_role = nil
    resp = handler.run(messages: messages) do |m, msgs|
      seen_models << m
      last_first_role = msgs.first[:role]
      seen_models.size == 1 ? refusal_response : ok_response(model: m, content: 'reframed ok')
    end
    expect(seen_models).to eq(%w[claude-fable-5 claude-fable-5]) # same model, one reframe
    expect(resp.content).to eq('reframed ok')
    expect(resp.served_by).to eq('claude-fable-5')
    expect(resp.refusal_recovery).to include('reframed' => true, 'fell_back' => false, 'resolved' => true)
    expect(last_first_role).to eq('system') # authorized-context note prepended on the reframe
  end

  it 'falls back to a non-Fable model when the reframe still refuses' do
    handler = described_class.new(model: 'claude-fable-5', fallback_models: ['claude-opus-4-8'])
    attempts = []
    resp = handler.run(messages: messages) do |m, _msgs|
      attempts << m
      m == 'claude-fable-5' ? refusal_response : ok_response(model: m, content: 'opus answer')
    end
    expect(attempts).to eq(%w[claude-fable-5 claude-fable-5 claude-opus-4-8])
    expect(resp.content).to eq('opus answer')
    expect(resp.served_by).to eq('claude-opus-4-8')
    expect(resp.refused?).to be false
    expect(resp.refusal_recovery).to include('fell_back' => true, 'resolved' => true, 'served_by' => 'claude-opus-4-8')
  end

  it 'replays the ORIGINAL history as-is on fallback (no reframe note)' do
    handler = described_class.new(model: 'claude-fable-5', fallback_models: ['claude-opus-4-8'])
    fallback_messages = nil
    handler.run(messages: messages) do |m, msgs|
      fallback_messages = msgs if m == 'claude-opus-4-8'
      m == 'claude-fable-5' ? refusal_response : ok_response(model: m)
    end
    expect(fallback_messages).to eq(messages)
  end

  it 'respects a fallback refusal: STOP (no 3rd model), surface a refusal, served_by nil' do
    handler = described_class.new(model: 'claude-fable-5', fallback_models: ['claude-opus-4-8'])
    attempts = []
    resp = handler.run(messages: messages) do |m, _msgs|
      attempts << m
      refusal_response(category: (m == 'claude-fable-5' ? 'cyber' : 'bio'))
    end
    expect(attempts).to eq(%w[claude-fable-5 claude-fable-5 claude-opus-4-8]) # never a 3rd model
    expect(resp.refused?).to be true
    expect(resp.served_by).to be_nil
    expect(resp.refusal_recovery).to include('fell_back' => true, 'resolved' => false)
  end

  it 'surfaces a structured refusal (never nil) when no fallback model is configured' do
    handler = described_class.new(model: 'claude-fable-5', fallback_models: [])
    attempts = []
    resp = handler.run(messages: messages) { |m, _msgs| attempts << m; refusal_response }
    expect(attempts).to eq(%w[claude-fable-5 claude-fable-5]) # original + one reframe, no fallback
    expect(resp.refused?).to be true
    expect(resp.refusal_recovery).to include('fell_back' => false, 'resolved' => false)
  end
end
