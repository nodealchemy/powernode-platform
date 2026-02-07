# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ProviderManagementService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe '.setup_default_providers' do
    it 'creates default AI providers' do
      expect {
        described_class.setup_default_providers
      }.to change { Ai::Provider.count }.by_at_least(1)
    end

    it 'creates Ollama as priority provider' do
      described_class.setup_default_providers

      ollama = Ai::Provider.find_by(slug: 'ollama')
      expect(ollama).to be_present
      expect(ollama.priority_order).to eq(1)
      expect(ollama.name).to eq('Ollama')
    end

    it 'creates OpenAI provider' do
      described_class.setup_default_providers

      openai = Ai::Provider.find_by(slug: 'openai')
      expect(openai).to be_present
      expect(openai.name).to eq('OpenAI')
      expect(openai.capabilities).to include('text_generation')
    end

    it 'creates Anthropic provider' do
      described_class.setup_default_providers

      anthropic = Ai::Provider.find_by(slug: 'anthropic')
      expect(anthropic).to be_present
      expect(anthropic.name).to eq('Anthropic')
      expect(anthropic.capabilities).to include('text_generation')
    end

    it 'does not create duplicates on repeated calls' do
      described_class.setup_default_providers
      initial_count = Ai::Provider.count

      described_class.setup_default_providers
      expect(Ai::Provider.count).to eq(initial_count)
    end

    it 'returns count of created providers' do
      count = described_class.setup_default_providers
      expect(count).to be_a(Integer)
      expect(count).to be >= 0
    end
  end

  describe '.create_provider_credential' do
    let(:openai_provider) { create(:ai_provider, :openai) }
    let(:credentials_data) do
      {
        api_key: 'sk-test1234567890abcdef',
        model: 'gpt-3.5-turbo'
      }
    end

    it 'creates provider credential' do
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details)
        .and_return({ success: true, response_time_ms: 1500 })

      credential = described_class.create_provider_credential(
        openai_provider,
        account,
        credentials_data,
        name: 'Test Credential'
      )

      expect(credential).to be_persisted
      expect(credential.name).to eq('Test Credential')
      expect(credential.account).to eq(account)
      expect(credential.provider).to eq(openai_provider)
      expect(credential).to be_is_active
    end

    it 'stores encrypted credentials' do
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details)
        .and_return({ success: true })

      credential = described_class.create_provider_credential(
        openai_provider,
        account,
        credentials_data
      )

      # Credentials should be accessible through the model
      expect(credential.credentials).to be_present
    end

    it 'tests credential after creation' do
      test_service = instance_double(Ai::ProviderTestService)
      allow(Ai::ProviderTestService).to receive(:new).and_return(test_service)
      # Service now uses test_with_details_simple for flat response format
      allow(test_service).to receive(:test_with_details_simple).and_return({ success: true })

      described_class.create_provider_credential(
        openai_provider,
        account,
        credentials_data
      )

      expect(test_service).to have_received(:test_with_details_simple)
    end

    it 'raises ValidationError for empty credentials' do
      expect {
        described_class.create_provider_credential(
          openai_provider,
          account,
          {}
        )
      }.to raise_error(Ai::ProviderManagementService::ValidationError)
    end

    it 'raises ValidationError for nil credentials' do
      expect {
        described_class.create_provider_credential(
          openai_provider,
          account,
          nil
        )
      }.to raise_error(Ai::ProviderManagementService::ValidationError)
    end
  end

  describe '.validate_ai_provider_credentials' do
    context 'for OpenAI provider' do
      let(:openai_provider) { create(:ai_provider, :openai) }

      it 'validates api_key is required' do
        expect {
          described_class.validate_ai_provider_credentials(
            openai_provider,
            { model: 'gpt-3.5-turbo' }
          )
        }.to raise_error(Ai::ProviderManagementService::ValidationError, /API key is required/)
      end

      it 'validates api_key format must start with sk-' do
        expect {
          described_class.validate_ai_provider_credentials(
            openai_provider,
            { api_key: 'invalid', model: 'gpt-3.5-turbo' }
          )
        }.to raise_error(Ai::ProviderManagementService::ValidationError, /sk-/)
      end

      it 'passes validation for valid credentials' do
        expect {
          described_class.validate_ai_provider_credentials(
            openai_provider,
            { api_key: 'sk-1234567890abcdefghijklmnop', model: 'gpt-3.5-turbo' }
          )
        }.not_to raise_error
      end
    end

    context 'for Anthropic provider' do
      let(:anthropic_provider) { create(:ai_provider, :anthropic) }

      it 'validates api_key is required' do
        expect {
          described_class.validate_ai_provider_credentials(
            anthropic_provider,
            { model: 'claude-3-sonnet' }
          )
        }.to raise_error(Ai::ProviderManagementService::ValidationError, /API key is required/)
      end

      it 'passes validation for valid Anthropic credentials' do
        expect {
          described_class.validate_ai_provider_credentials(
            anthropic_provider,
            { api_key: 'sk-ant-api-test1234567890', model: 'claude-3-sonnet' }
          )
        }.not_to raise_error
      end
    end

    context 'for Ollama provider' do
      let(:ollama_provider) { create(:ai_provider, :ollama) }

      it 'allows credentials without api_key' do
        # Ollama is provider_type 'ollama', no api_key validation
        expect {
          described_class.validate_ai_provider_credentials(
            ollama_provider,
            { base_url: 'http://localhost:11434', model: 'llama2' }
          )
        }.not_to raise_error
      end
    end
  end

  describe '.test_all_credentials' do
    let(:provider) { create(:ai_provider) }
    let!(:credential1) { create(:ai_provider_credential, account: account, provider: provider) }
    let!(:credential2) { create(:ai_provider_credential, account: account) }
    let!(:other_account_credential) { create(:ai_provider_credential) }

    it 'tests all credentials for the account' do
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details)
        .and_return({ success: true, response_time_ms: 1000 })

      results = described_class.test_all_credentials(account)

      expect(results).to be_an(Array)
      expect(results.size).to eq(2)
      expect(results.all? { |r| r.key?(:credential_id) }).to be true
      expect(results.all? { |r| r.key?(:success) }).to be true
    end

    it 'includes credential information in results' do
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details)
        .and_return({ success: true, response_time_ms: 1500 })

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
      # Service now uses test_with_details_simple for flat response format
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details_simple)
        .and_return({ success: false, error: 'Connection timeout' })

      results = described_class.test_all_credentials(account)

      expect(results).to be_an(Array)
      expect(results.all? { |r| r[:success] == false }).to be true
      expect(results.all? { |r| r[:error].present? }).to be true
    end

    it 'does not test credentials from other accounts' do
      # Service now uses test_with_details_simple for flat response format
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details_simple)
        .and_return({ success: true })

      results = described_class.test_all_credentials(account)
      credential_ids = results.map { |r| r[:credential_id] }

      expect(credential_ids).not_to include(other_account_credential.id)
    end
  end

  describe '.get_available_providers_for_account' do
    let!(:active_provider) { create(:ai_provider, is_active: true) }
    let!(:inactive_provider) { create(:ai_provider, is_active: false) }
    let!(:credential) { create(:ai_provider_credential, account: account, provider: active_provider) }

    it 'returns only active providers' do
      providers = described_class.get_available_providers_for_account(account)

      expect(providers).to include(active_provider)
      expect(providers).not_to include(inactive_provider)
    end

    it 'includes providers with credentials' do
      providers = described_class.get_available_providers_for_account(account)
      provider_with_creds = providers.find { |p| p.id == active_provider.id }

      expect(provider_with_creds).to be_present
    end
  end

  describe '.sync_provider_models' do
    let(:provider) { create(:ai_provider) }

    it 'updates provider with model information' do
      result = described_class.sync_provider_models(provider)

      expect(result).to be true
      provider.reload
      expect(provider.supported_models).to be_present
    end

    it 'returns false for inactive provider' do
      inactive_provider = create(:ai_provider, is_active: false)

      result = described_class.sync_provider_models(inactive_provider)

      expect(result).to be false
    end

    context 'for OpenAI provider' do
      let(:openai_provider) { create(:ai_provider, :openai) }

      it 'syncs OpenAI models' do
        result = described_class.sync_provider_models(openai_provider)

        expect(result).to be true
        openai_provider.reload
        model_ids = openai_provider.supported_models.map { |m| m['id'] }
        # Updated to current OpenAI model names
        expect(model_ids).to include('gpt-4o')
        expect(model_ids).to include('gpt-4-turbo')
      end
    end

    context 'for Anthropic provider' do
      let(:anthropic_provider) { create(:ai_provider, :anthropic) }

      it 'syncs Anthropic models' do
        result = described_class.sync_provider_models(anthropic_provider)

        expect(result).to be true
        anthropic_provider.reload
        expect(anthropic_provider.supported_models).to be_present
      end
    end
  end

  describe '.provider_usage_summary' do
    let(:provider) { create(:ai_provider, account: account) }
    let(:agent) { create(:ai_agent, account: account, provider: provider) }

    it 'returns usage summary for provider and account' do
      summary = described_class.provider_usage_summary(
        provider,
        account,
        30.days
      )

      expect(summary).to include(
        :provider_id,
        :provider_name,
        :period_start,
        :period_end,
        :total_requests,
        :successful_requests,
        :failed_requests,
        :total_tokens,
        :total_cost,
        :average_response_time_ms,
        :success_rate
      )
    end

    it 'includes daily breakdown' do
      summary = described_class.provider_usage_summary(
        provider,
        account,
        30.days
      )

      expect(summary[:daily_breakdown]).to be_an(Array)
      expect(summary[:daily_breakdown]).not_to be_empty
    end

    it 'returns zero values when no executions exist' do
      summary = described_class.provider_usage_summary(
        provider,
        account,
        7.days
      )

      expect(summary[:total_requests]).to eq(0)
      expect(summary[:successful_requests]).to eq(0)
      expect(summary[:failed_requests]).to eq(0)
      expect(summary[:total_tokens]).to eq(0)
      expect(summary[:success_rate]).to eq(0.0)
    end

    context 'with real execution data' do
      before do
        # Create test executions - ensure agent uses the same provider
        create(:ai_agent_execution, agent: agent, provider: provider, account: account, status: 'completed',
               started_at: 10.minutes.ago, completed_at: 5.minutes.ago, duration_ms: 300000,
               output_data: { 'usage' => { 'prompt_tokens' => 100, 'completion_tokens' => 50 }, 'cost' => 0.01 })
        create(:ai_agent_execution, agent: agent, provider: provider, account: account, status: 'completed',
               started_at: 10.minutes.ago, completed_at: 5.minutes.ago, duration_ms: 300000,
               output_data: { 'usage' => { 'prompt_tokens' => 200, 'completion_tokens' => 100 }, 'cost' => 0.02 })
        create(:ai_agent_execution, agent: agent, provider: provider, account: account, status: 'failed',
               error_message: 'timeout',
               output_data: { 'error' => 'timeout' })
      end

      it 'calculates correct totals from real execution data' do
        summary = described_class.provider_usage_summary(
          provider,
          account,
          30.days
        )

        expect(summary[:total_requests]).to eq(3)
        expect(summary[:successful_requests]).to eq(2)
        expect(summary[:failed_requests]).to eq(1)
        expect(summary[:total_tokens]).to eq(450) # 100+50 + 200+100
        expect(summary[:total_cost]).to eq(0.03)
        expect(summary[:success_rate]).to eq(66.7) # 2/3 * 100
      end
    end
  end

  describe 'error handling' do
    it 'handles invalid provider gracefully' do
      expect {
        described_class.validate_ai_provider_credentials(nil, {})
      }.to raise_error(Ai::ProviderManagementService::ValidationError)
    end

    it 'handles nil credentials data' do
      provider = create(:ai_provider)
      expect {
        described_class.validate_ai_provider_credentials(provider, nil)
      }.to raise_error(Ai::ProviderManagementService::ValidationError)
    end

    it 'handles network errors during credential testing gracefully' do
      openai_provider = create(:ai_provider, :openai)
      allow_any_instance_of(Ai::ProviderTestService).to receive(:test_with_details)
        .and_raise(StandardError.new('Network error'))

      # Credential should still be created, but with failure recorded
      credential = described_class.create_provider_credential(
        openai_provider,
        account,
        { api_key: 'sk-test1234567890abcdefghijklmnop', model: 'gpt-4' }
      )

      expect(credential).to be_persisted
    end
  end
end
