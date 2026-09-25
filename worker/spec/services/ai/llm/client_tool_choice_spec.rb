# frozen_string_literal: true

require 'spec_helper'

# tool_choice is a provider-neutral intent ("auto" | "none" | "required" | "any" |
# <tool name>). Anthropic never gets a forced shape: current Claude models 400 on
# tool_choice type "any"/"tool". OpenAI keeps forcing. Mirrors
# server/spec/services/ai/llm/adapters/tool_choice_mapping_spec.rb.
RSpec.describe Ai::Llm::Client, 'tool_choice on the wire' do
  let(:messages) { [{ role: 'user', content: 'ask claude to review' }] }
  let(:tools) { [{ name: 'send_message', description: 'Send', parameters: { type: 'object' } }] }

  def sent_tool_choice(client, model, choice, response)
    captured = nil
    allow(client).to receive(:http_post) do |_url, body|
      captured = body
      [200, response, {}]
    end
    # max_tokens under the streaming ceiling keeps this on the http_post path.
    opts = choice.nil? ? { max_tokens: 1024 } : { tool_choice: choice, max_tokens: 1024 }
    client.complete_with_tools(messages: messages, tools: tools, model: model, **opts)
    captured[:tool_choice]
  end

  context 'with Anthropic' do
    let(:client) { described_class.new(provider_type: 'anthropic', api_key: 'k') }

    def choice_for(choice) = sent_tool_choice(client, 'claude-fable-5', choice, { 'content' => [] })

    it('sends auto when no choice is given') { expect(choice_for(nil)).to eq(type: 'auto') }
    it('keeps none') { expect(choice_for('none')).to eq(type: 'none') }

    ['required', 'any', 'send_message',
     { 'type' => 'function', 'function' => { 'name' => 'send_message' } }].each do |forced|
      it "degrades the forcing intent #{forced.inspect} to auto" do
        expect(choice_for(forced)).to eq(type: 'auto')
      end
    end
  end

  context 'with OpenAI' do
    let(:client) { described_class.new(provider_type: 'openai', api_key: 'k') }
    let(:ok) { { 'choices' => [{ 'message' => { 'content' => 'ok' }, 'finish_reason' => 'stop' }] } }

    def choice_for(choice) = sent_tool_choice(client, 'gpt-test', choice, ok)

    it('sends auto when no choice is given') { expect(choice_for(nil)).to eq('auto') }
    it('passes required through') { expect(choice_for('required')).to eq('required') }
    it('maps any to required') { expect(choice_for('any')).to eq('required') }

    it 'forces a named tool with the function shape' do
      expect(choice_for('send_message')).to eq(type: 'function', function: { name: 'send_message' })
    end
  end
end
