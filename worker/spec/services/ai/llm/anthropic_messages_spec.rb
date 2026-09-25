# frozen_string_literal: true

require 'spec_helper'

# Mirrors server/spec/services/ai/llm/anthropic_messages_spec.rb.
RSpec.describe Ai::Llm::AnthropicMessages do
  # Always-thinking model that accepts mid-conversation system messages, and one
  # that does not (the fallback path).
  let(:native_model) { 'claude-fable-5' }
  let(:fallback_model) { 'claude-sonnet-5' }

  def split(messages, model) = described_class.split(messages, model)

  it 'lifts only the leading run of system messages into top-level system' do
    system, messages = split([ { role: 'system', content: 'core' }, { role: 'user', content: 'hi' } ], native_model)
    expect(system).to eq('core')
    expect(messages).to eq([ { role: 'user', content: 'hi' } ])
  end

  it 'keeps a later system message in place, natively, after a user turn' do
    _system, messages = split([ { role: 'system', content: 'core' }, { role: 'user', content: 'hi' },
                                { role: 'system', content: 'note' } ], native_model)
    expect(messages).to eq([ { role: 'user', content: 'hi' }, { role: 'system', content: 'note' } ])
  end

  it 'falls back to a reminder block on the preceding user turn when the model lacks the feature' do
    _system, messages = split([ { role: 'user', content: 'hi' }, { role: 'system', content: 'note' } ], fallback_model)
    expect(messages).to eq([ { role: 'user', content: [ { type: 'text', text: 'hi' },
                                                        { type: 'text', text: "<system-reminder>\nnote\n</system-reminder>" } ] } ])
  end

  it 'uses the reminder form when native placement would be illegal (followed by a user turn)' do
    _system, messages = split([ { role: 'user', content: 'a' }, { role: 'system', content: 'note' },
                                { role: 'user', content: 'b' } ], native_model)
    expect(messages.first[:content].last[:text]).to include('note')
    expect(messages.map { |m| m[:role] }).to eq(%w[user user])
  end

  it 'gives a system message that follows an assistant turn its own user message' do
    _system, messages = split([ { role: 'user', content: 'a' }, { role: 'assistant', content: 'ok' },
                                { role: 'system', content: 'event' } ], native_model)
    expect(messages.last).to eq(role: 'user', content: [ { type: 'text', text: "<system-reminder>\nevent\n</system-reminder>" } ])
  end

  it 'joins a run of consecutive system messages into one placement' do
    _system, messages = split([ { role: 'user', content: 'a' }, { role: 'system', content: 'one' },
                                { role: 'system', content: 'two' } ], native_model)
    expect(messages.last).to eq(role: 'system', content: "one\n\ntwo")
  end

  it 'produces an append-only request from an append-only history' do
    h1 = [ { role: 'system', content: 'core' }, { role: 'user', content: 'a' }, { role: 'system', content: 'ctx 1' } ]
    h2 = h1 + [ { role: 'assistant', content: 'ok' }, { role: 'user', content: 'b' }, { role: 'system', content: 'ctx 2' } ]
    [ native_model, fallback_model ].each do |model|
      s1, m1 = split(h1, model)
      s2, m2 = split(h2, model)
      expect(s2).to eq(s1)
      expect(m2.first(m1.size)).to eq(m1), model
      expect(m2.to_s).to include('ctx 1') # the earlier injection survives into the later request
    end
  end

  it 'normalizes non-system messages through the given block' do
    _system, messages = described_class.split([ { role: 'tool', content: 'r' } ], native_model) { |m| m.merge(role: 'user') }
    expect(messages.first[:role]).to eq('user')
  end

  describe 'turn-scoped (clear_at) system messages' do
    let(:history) do
      [ { role: 'user', content: 'a' }, { role: 'system', content: 'ctx', clear_at: 'next_user_message' } ]
    end

    it 'keeps clear_at on the native form' do
      _system, messages = split(history, native_model)
      expect(messages.last).to eq(role: 'system', content: 'ctx', clear_at: 'next_user_message')
    end

    it 'drops it in the reminder fallback (earlier copies simply stay in place)' do
      _system, messages = split(history, fallback_model)
      expect(messages.to_s).not_to include('clear_at')
    end

    it 'declares the beta the body then needs' do
      _system, messages = split(history, native_model)
      expect(described_class.beta_headers(messages: messages)).to eq('anthropic-beta' => described_class::CLEAR_AT_BETA)
      expect(described_class.beta_headers(messages: [ { role: 'user', content: 'a' } ])).to eq({})
    end
  end
end
