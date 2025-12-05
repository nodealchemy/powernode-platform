# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Provider Integration', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :system_admin, account: account) }
  let(:ai_provider) { create(:ai_provider) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:current_account).and_return(account)
    allow_any_instance_of(ApplicationController).to receive(:authenticate_request).and_return(true)
  end

  describe 'Complete AI Provider Setup Workflow' do
    it 'completes full provider setup and testing workflow' do
      # Step 1: Setup default providers (as admin)
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(admin_user)
      
      post '/api/v1/ai/providers/setup_defaults'
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      
      # Verify Ollama was created with priority
      ollama = AiProvider.find_by(slug: 'ollama')
      expect(ollama).to be_present
      expect(ollama.priority_order).to eq(1)

      # Step 2: Create credentials for Ollama (as regular user)
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
      
      # Mock successful credential test
      allow_any_instance_of(AiProviderTestService).to receive(:test_with_details)
        .and_return({ success: true, response_time_ms: 1200 })
      
      post '/api/v1/ai/provider_credentials', params: {
        credential: {
          ai_provider_id: ollama.id,
          name: 'Local Ollama',
          credentials: {
            base_url: 'http://localhost:11434',
            model: 'llama2'
          }
        }
      }
      
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      
      credential = AiProviderCredential.last
      expect(credential.name).to eq('Local Ollama')
      expect(credential).to be_is_default
      expect(credential).to be_is_active

      # Step 3: Test the credential connection
      post "/api/v1/ai/providers/#{ollama.id}/test_connection"
      
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['success']).to be true

      # Step 4: Create an AI agent using the provider
      post '/api/v1/ai/agents', params: {
        agent: {
          ai_provider_id: ollama.id,
          name: 'Code Assistant',
          agent_type: 'code_assistant',
          description: 'Helps with coding tasks',
          configuration: {
            model: 'llama2',
            temperature: 0.2,
            max_tokens: 2000,
            system_prompt: 'You are an expert programmer.'
          }
        }
      }
      
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      
      agent = AiAgent.last
      expect(agent.name).to eq('Code Assistant')
      expect(agent.ai_provider).to eq(ollama)

      # Step 5: Create a conversation
      post '/api/v1/ai/conversations', params: {
        conversation: {
          ai_agent_id: agent.id,
          title: 'Python Help Session'
        }
      }
      
      expect(response).to have_http_status(:ok)
      conversation = AiConversation.last
      expect(conversation.title).to eq('Python Help Session')

      # Step 6: Send a message in the conversation
      post '/api/v1/ai/messages', params: {
        message: {
          conversation_id: conversation.id,
          sender_type: 'user',
          sender_id: user.id,
          content: 'Help me write a Python function to calculate fibonacci numbers'
        }
      }
      
      expect(response).to have_http_status(:ok)
      message = AiMessage.last
      expect(message.content).to include('fibonacci')

      # Step 7: Execute an agent task
      post '/api/v1/ai/agent_executions', params: {
        execution: {
          ai_agent_id: agent.id,
          input_data: {
            prompt: 'Generate a Python class for a simple calculator',
            parameters: { temperature: 0.1 }
          }
        }
      }
      
      expect(response).to have_http_status(:ok)
      execution = AiAgentExecution.last
      expect(execution.status).to eq('queued')
      expect(execution.ai_agent).to eq(agent)

      # Step 8: Check provider usage summary
      get '/api/v1/ai/providers/usage_summary', params: { 
        provider_id: ollama.id,
        period: 30
      }
      
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      
      summary = json_response['data']
      expect(summary).to have_key('total_executions')
      expect(summary).to have_key('success_rate')
    end
  end

  describe 'Error Handling and Recovery' do
    let!(:provider) { create(:ai_provider, slug: 'openai') }

    it 'handles credential validation errors gracefully' do
      post '/api/v1/ai/provider_credentials', params: {
        credential: {
          ai_provider_id: provider.id,
          name: 'Invalid OpenAI',
          credentials: {
            model: 'gpt-3.5-turbo'
            # Missing required api_key
          }
        }
      }
      
      expect(response).to have_http_status(:forbidden)
      expect(json_response['success']).to be false
      expect(json_response['error']).to include('api_key is required')
    end

    it 'handles credential test failures' do
      allow_any_instance_of(AiProviderTestService).to receive(:test_with_details)
        .and_return({ success: false, error: 'Invalid API key' })
      
      post '/api/v1/ai/provider_credentials', params: {
        credential: {
          ai_provider_id: provider.id,
          name: 'Bad OpenAI Key',
          credentials: {
            api_key: 'sk-invalid123',
            model: 'gpt-3.5-turbo'
          }
        }
      }
      
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['error']).to include('Invalid API key')
    end

    it 'handles provider unavailability' do
      get '/api/v1/ai/providers/invalid-id'
      
      expect(response).to have_http_status(:not_found)
      expect(json_response['error']).to eq('AI provider not found')
    end

    it 'handles permission errors' do
      # Try to create provider as regular user (should fail)
      post '/api/v1/ai/providers', params: {
        provider: {
          name: 'Custom Provider',
          slug: 'custom',
          provider_type: 'text_generation'
        }
      }
      
      expect(response).to have_http_status(:forbidden)
      expect(json_response['error']).to eq('Insufficient permissions to create providers')
    end
  end

  describe 'Multi-Provider Scenario' do
    let!(:ollama) { create(:ai_provider, slug: 'ollama', priority_order: 1) }
    let!(:openai) { create(:ai_provider, slug: 'openai', priority_order: 2) }
    let!(:anthropic) { create(:ai_provider, slug: 'anthropic', priority_order: 3) }

    before do
      # Create credentials for each provider
      allow_any_instance_of(AiProviderTestService).to receive(:test_with_details)
        .and_return({ success: true, response_time_ms: 1000 })
      
      [ollama, openai, anthropic].each do |provider|
        credentials = case provider.slug
                     when 'ollama'
                       { base_url: 'http://localhost:11434', model: 'llama2' }
                     when 'openai'
                       { api_key: 'sk-test123', model: 'gpt-3.5-turbo' }
                     when 'anthropic'
                       { api_key: 'ant-test123', model: 'claude-3-sonnet' }
                     end
        
        create(:ai_provider_credential,
               account: account,
               ai_provider: provider,
               name: "#{provider.name} Credential",
               credentials: credentials.to_json,
               is_active: true)
      end
    end

    it 'lists providers in priority order' do
      get '/api/v1/ai/providers'
      
      expect(response).to have_http_status(:ok)
      providers = json_response['data']['providers']
      
      expect(providers.first['slug']).to eq('ollama')
      expect(providers.second['slug']).to eq('openai')
      expect(providers.third['slug']).to eq('anthropic')
    end

    it 'tests all credentials at once' do
      post '/api/v1/ai/provider_credentials/test_all'
      
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      
      results = json_response['data']['test_results']
      expect(results.size).to eq(3)
      expect(results.all? { |r| r['success'] == true }).to be true
      
      summary = json_response['data']['summary']
      expect(summary['total_tested']).to eq(3)
      expect(summary['successful']).to eq(3)
      expect(summary['failed']).to eq(0)
    end

    it 'shows available providers for account' do
      get '/api/v1/ai/providers/available_for_account'
      
      expect(response).to have_http_status(:ok)
      providers = json_response['data']['providers']
      
      expect(providers.size).to eq(3)
      expect(providers.map { |p| p['slug'] }).to contain_exactly('ollama', 'openai', 'anthropic')
    end

    it 'creates agents with different providers' do
      # Create Ollama agent for code tasks
      post '/api/v1/ai/agents', params: {
        agent: {
          ai_provider_id: ollama.id,
          name: 'Local Code Assistant',
          agent_type: 'code_assistant',
          configuration: { model: 'llama2', temperature: 0.1 }
        }
      }
      
      expect(response).to have_http_status(:ok)
      ollama_agent = AiAgent.last
      
      # Create OpenAI agent for general tasks
      post '/api/v1/ai/agents', params: {
        agent: {
          ai_provider_id: openai.id,
          name: 'OpenAI Assistant',
          agent_type: 'assistant',
          configuration: { model: 'gpt-3.5-turbo', temperature: 0.7 }
        }
      }
      
      expect(response).to have_http_status(:ok)
      openai_agent = AiAgent.last
      
      # Verify different providers
      expect(ollama_agent.ai_provider.slug).to eq('ollama')
      expect(openai_agent.ai_provider.slug).to eq('openai')
    end
  end

  describe 'Analytics and Monitoring Integration' do
    let!(:provider) { create(:ai_provider) }
    let!(:credential) { create(:ai_provider_credential, account: account, ai_provider: provider) }
    let!(:agent) { create(:ai_agent, account: account, ai_provider: provider) }

    before do
      # Create some execution history
      create(:ai_agent_execution, :completed, ai_agent: agent, account: account)
      create(:ai_agent_execution, :failed, ai_agent: agent, account: account)
      create(:ai_agent_execution, :running, ai_agent: agent, account: account)
    end

    it 'provides comprehensive usage analytics' do
      get '/api/v1/ai/providers/usage_summary', params: { 
        provider_id: provider.id 
      }
      
      expect(response).to have_http_status(:ok)
      summary = json_response['data']
      
      expect(summary['total_executions']).to eq(3)
      expect(summary['successful_executions']).to eq(1)
      expect(summary['failed_executions']).to eq(1)
      expect(summary['success_rate']).to eq(33.33) # 1/3 completed
    end

    it 'filters analytics by time period' do
      # Create old execution
      old_execution = create(:ai_agent_execution, :completed, 
                           ai_agent: agent, 
                           account: account,
                           created_at: 2.months.ago)
      
      get '/api/v1/ai/providers/usage_summary', params: { 
        provider_id: provider.id,
        period: 30 # Last 30 days only
      }
      
      expect(response).to have_http_status(:ok)
      summary = json_response['data']
      
      # Should not include the old execution
      expect(summary['total_executions']).to eq(3)
    end

    it 'provides system-wide capability listing' do
      get '/api/v1/ai/providers/capabilities'
      
      expect(response).to have_http_status(:ok)
      capabilities = json_response['data']['capabilities']
      
      expect(capabilities).to be_an(Array)
      expect(capabilities).not_to be_empty
    end

    it 'lists all provider types' do
      get '/api/v1/ai/providers/provider_types'
      
      expect(response).to have_http_status(:ok)
      types = json_response['data']['provider_types']
      
      expect(types).to be_an(Array)
      expect(types).not_to be_empty
    end
  end

  describe 'Performance and Scalability' do
    it 'handles large provider lists efficiently' do
      # Create many providers
      create_list(:ai_provider, 50)
      
      start_time = Time.current
      get '/api/v1/ai/providers', params: { per_page: 100 }
      end_time = Time.current
      
      expect(response).to have_http_status(:ok)
      expect(end_time - start_time).to be < 2.seconds # Should be fast
      
      providers = json_response['data']['providers']
      expect(providers.size).to be <= 100 # Respects pagination
    end

    it 'handles concurrent credential creation' do
      provider = create(:ai_provider, slug: 'openai')
      
      # Mock successful tests
      allow_any_instance_of(AiProviderTestService).to receive(:test_with_details)
        .and_return({ success: true })
      
      threads = 3.times.map do |i|
        Thread.new do
          post '/api/v1/ai/provider_credentials', params: {
            credential: {
              ai_provider_id: provider.id,
              name: "Concurrent Credential #{i}",
              credentials: {
                api_key: "sk-test#{i}",
                model: 'gpt-3.5-turbo'
              }
            }
          }
          response.status
        end
      end
      
      results = threads.map(&:value)
      expect(results.all? { |status| status == 200 }).to be true
      
      # Verify all credentials were created
      expect(provider.ai_provider_credentials.count).to eq(3)
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end