# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiProviderManagementService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider) }
  let(:user) { create(:user, account: account) }

  describe '.setup_default_providers' do
    it 'creates default AI providers' do
      expect {
        described_class.setup_default_providers
      }.to change { AiProvider.count }.by_at_least(5)
    end

    it 'creates Ollama as priority provider' do
      described_class.setup_default_providers
      
      ollama = AiProvider.find_by(slug: 'ollama')
      expect(ollama).to be_present
      expect(ollama.priority_order).to eq(1)
      expect(ollama.name).to eq('Ollama')
      expect(ollama.provider_type).to eq('custom')
    end

    it 'creates OpenAI provider' do
      described_class.setup_default_providers
      
      openai = AiProvider.find_by(slug: 'openai')
      expect(openai).to be_present
      expect(openai.name).to eq('OpenAI')
      expect(openai.capabilities).to include('text_generation')
    end

    it 'creates Anthropic provider' do
      described_class.setup_default_providers
      
      anthropic = AiProvider.find_by(slug: 'anthropic')
      expect(anthropic).to be_present
      expect(anthropic.name).to eq('Anthropic')
      expect(anthropic.capabilities).to include('text_generation')
    end

    it 'does not create duplicates on repeated calls' do
      described_class.setup_default_providers
      initial_count = AiProvider.count
      
      described_class.setup_default_providers
      expect(AiProvider.count).to eq(initial_count)
    end

    it 'returns count of created providers' do
      count = described_class.setup_default_providers
      expect(count).to be_a(Integer)
      expect(count).to be >= 0
    end
  end

  describe '.create_provider_credential' do
    let(:credentials_data) do
      {
        api_key: 'test_api_key_123',
        model: 'gpt-3.5-turbo'
      }
    end

    it 'creates and tests provider credential' do
      allow(AiProviderTestService).to receive_service_call(:test_with_details)
        .and_return({ success: true, response_time_ms: 1500 })

      credential = described_class.create_provider_credential(
        provider,
        account,
        credentials_data,
        name: 'Test Credential'
      )

      expect(credential).to be_persisted
      expect(credential.name).to eq('Test Credential')
      expect(credential.account).to eq(account)
      expect(credential.ai_provider).to eq(provider)
      expect(credential).to be_is_active
    end

    it 'encrypts credential data' do
      allow(AiProviderTestService).to receive_service_call(:test_with_details)
        .and_return({ success: true })

      credential = described_class.create_provider_credential(
        provider,
        account,
        credentials_data
      )

      expect(credential.credentials).not_to eq(credentials_data.to_json)
      expect(credential.credentials).to be_a(String)
      expect(credential.credentials.length).to be > 100 # Encrypted data is longer
    end

    it 'sets as default if no other credentials exist' do
      allow(AiProviderTestService).to receive_service_call(:test_with_details)
        .and_return({ success: true })

      credential = described_class.create_provider_credential(
        provider,
        account,
        credentials_data
      )

      expect(credential).to be_is_default
    end

    it 'does not set as default if other credentials exist' do
      create(:ai_provider_credential, account: account, ai_provider: provider, is_default: true)
      
      allow(AiProviderTestService).to receive_service_call(:test_with_details)
        .and_return({ success: true })

      credential = described_class.create_provider_credential(
        provider,
        account,
        credentials_data
      )

      expect(credential).not_to be_is_default
    end

    it 'raises ValidationError for invalid credentials' do
      expect {
        described_class.create_provider_credential(
          provider,
          account,
          {} # Empty credentials
        )
      }.to raise_error(AiProviderManagementService::ValidationError)
    end

    it 'raises CredentialError when test fails' do
      allow(AiProviderTestService).to receive_service_call(:test_with_details)
        .and_return({ success: false, error: 'Invalid API key' })

      expect {
        described_class.create_provider_credential(
          provider,
          account,
          credentials_data
        )
      }.to raise_error(AiProviderManagementService::CredentialError, /Invalid API key/)
    end

    it 'handles provider-specific validation' do
      openai_provider = create(:ai_provider, slug: 'openai')
      invalid_openai_creds = { model: 'gpt-3.5-turbo' } # Missing api_key

      expect {
        described_class.create_provider_credential(
          openai_provider,
          account,
          invalid_openai_creds
        )
      }.to raise_error(AiProviderManagementService::ValidationError, /api_key is required/)
    end
  end

  describe '.validate_provider_credentials' do
    context 'for OpenAI provider' do
      let(:openai_provider) { create(:ai_provider, slug: 'openai') }

      it 'validates required api_key' do
        expect {
          described_class.validate_provider_credentials(
            openai_provider,
            { model: 'gpt-3.5-turbo' }
          )
        }.to raise_error(AiProviderManagementService::ValidationError, /api_key is required/)
      end

      it 'validates api_key format' do
        expect {
          described_class.validate_provider_credentials(
            openai_provider,
            { api_key: 'invalid', model: 'gpt-3.5-turbo' }
          )
        }.to raise_error(AiProviderManagementService::ValidationError, /Invalid API key format/)
      end

      it 'passes validation for valid credentials' do
        expect {
          described_class.validate_provider_credentials(
            openai_provider,
            { api_key: 'sk-1234567890abcdef', model: 'gpt-3.5-turbo' }
          )
        }.not_to raise_error
      end
    end

    context 'for Anthropic provider' do
      let(:anthropic_provider) { create(:ai_provider, slug: 'anthropic') }

      it 'validates required api_key' do
        expect {
          described_class.validate_provider_credentials(
            anthropic_provider,
            { model: 'claude-3-sonnet' }
          )
        }.to raise_error(AiProviderManagementService::ValidationError, /api_key is required/)
      end
    end

    context 'for Ollama provider' do
      let(:ollama_provider) { create(:ai_provider, slug: 'ollama') }

      it 'validates base_url format if provided' do
        expect {
          described_class.validate_provider_credentials(
            ollama_provider,
            { base_url: 'invalid-url', model: 'llama2' }
          )
        }.to raise_error(AiProviderManagementService::ValidationError, /Invalid base URL format/)
      end

      it 'allows valid base_url' do
        expect {
          described_class.validate_provider_credentials(
            ollama_provider,
            { base_url: 'http://localhost:11434', model: 'llama2' }
          )
        }.not_to raise_error
      end

      it 'uses default base_url if not provided' do
        expect {
          described_class.validate_provider_credentials(
            ollama_provider,
            { model: 'llama2' }
          )
        }.not_to raise_error
      end
    end
  end

  describe '.test_all_credentials' do
    let!(:credential1) { create(:ai_provider_credential, account: account, ai_provider: provider) }
    let!(:credential2) { create(:ai_provider_credential, account: account) }
    let!(:other_account_credential) { create(:ai_provider_credential) }

    it 'tests all credentials for the account' do
      allow(AiProviderTestService).to receive(:new).and_return(
        double(test_with_details: { success: true, response_time_ms: 1000 })
      )

      results = described_class.test_all_credentials(account)
      
      expect(results).to be_an(Array)
      expect(results.size).to eq(2)
      expect(results.all? { |r| r.key?(:credential_id) }).to be true
      expect(results.all? { |r| r.key?(:success) }).to be true
    end

    it 'includes credential information in results' do
      allow(AiProviderTestService).to receive(:new).and_return(
        double(test_with_details: { success: true, response_time_ms: 1500 })
      )

      results = described_class.test_all_credentials(account)
      
      first_result = results.first
      expect(first_result).to include(
        :credential_id,
        :credential_name,
        :provider_name,
        :success,
        :response_time_ms
      )
    end

    it 'handles test failures gracefully' do
      allow(AiProviderTestService).to receive(:new).and_return(
        double(test_with_details: { success: false, error: 'Connection timeout' })
      )

      results = described_class.test_all_credentials(account)
      
      expect(results).to be_an(Array)
      expect(results.all? { |r| r[:success] == false }).to be true
      expect(results.all? { |r| r[:error].present? }).to be true
    end

    it 'does not test credentials from other accounts' do
      allow(AiProviderTestService).to receive(:new).and_return(
        double(test_with_details: { success: true })
      )

      results = described_class.test_all_credentials(account)
      credential_ids = results.map { |r| r[:credential_id] }
      
      expect(credential_ids).not_to include(other_account_credential.id)
    end
  end

  describe '.get_available_providers_for_account' do
    let!(:active_provider) { create(:ai_provider, is_active: true) }
    let!(:inactive_provider) { create(:ai_provider, is_active: false) }
    let!(:credential) { create(:ai_provider_credential, account: account, ai_provider: active_provider) }

    it 'returns only active providers' do
      providers = described_class.get_available_providers_for_account(account)
      
      expect(providers).to include(active_provider)
      expect(providers).not_to include(inactive_provider)
    end

    it 'includes provider credential information' do
      providers = described_class.get_available_providers_for_account(account)
      provider_with_creds = providers.find { |p| p.id == active_provider.id }
      
      expect(provider_with_creds).to be_present
    end

    it 'orders providers by priority' do
      high_priority = create(:ai_provider, priority_order: 1)
      low_priority = create(:ai_provider, priority_order: 10)
      
      providers = described_class.get_available_providers_for_account(account)
      
      high_index = providers.index { |p| p.id == high_priority.id }
      low_index = providers.index { |p| p.id == low_priority.id }
      
      expect(high_index).to be < low_index
    end
  end

  describe '.sync_provider_models' do
    it 'updates provider with latest model information' do
      expect(provider.supported_models).to be_empty
      
      result = described_class.sync_provider_models(provider)
      
      expect(result).to be true
      expect(provider.reload.supported_models).not_to be_empty
    end

    it 'handles sync errors gracefully' do
      allow(provider).to receive(:update!).and_raise(StandardError.new('Sync failed'))
      
      result = described_class.sync_provider_models(provider)
      
      expect(result).to be false
    end

    context 'for OpenAI provider' do
      let(:openai_provider) { create(:ai_provider, slug: 'openai') }

      it 'syncs OpenAI models' do
        result = described_class.sync_provider_models(openai_provider)
        
        expect(result).to be true
        expect(openai_provider.reload.supported_models).to include('gpt-3.5-turbo')
        expect(openai_provider.supported_models).to include('gpt-4')
      end
    end
  end

  describe '.provider_usage_summary' do
    let!(:execution1) { create(:ai_agent_execution, :completed, account: account) }
    let!(:execution2) { create(:ai_agent_execution, :failed, account: account) }

    before do
      # Set up executions with same provider
      execution1.ai_agent.update!(ai_provider: provider)
      execution2.ai_agent.update!(ai_provider: provider)
    end

    it 'returns usage summary for provider and account' do
      summary = described_class.provider_usage_summary(
        provider,
        account,
        30.days
      )

      expect(summary).to include(
        :total_executions,
        :successful_executions,
        :failed_executions,
        :total_tokens_used,
        :estimated_cost,
        :avg_response_time,
        :success_rate
      )
    end

    it 'calculates metrics correctly' do
      summary = described_class.provider_usage_summary(
        provider,
        account,
        30.days
      )

      expect(summary[:total_executions]).to eq(2)
      expect(summary[:successful_executions]).to eq(1)
      expect(summary[:failed_executions]).to eq(1)
      expect(summary[:success_rate]).to eq(50.0)
    end

    it 'filters by time period correctly' do
      old_execution = create(:ai_agent_execution, :completed, 
                           account: account, 
                           created_at: 2.months.ago)
      old_execution.ai_agent.update!(ai_provider: provider)

      summary = described_class.provider_usage_summary(
        provider,
        account,
        30.days
      )

      expect(summary[:total_executions]).to eq(2) # Should not include old execution
    end
  end

  describe 'error handling' do
    it 'handles invalid provider gracefully' do
      expect {
        described_class.validate_provider_credentials(nil, {})
      }.to raise_error(AiProviderManagementService::ValidationError)
    end

    it 'handles network errors during credential testing' do
      allow(AiProviderTestService).to receive(:new).and_raise(StandardError.new('Network error'))

      expect {
        described_class.create_provider_credential(
          provider,
          account,
          { api_key: 'test_key' }
        )
      }.to raise_error(AiProviderManagementService::CredentialError, /Network error/)
    end

    it 'handles database errors during credential creation' do
      allow(AiProviderCredential).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        described_class.create_provider_credential(
          provider,
          account,
          { api_key: 'test_key' }
        )
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'private methods' do
    describe 'provider-specific model lists' do
      it 'returns OpenAI models' do
        models = described_class.send(:openai_models)
        expect(models).to be_a(Hash)
        expect(models).to have_key('gpt-3.5-turbo')
        expect(models).to have_key('gpt-4')
      end

      it 'returns Anthropic models' do
        models = described_class.send(:anthropic_models)
        expect(models).to be_a(Hash)
        expect(models).to have_key('claude-3-sonnet-20240229')
      end

      it 'returns Ollama models' do
        models = described_class.send(:ollama_models)
        expect(models).to be_a(Hash)
        expect(models).to have_key('llama2')
      end
    end
  end
end