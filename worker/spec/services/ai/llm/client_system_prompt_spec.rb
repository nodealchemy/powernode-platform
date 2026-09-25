# frozen_string_literal: true

require 'spec_helper'

# Last hop of the system_prompt contract: every provider body builder puts
# opts[:system_prompt] in front of the model. The Ollama builder used to ignore it.
RSpec.describe Ai::Llm::Client, 'system_prompt in request bodies' do
  let(:messages) { [{ role: 'user', content: 'hi' }] }
  let(:system_prompt) { 'You are the contract-test agent.' }

  it 'Anthropic: lands in top-level system' do
    client = described_class.new(provider_type: 'anthropic', api_key: 'k')
    body = client.send(:build_anthropic_body, messages, 'claude-test', system_prompt: system_prompt,
                                                                       cache_system_prompt: false)
    expect(body[:system]).to eq(system_prompt)
  end

  it 'OpenAI: lands as the leading system message' do
    client = described_class.new(provider_type: 'openai', api_key: 'k')
    body = client.send(:build_openai_body, messages, 'gpt-test', system_prompt: system_prompt)
    expect(body[:messages].first).to eq(role: 'system', content: system_prompt)
  end

  it 'Ollama: lands as the leading system message' do
    client = described_class.new(provider_type: 'ollama', api_key: 'k', base_url: 'http://localhost:11434')
    body = client.send(:build_ollama_body, messages, 'llama-test', system_prompt: system_prompt)
    expect(body[:messages].first).to eq(role: 'system', content: system_prompt)
    expect(body[:messages].last).to eq(role: 'user', content: 'hi')
  end

  it 'Ollama: adds no system message when none is given' do
    client = described_class.new(provider_type: 'ollama', api_key: 'k', base_url: 'http://localhost:11434')
    body = client.send(:build_ollama_body, messages, 'llama-test')
    expect(body[:messages].map { |m| m[:role] }).to eq(['user'])
  end
end
