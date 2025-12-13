# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentExecutionJob, type: :job do
  subject { described_class }

  # Shared examples for base job behavior
  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'
  it_behaves_like 'a job with timing metrics'

  let(:agent_execution_id) { 'execution-123' }
  let(:agent_id) { 'agent-456' }
  let(:provider_id) { 'provider-789' }
  let(:credential_id) { 'cred-101' }

  # Used by shared examples for job argument handling
  let(:job_args) { agent_execution_id }

  let(:agent_data) {
    {
      'id' => agent_id,
      'name' => 'Test AI Agent',
      'agent_type' => 'assistant',
      'prompt_template' => 'Please help with: {{topic}}',
      'system_prompt' => 'You are a helpful AI assistant.',
      'configuration' => {
        'model' => 'gpt-3.5-turbo',
        'multi_turn' => {
          'enabled' => true,
          'max_turns' => 3
        }
      }
    }
  }

  let(:provider_data) {
    {
      'id' => provider_id,
      'name' => 'OpenAI',
      'provider_type' => 'openai',
      'api_endpoint' => 'https://api.openai.com'
    }
  }

  let(:agent_execution_data) {
    {
      'id' => agent_execution_id,
      'status' => 'pending',
      'input_parameters' => {
        'topic' => 'Ruby on Rails testing',
        'context' => 'Best practices for RSpec'
      },
      'ai_agent' => agent_data,
      'ai_provider' => provider_data
    }
  }

  let(:credentials_data) {
    [
      {
        'id' => credential_id,
        'provider_id' => provider_id,
        'is_active' => true,
        'is_default' => true
      }
    ]
  }

  let(:decrypted_credentials) {
    {
      'api_key' => 'sk-test-key-123',
      'model' => 'gpt-3.5-turbo'
    }
  }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    # Bypass runaway loop detection in tests (it uses Redis)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe 'job configuration' do
    it 'is configured with correct queue' do
      expect(described_class.sidekiq_options['queue']).to eq('ai_agents')
    end

    it 'is configured with correct retry count' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end

    it 'includes AiJobsConcern' do
      expect(described_class.included_modules).to include(AiJobsConcern)
    end
  end

  describe '#execute' do
    let(:job_instance) { described_class.new }

    context 'with successful single-turn execution' do
      let(:ai_response) {
        {
          'success' => true,
          'response' => 'RSpec is a testing framework for Ruby...',
          'model' => 'gpt-3.5-turbo',
          'metadata' => {
            'tokens_used' => 150,
            'prompt_tokens' => 50,
            'response_time_ms' => 1200
          },
          'cost' => 0.003
        }
      }

      before do
        # Stub fetching agent execution
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => agent_execution_data }
        })

        # Stub updating status to running
        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        # Stub credentials fetch - use WebMock to match any query params
        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Stub credential decryption
        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => decrypted_credentials }
        })

        # Stub OpenAI API call
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { content: ai_response['response'] } }],
              usage: {
                total_tokens: 150,
                prompt_tokens: 50
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'executes successfully and completes the agent execution' do
        expect {
          job_instance.execute(agent_execution_id)
        }.not_to raise_error

        # Verify completion API call was made
        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including('status' => 'completed')
          }))
      end

      it 'logs execution start and completion' do
        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:info).with(
          a_string_matching(/Starting AI agent execution/)
        ).at_least(:once)
        expect(logger_double).to have_received(:info).with(
          a_string_matching(/AI agent execution completed successfully/)
        ).at_least(:once)
      end

      it 'includes cost and token metrics in completion' do
        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'cost_usd' => kind_of(Numeric),
              'tokens_used' => kind_of(Integer)
            )
          }))
      end
    end

    context 'with successful multi-turn execution' do
      let(:agent_execution_with_multi_turn) {
        agent_execution_data.deep_dup.tap do |data|
          data['ai_agent']['configuration']['multi_turn'] = {
            'enabled' => true,
            'max_turns' => 3
          }
        end
      }

      before do
        # Stub fetching agent execution
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => agent_execution_with_multi_turn }
        })

        # Stub status updates
        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        # Stub credentials - use WebMock to match any query params
        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => decrypted_credentials }
        })

        # Stub first turn - short response that triggers follow-up
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            { status: 200, body: { choices: [{ message: { content: 'Brief response' } }], usage: { total_tokens: 50 } }.to_json },
            { status: 200, body: { choices: [{ message: { content: 'More comprehensive response with full details...' } }], usage: { total_tokens: 150 } }.to_json }
          )
      end

      it 'executes multiple turns when follow-up is needed' do
        job_instance.execute(agent_execution_id)

        # Should make 2 API calls (initial + 1 follow-up)
        expect(WebMock).to have_requested(:post, 'https://api.openai.com/v1/chat/completions')
          .at_least_times(2)
      end

      it 'accumulates cost and tokens across turns' do
        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'tokens_used' => be > 50, # More than single turn
              'cost_usd' => be > 0
            )
          }))
      end

      it 'includes output data with content and response fields' do
        job_instance.execute(agent_execution_id)

        # After multi-turn execution, output should include both content and response fields
        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'output_data' => hash_including(
                'content' => kind_of(String),
                'response' => kind_of(String)
              )
            )
          }))
      end
    end

    context 'with state validation' do
      it 'does not execute agents in completed state' do
        completed_execution = agent_execution_data.merge('status' => 'completed')
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => completed_execution }
        })

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:warn).with(
          a_string_matching(/Agent execution not in executable state/)
        )

        # Should not make status update calls
        expect(WebMock).not_to have_requested(:patch, /.*api\/v1\/ai\/executions/)
      end

      it 'does not execute agents in failed state' do
        failed_execution = agent_execution_data.merge('status' => 'failed')
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => failed_execution }
        })

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:warn).with(
          a_string_matching(/Agent execution not in executable state/)
        )
      end

      it 'executes agents in queued state' do
        queued_execution = agent_execution_data.merge('status' => 'queued')
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => queued_execution }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => decrypted_credentials }
        })

        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 200, body: { choices: [{ message: { content: 'Response' } }], usage: { total_tokens: 100 } }.to_json)

        expect {
          job_instance.execute(agent_execution_id)
        }.not_to raise_error

        # Should update status to running
        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including('status' => 'running')
          }))
      end

      it 'validates presence of agent data' do
        execution_without_agent = agent_execution_data.merge('ai_agent' => nil)
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => execution_without_agent }
        })

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:error).with(
          a_string_matching(/Agent execution missing agent data/)
        )
      end

      it 'validates presence of provider data' do
        execution_without_provider = agent_execution_data.merge('ai_provider' => nil)
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => execution_without_provider }
        })

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:error).with(
          a_string_matching(/Agent execution missing provider data/)
        )
      end
    end

    context 'with API errors' do
      it 'handles fetch execution API failure' do
        # Stub a logical failure (API returns success but response indicates failure)
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => false,
          'error' => 'Execution not found'
        })

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:error).with(
          a_string_matching(/Failed to fetch agent execution/)
        )
      end

      it 'handles credentials fetch failure' do
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => agent_execution_data }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => false, 'error' => 'Credentials not found' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        job_instance.execute(agent_execution_id)

        # Should update execution status to failed
        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'status' => 'failed',
              'error_message' => a_string_matching(/Failed to fetch provider credentials/)
            )
          }))
      end

      it 'handles missing credentials' do
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => agent_execution_data }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => [] } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'status' => 'failed',
              'error_message' => a_string_matching(/No active credentials found/)
            )
          }))
      end

      it 'handles provider API errors' do
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => agent_execution_data }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => decrypted_credentials }
        })

        # Stub OpenAI API failure
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 500, body: { error: { message: 'OpenAI service unavailable' } }.to_json)

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'status' => 'failed',
              'error_message' => a_string_matching(/OpenAI API error/)
            )
          }))
      end

      it 'handles timeout errors' do
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => agent_execution_data }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => decrypted_credentials }
        })

        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_timeout

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        # Error messages use lowercase 'failed'
        expect(logger_double).to have_received(:error).with(
          a_string_matching(/failed/i)
        )
      end

      it 'updates execution to failed on StandardError' do
        # Only stub the PATCH endpoint - GET will raise an error
        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        # Stub to raise error on execution fetch - this will be caught by BaseJob
        stub_request(:get, /\/api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(headers: { 'Authorization' => expected_request_headers['Authorization'] })
          .to_raise(StandardError.new('Unexpected error'))

        logger_double = mock_logger
        # The exception will be caught and re-raised by BaseJob's perform method
        expect { job_instance.execute(agent_execution_id) }.to raise_error(StandardError, 'Unexpected error')

        expect(logger_double).to have_received(:error).at_least(:once)
      end
    end

    context 'with Ollama provider' do
      let(:ollama_provider) {
        {
          'id' => provider_id,
          'name' => 'Local Ollama',
          'provider_type' => 'ollama',
          'api_endpoint' => 'http://localhost:11434'
        }
      }

      let(:ollama_credentials) {
        {
          'base_url' => 'http://localhost:11434',
          'model' => 'deepseek-r1:1.5b'
        }
      }

      let(:ollama_execution) {
        agent_execution_data.merge('ai_provider' => ollama_provider)
      }

      before do
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => ollama_execution }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => ollama_credentials }
        })
      end

      it 'calls Ollama API successfully' do
        # Use a long enough response to avoid follow-up turns
        long_response = 'This is a comprehensive response from Ollama that provides detailed information about the requested topic with sufficient content.'
        stub_request(:post, 'http://localhost:11434/api/chat')
          .to_return(
            status: 200,
            body: {
              message: { content: long_response },
              eval_count: 100,
              prompt_eval_count: 50
            }.to_json
          )

        job_instance.execute(agent_execution_id)

        # Job uses the model from agent_data configuration, not credentials
        expect(WebMock).to have_requested(:post, 'http://localhost:11434/api/chat')
          .with(body: hash_including('model' => 'gpt-3.5-turbo')).at_least_times(1)
      end

      it 'calculates zero cost for Ollama (local)' do
        # Use a long enough response to avoid follow-up turns
        long_response = 'This is a comprehensive response from Ollama that provides detailed information about the requested topic with sufficient content.'
        stub_request(:post, 'http://localhost:11434/api/chat')
          .to_return(
            status: 200,
            body: {
              message: { content: long_response },
              eval_count: 100
            }.to_json
          )

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including('cost_usd' => 0.0)
          }))
      end
    end

    context 'with Anthropic provider' do
      let(:anthropic_provider) {
        {
          'id' => provider_id,
          'name' => 'Claude',
          'provider_type' => 'anthropic',
          'api_endpoint' => 'https://api.anthropic.com'
        }
      }

      let(:anthropic_credentials) {
        {
          'api_key' => 'sk-ant-test-key',
          'model' => 'claude-3-sonnet-20240229'
        }
      }

      let(:anthropic_execution) {
        agent_execution_data.merge('ai_provider' => anthropic_provider)
      }

      before do
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => anthropic_execution }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => anthropic_credentials }
        })
      end

      it 'calls Anthropic API with correct format' do
        # Return a response long enough to not trigger follow-up turns
        long_response = 'This is a comprehensive response from Claude that provides detailed information about the requested topic with sufficient content.'
        stub_request(:post, 'https://api.anthropic.com/v1/messages')
          .to_return(
            status: 200,
            body: {
              content: [{ text: long_response }],
              usage: {
                input_tokens: 50,
                output_tokens: 100
              }
            }.to_json
          )

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:post, 'https://api.anthropic.com/v1/messages')
          .with(
            headers: { 'x-api-key' => 'sk-ant-test-key' },
            body: hash_including('model' => 'claude-3-sonnet-20240229')
          ).at_least_times(1)
      end

      it 'calculates Anthropic cost correctly' do
        # Use a long enough response to avoid follow-up turns
        long_response = 'This is a comprehensive response from Claude that provides detailed information about the requested topic with sufficient content.'
        stub_request(:post, 'https://api.anthropic.com/v1/messages')
          .to_return(
            status: 200,
            body: {
              content: [{ text: long_response }],
              usage: {
                input_tokens: 1000,
                output_tokens: 2000
              }
            }.to_json
          )

        job_instance.execute(agent_execution_id)

        # Claude Sonnet: $0.003/1K input + $0.015/1K output - may have multiple turns
        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'cost_usd' => kind_of(Numeric)
            )
          }))
      end
    end

    context 'with response processing' do
      before do
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => agent_execution_data }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => decrypted_credentials }
        })
      end

      it 'removes <think> tags from responses' do
        response_with_think = '<think>Internal reasoning here</think>Actual response content'

        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { content: response_with_think } }],
              usage: { total_tokens: 100 }
            }.to_json
          )

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'output_data' => hash_including(
                'content' => 'Actual response content'
              )
            )
          }))
      end

      it 'extracts structured JSON data from responses' do
        response_with_json = "Here's the data:\n```json\n{\"result\": \"success\", \"value\": 42}\n```"

        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { content: response_with_json } }],
              usage: { total_tokens: 100 }
            }.to_json
          )

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'output_data' => hash_including(
                'structured_data' => { 'result' => 'success', 'value' => 42 }
              )
            )
          }))
      end

      it 'truncates excessively long responses' do
        very_long_response = 'a' * 15_000 # Exceeds 10KB limit

        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { content: very_long_response } }],
              usage: { total_tokens: 100 }
            }.to_json
          )

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'output_data' => hash_including(
                'content' => a_string_matching(/Response truncated due to length/)
              )
            )
          }))
      end

      it 'includes both content and response fields for compatibility' do
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(
            status: 200,
            body: {
              choices: [{ message: { content: 'Test response' } }],
              usage: { total_tokens: 100 }
            }.to_json
          )

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including(
              'output_data' => hash_including(
                'content' => 'Test response',
                'response' => 'Test response'
              )
            )
          }))
      end
    end
  end

  describe 'retry behavior' do
    it 'retries on BackendApiClient::ApiError' do
      Sidekiq::Testing.inline! do
        stub_backend_api_success(:get, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true,
          'data' => { 'agent_execution' => agent_execution_data }
        })

        stub_backend_api_success(:patch, "/api/v1/ai/executions/#{agent_execution_id}", {
          'success' => true
        })

        stub_request(:get, /\/api\/v1\/ai\/credentials/)
          .to_return(
            status: 200,
            body: { 'success' => true, 'data' => { 'credentials' => credentials_data } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_backend_api_success(:post, "/api/v1/ai/credentials/#{credential_id}/decrypt", {
          'success' => true,
          'data' => { 'credentials' => decrypted_credentials }
        })

        # First API call fails, which should be caught and handled by job
        stub_request(:post, 'https://api.openai.com/v1/chat/completions')
          .to_return(status: 503, body: { error: { message: 'Service unavailable' } }.to_json)

        # Job should complete (not raise) because it handles API errors internally
        job = described_class.new
        job.execute(agent_execution_id)

        # Verify status was updated to failed
        expect(WebMock).to have_requested(:patch, /.*api\/v1\/ai\/executions\/#{agent_execution_id}/)
          .with(body: hash_including({
            'agent_execution' => hash_including('status' => 'failed')
          }))
      end
    end
  end
end
