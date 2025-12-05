# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiConversationProcessingJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before do
    mock_powernode_worker_config
    # Bypass runaway loop detection (uses Redis)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    # Allow all logging calls
    allow_logging_methods
  end

  let(:conversation_id) { SecureRandom.uuid }
  let(:message_id) { SecureRandom.uuid }
  let(:ai_message_id) { SecureRandom.uuid }
  let(:account_id) { SecureRandom.uuid }
  let(:provider_id) { SecureRandom.uuid }
  let(:credential_id) { SecureRandom.uuid }
  let(:agent_id) { SecureRandom.uuid }

  let(:conversation_data) do
    {
      'id' => conversation_id,
      'account_id' => account_id,
      'metadata' => { 'total_tokens' => 0, 'total_cost' => 0 },
      'ai_agent' => {
        'id' => agent_id,
        'name' => 'Test Agent',
        'ai_provider' => {
          'id' => provider_id,
          'name' => 'OpenAI',
          'slug' => 'openai',
          'provider_type' => 'openai'
        }
      },
      'ai_provider' => {
        'id' => provider_id,
        'name' => 'OpenAI',
        'slug' => 'openai',
        'provider_type' => 'openai'
      }
    }
  end

  let(:message_data) do
    {
      'id' => message_id,
      'role' => 'user',
      'content' => 'Hello, how are you?',
      'sender_type' => 'user'
    }
  end

  let(:ai_message_data) do
    {
      'id' => ai_message_id,
      'role' => 'assistant',
      'content' => 'Processing your request...',
      'processing_metadata' => {}
    }
  end

  let(:credentials_data) do
    {
      'id' => credential_id,
      'ai_provider_id' => provider_id,
      'is_active' => true,
      'is_default' => true
    }
  end

  describe '#execute' do
    let(:job) { described_class.new }

    context 'with valid conversation and message' do
      before do
        # Stub conversation fetch
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}", {
          'success' => true,
          'data' => { 'conversation' => conversation_data }
        })

        # Stub message fetch
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{message_id}", {
          'success' => true,
          'data' => { 'message' => message_data }
        })

        # Stub AI message placeholder creation
        stub_backend_api_success(:post, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'message' => ai_message_data }
        })

        # Stub credentials fetch
        stub_backend_api_success(:get, '/api/v1/ai/credentials', {
          'success' => true,
          'data' => { 'credentials' => [credentials_data] }
        })

        # Stub credential decryption
        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => {
            'credentials' => {
              'api_key' => 'sk-test-key',
              'model' => 'gpt-3.5-turbo'
            }
          }
        })

        # Stub conversation history fetch
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'messages' => [message_data] }
        })

        # Stub AI message update (for fetching updated message)
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true,
          'data' => { 'message' => ai_message_data.merge('content' => 'AI response here') }
        })

        # Stub AI message update
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true,
          'data' => { 'message' => ai_message_data }
        })

        # Stub conversation metadata update
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}", {
          'success' => true,
          'data' => { 'conversation' => conversation_data }
        })

        # Stub usage metrics
        stub_backend_api_success(:post, '/api/v1/ai/analytics/usage', {
          'success' => true
        })

        # Stub OpenAI API
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { role: 'assistant', content: 'Hello! I am doing well.' } }],
              usage: { total_tokens: 25, prompt_tokens: 10, completion_tokens: 15 }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'processes conversation successfully' do
        job.execute(conversation_id, message_id)

        expect_api_request(:post, "/api/v1/ai/conversations/#{conversation_id}/messages")
      end

      it 'creates AI message placeholder' do
        job.execute(conversation_id, message_id)

        expect_api_request(:post, "/api/v1/ai/conversations/#{conversation_id}/messages")
      end

      it 'updates AI message with response' do
        job.execute(conversation_id, message_id)

        expect_api_request(:patch, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}")
      end

      it 'records usage metrics' do
        job.execute(conversation_id, message_id)

        expect_api_request(:post, '/api/v1/ai/analytics/usage')
      end

      it 'logs processing info' do
        capture_logs_for(job)

        job.execute(conversation_id, message_id)

        expect_logged(:info, /DEBUG.*Starting AI response processing/)
      end
    end

    context 'when conversation not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}", {
          'success' => false,
          'error' => 'Not found'
        })
      end

      it 'returns early without processing' do
        result = job.execute(conversation_id, message_id)

        expect(result).to be_nil
      end
    end

    context 'when message not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}", {
          'success' => true,
          'data' => { 'conversation' => conversation_data }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{message_id}", {
          'success' => false,
          'error' => 'Not found'
        })
      end

      it 'returns early without processing' do
        result = job.execute(conversation_id, message_id)

        expect(result).to be_nil
      end
    end

    context 'when no credentials found' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}", {
          'success' => true,
          'data' => { 'conversation' => conversation_data }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{message_id}", {
          'success' => true,
          'data' => { 'message' => message_data }
        })
        stub_backend_api_success(:post, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'message' => ai_message_data }
        })
        stub_backend_api_success(:get, '/api/v1/ai/credentials', {
          'success' => true,
          'data' => { 'credentials' => [] }
        })
        # Stub for reloading the AI message after update
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true,
          'data' => { 'message' => ai_message_data }
        })
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true
        })
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}", { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/ai/analytics/usage', { 'success' => true })
      end

      it 'generates error response' do
        capture_logs_for(job)

        job.execute(conversation_id, message_id)

        expect_logged(:error, /No default credential available/)
      end
    end

    context 'with realtime option' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}", {
          'success' => true,
          'data' => { 'conversation' => conversation_data }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{message_id}", {
          'success' => true,
          'data' => { 'message' => message_data }
        })
        stub_backend_api_success(:post, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'message' => ai_message_data }
        })
        stub_backend_api_success(:post, "/api/v1/ai/conversations/#{conversation_id}/broadcast_status", {
          'success' => true
        })
        stub_backend_api_success(:post, "/api/v1/ai/conversations/#{conversation_id}/broadcast_response", {
          'success' => true
        })
        stub_backend_api_success(:get, '/api/v1/ai/credentials', {
          'success' => true,
          'data' => { 'credentials' => [credentials_data] }
        })
        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => { 'api_key' => 'sk-test', 'model' => 'gpt-3.5-turbo' } }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'messages' => [message_data] }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true,
          'data' => { 'message' => ai_message_data.merge('content' => 'Response') }
        })
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true
        })
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}", { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/ai/analytics/usage', { 'success' => true })
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 200, body: '{"choices":[{"message":{"role":"assistant","content":"Response"}}],"usage":{"total_tokens":10}}')
      end

      it 'broadcasts processing status' do
        job.execute(conversation_id, message_id, 'realtime' => true)

        # Job calls broadcast_status twice: once for "processing" and once for "complete"
        expect(
          a_request(:post, "http://localhost:3000/api/v1/ai/conversations/#{conversation_id}/broadcast_status")
        ).to have_been_made.at_least_once
      end

      it 'broadcasts AI response' do
        job.execute(conversation_id, message_id, 'realtime' => true)

        expect_api_request(:post, "/api/v1/ai/conversations/#{conversation_id}/broadcast_response")
      end
    end

    context 'with Ollama provider' do
      let(:ollama_conversation) do
        conversation_data.merge(
          'ai_provider' => {
            'id' => provider_id,
            'name' => 'Ollama',
            'slug' => 'ollama',
            'provider_type' => 'ollama'
          },
          'ai_agent' => conversation_data['ai_agent'].merge(
            'ai_provider' => {
              'id' => provider_id,
              'slug' => 'ollama',
              'provider_type' => 'ollama'
            }
          )
        )
      end

      before do
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}", {
          'success' => true,
          'data' => { 'conversation' => ollama_conversation }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{message_id}", {
          'success' => true,
          'data' => { 'message' => message_data }
        })
        stub_backend_api_success(:post, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'message' => ai_message_data }
        })
        stub_backend_api_success(:get, '/api/v1/ai/credentials', {
          'success' => true,
          'data' => { 'credentials' => [credentials_data] }
        })
        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => {
            'credentials' => {
              'base_url' => 'http://localhost:11434',
              'model' => 'llama2'
            }
          }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'messages' => [message_data] }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true,
          'data' => { 'message' => ai_message_data.merge('content' => 'Ollama response') }
        })
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true
        })
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}", { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/ai/analytics/usage', { 'success' => true })

        stub_request(:post, 'http://localhost:11434/api/chat')
          .to_return(
            status: 200,
            body: {
              message: { role: 'assistant', content: 'Hello from Ollama!' },
              eval_count: 15,
              prompt_eval_count: 10
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'routes to Ollama service' do
        capture_logs_for(job)

        job.execute(conversation_id, message_id)

        expect_logged(:info, /Ollama/)
      end

      it 'makes request to Ollama endpoint' do
        job.execute(conversation_id, message_id)

        expect(WebMock).to have_requested(:post, 'http://localhost:11434/api/chat')
      end
    end

    context 'when AI provider fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}", {
          'success' => true,
          'data' => { 'conversation' => conversation_data }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages/#{message_id}", {
          'success' => true,
          'data' => { 'message' => message_data }
        })
        stub_backend_api_success(:post, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'message' => ai_message_data }
        })
        stub_backend_api_success(:get, '/api/v1/ai/credentials', {
          'success' => true,
          'data' => { 'credentials' => [credentials_data] }
        })
        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => { 'api_key' => 'sk-test', 'model' => 'gpt-3.5-turbo' } }
        })
        stub_backend_api_success(:get, "/api/v1/ai/conversations/#{conversation_id}/messages", {
          'success' => true,
          'data' => { 'messages' => [message_data] }
        })
        stub_backend_api_success(:patch, "/api/v1/ai/conversations/#{conversation_id}/messages/#{ai_message_id}", {
          'success' => true
        })
        stub_backend_api_success(:post, '/api/v1/ai/analytics/usage', { 'success' => true })

        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'handles error and raises for retry' do
        expect { job.execute(conversation_id, message_id) }.to raise_error(StandardError)
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses ai_conversations queue' do
      expect(described_class.sidekiq_options['queue']).to eq('ai_conversations')
    end

    it 'has retry count of 3' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end
end
