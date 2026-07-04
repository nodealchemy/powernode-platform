# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiChatResponseJob, type: :job do
  subject(:job) { described_class.new }

  let(:conversation_id) { 'conv-123' }
  let(:agent) { { 'system_prompt' => 'You are a helpful assistant.' } }
  let(:conv_response) do
    {
      'success' => true,
      'data' => {
        'conversation' => {
          'recent_messages' => [
            { 'role' => 'user', 'content' => 'hello' },
            { 'role' => 'assistant', 'content' => 'hi there' }
          ]
        }
      }
    }
  end

  describe '#build_response_messages' do
    it 'reuses the already-fetched conversation instead of re-fetching it (IMP-258dee4f09b9)' do
      expect(job).not_to receive(:backend_api_get)

      messages = job.send(:build_response_messages, conv_response, conversation_id, agent)

      expect(messages).to include({ role: 'system', content: 'You are a helpful assistant.' })
      expect(messages).to include({ role: 'user', content: 'hello' })
      expect(messages).to include({ role: 'assistant', content: 'hi there' })
    end
  end
end
