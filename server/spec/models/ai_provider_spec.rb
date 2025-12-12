# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiProvider, type: :model do
  subject(:provider) { build(:ai_provider) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:credentials).class_name('AiProviderCredential').dependent(:destroy) }
    it { is_expected.to have_many(:ai_agents).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:provider_type) }
    it { is_expected.to validate_presence_of(:api_endpoint) }

    it { is_expected.to validate_inclusion_of(:provider_type).in_array(%w[openai anthropic google azure huggingface custom ollama local api_gateway]) }

    context 'name validation' do
      it 'validates name uniqueness within account' do
        account = create(:account)
        create(:ai_provider, account: account, name: 'OpenAI GPT-4')

        duplicate = build(:ai_provider, account: account, name: 'OpenAI GPT-4')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different accounts' do
        account1 = create(:account)
        account2 = create(:account)

        create(:ai_provider, account: account1, name: 'OpenAI GPT-4')
        duplicate = build(:ai_provider, account: account2, name: 'OpenAI GPT-4')

        expect(duplicate).to be_valid
      end

      it 'validates name length' do
        provider = build(:ai_provider, name: 'a' * 256)
        expect(provider).not_to be_valid
        expect(provider.errors[:name]).to include('is too long (maximum is 255 characters)')
      end
    end

    context 'api_endpoint validation' do
      it 'validates URL format' do
        invalid_urls = [ 'not-a-url', 'ftp://invalid.com', 'http://', '' ]

        invalid_urls.each do |url|
          provider = build(:ai_provider, api_endpoint: url)
          expect(provider).not_to be_valid, "Expected '#{url}' to be invalid"
          expect(provider.errors[:api_endpoint]).to be_present
        end
      end

      it 'accepts valid HTTPS URLs' do
        valid_urls = [
          'https://api.openai.com/v1',
          'https://api.anthropic.com',
          'https://api.google.com/ai/v1',
          'https://custom-api.example.com/v2'
        ]

        valid_urls.each do |url|
          provider = build(:ai_provider, api_endpoint: url)
          expect(provider).to be_valid, "Expected '#{url}' to be valid"
        end
      end

      it 'accepts HTTP URLs for development' do
        provider = build(:ai_provider, api_endpoint: 'http://localhost:8080/api')
        expect(provider).to be_valid
      end
    end

    context 'configuration validation' do
      it 'validates configuration is a hash when present' do
        provider = build(:ai_provider, configuration: 'not a hash')
        expect(provider).not_to be_valid
        expect(provider.errors[:configuration]).to include('must be a hash')
      end

      it 'allows nil configuration' do
        provider = build(:ai_provider, configuration: nil)
        expect(provider).to be_valid
      end

      it 'validates provider-specific configuration' do
        openai_config = {
          models: [ 'gpt-3.5-turbo', 'gpt-4' ],
          default_model: 'gpt-3.5-turbo',
          max_tokens: 4000,
          temperature_range: { min: 0, max: 2 }
        }

        provider = build(:ai_provider, provider_type: 'openai', configuration: openai_config)
        expect(provider).to be_valid
      end

      it 'rejects invalid configuration structure' do
        invalid_config = {
          models: 'not_an_array',
          max_tokens: 'not_a_number'
        }

        provider = build(:ai_provider, provider_type: 'openai', configuration: invalid_config)
        expect(provider).not_to be_valid
        expect(provider.errors[:configuration]).to be_present
      end
    end

    context 'rate_limit validation' do
      it 'validates rate_limit structure when present' do
        invalid_rate_limit = {
          requests_per_minute: 'not_a_number',
          requests_per_day: -1
        }

        provider = build(:ai_provider, rate_limit: invalid_rate_limit)
        expect(provider).not_to be_valid
        expect(provider.errors[:rate_limit]).to include('requests_per_minute must be a positive integer')
      end

      it 'accepts valid rate limit configuration' do
        valid_rate_limit = {
          requests_per_minute: 60,
          requests_per_hour: 3000,
          requests_per_day: 50000,
          tokens_per_minute: 150000
        }

        provider = build(:ai_provider, rate_limit: valid_rate_limit)
        expect(provider).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:active_provider) { create(:ai_provider, is_active: true) }
    let!(:inactive_provider) { create(:ai_provider, is_active: false) }
    let!(:openai_provider) { create(:ai_provider, provider_type: 'openai') }
    let!(:anthropic_provider) { create(:ai_provider, provider_type: 'anthropic') }
    let!(:default_provider) { create(:ai_provider, is_default: true) }

    describe '.active' do
      it 'returns only active providers' do
        expect(described_class.active).to include(active_provider)
        expect(described_class.active).not_to include(inactive_provider)
      end
    end

    describe '.by_type' do
      it 'filters providers by type' do
        expect(described_class.by_type('openai')).to include(openai_provider)
        expect(described_class.by_type('openai')).not_to include(anthropic_provider)
      end
    end

    describe '.default' do
      it 'returns default providers' do
        expect(described_class.default).to include(default_provider)
        expect(described_class.default.count).to eq(1)
      end
    end

    describe '.for_account' do
      let(:account1) { create(:account) }
      let(:account2) { create(:account) }
      let!(:provider1) { create(:ai_provider, account: account1) }
      let!(:provider2) { create(:ai_provider, account: account2) }

      it 'filters providers by account' do
        expect(described_class.for_account(account1)).to include(provider1)
        expect(described_class.for_account(account1)).not_to include(provider2)
      end
    end

    describe '.with_healthy_status' do
      let!(:healthy_provider) { create(:ai_provider, last_health_check: 30.minutes.ago, health_status: 'healthy') }
      let!(:unhealthy_provider) { create(:ai_provider, last_health_check: 30.minutes.ago, health_status: 'unhealthy') }

      it 'returns providers with healthy status' do
        expect(described_class.with_healthy_status).to include(healthy_provider)
        expect(described_class.with_healthy_status).not_to include(unhealthy_provider)
      end
    end
  end

  describe 'callbacks and lifecycle' do
    describe 'before_validation' do
      it 'normalizes provider_type' do
        provider = build(:ai_provider, provider_type: '  OPENAI  ')
        provider.valid?
        expect(provider.provider_type).to eq('openai')
      end

      it 'strips whitespace from api_endpoint' do
        provider = build(:ai_provider, api_endpoint: '  https://api.openai.com/v1  ')
        provider.valid?
        expect(provider.api_endpoint).to eq('https://api.openai.com/v1')
      end

      it 'sets default configuration based on provider type' do
        provider = build(:ai_provider, provider_type: 'openai', configuration: nil)
        provider.valid?

        expect(provider.configuration['models']).to include('gpt-3.5-turbo')
        expect(provider.configuration['default_model']).to be_present
      end
    end

    describe 'after_create' do
      it 'performs initial health check' do
        expect_any_instance_of(described_class).to receive(:perform_health_check)
        create(:ai_provider)
      end

      it 'sets up default credentials for known providers' do
        expect_any_instance_of(described_class).to receive(:setup_default_credentials)
        create(:ai_provider, provider_type: 'openai')
      end
    end

    describe 'after_update' do
      it 'invalidates cache when configuration changes' do
        provider = create(:ai_provider)

        expect(provider).to receive(:invalidate_provider_cache)
        provider.update!(configuration: { updated: true })
      end

      it 'triggers health check when endpoint changes' do
        provider = create(:ai_provider)

        expect(provider).to receive(:perform_health_check)
        provider.update!(api_endpoint: 'https://new-endpoint.com/api')
      end
    end
  end

  describe 'instance methods' do
    describe '#healthy?' do
      it 'returns true for providers with recent healthy status' do
        provider = create(:ai_provider,
                         health_status: 'healthy',
                         last_health_check: 30.minutes.ago)
        expect(provider.healthy?).to be true
      end

      it 'returns false for providers with unhealthy status' do
        provider = create(:ai_provider,
                         health_status: 'unhealthy',
                         last_health_check: 30.minutes.ago)
        expect(provider.healthy?).to be false
      end

      it 'returns false for providers with stale health checks' do
        provider = create(:ai_provider,
                         health_status: 'healthy',
                         last_health_check: 2.hours.ago)
        expect(provider.healthy?).to be false
      end

      it 'returns false for providers never checked' do
        provider = create(:ai_provider, last_health_check: nil)
        expect(provider.healthy?).to be false
      end
    end

    describe '#available_models' do
      let(:provider) { create(:ai_provider, provider_type: 'openai') }

      it 'returns configured models' do
        provider.configuration = {
          models: [ 'gpt-3.5-turbo', 'gpt-4', 'gpt-4-turbo' ],
          model_capabilities: {
            'gpt-4' => { max_tokens: 8000, supports_functions: true }
          }
        }

        models = provider.available_models
        expect(models).to include('gpt-3.5-turbo', 'gpt-4', 'gpt-4-turbo')
      end

      it 'fetches models from API when not configured' do
        provider.configuration = {}

        # Mock API response
        allow(provider).to receive(:fetch_models_from_api)
          .and_return([ 'gpt-3.5-turbo', 'gpt-4' ])

        models = provider.available_models
        expect(models).to include('gpt-3.5-turbo', 'gpt-4')
      end
    end

    describe '#default_model' do
      it 'returns configured default model' do
        provider = create(:ai_provider,
                         configuration: { default_model: 'gpt-4' })
        expect(provider.default_model).to eq('gpt-4')
      end

      it 'returns first available model when no default configured' do
        provider = create(:ai_provider,
                         configuration: { models: [ 'gpt-3.5-turbo', 'gpt-4' ] })
        expect(provider.default_model).to eq('gpt-3.5-turbo')
      end
    end

    describe '#supports_model?' do
      let(:provider) { create(:ai_provider,
                             configuration: { models: [ 'gpt-3.5-turbo', 'gpt-4' ] }) }

      it 'returns true for supported models' do
        expect(provider.supports_model?('gpt-4')).to be true
      end

      it 'returns false for unsupported models' do
        expect(provider.supports_model?('claude-3')).to be false
      end

      it 'handles case variations' do
        expect(provider.supports_model?('GPT-4')).to be true
      end
    end

    describe '#model_capabilities' do
      let(:provider) { create(:ai_provider, provider_type: 'openai') }

      before do
        provider.configuration = {
          model_capabilities: {
            'gpt-3.5-turbo' => {
              max_tokens: 4000,
              supports_functions: true,
              supports_vision: false,
              cost_per_1k_tokens: { input: 0.001, output: 0.002 }
            },
            'gpt-4' => {
              max_tokens: 8000,
              supports_functions: true,
              supports_vision: true,
              cost_per_1k_tokens: { input: 0.03, output: 0.06 }
            }
          }
        }
      end

      it 'returns capabilities for specific model' do
        capabilities = provider.model_capabilities('gpt-4')

        expect(capabilities[:max_tokens]).to eq(8000)
        expect(capabilities[:supports_vision]).to be true
        expect(capabilities[:cost_per_1k_tokens][:input]).to eq(0.03)
      end

      it 'returns nil for unsupported models' do
        expect(provider.model_capabilities('unsupported-model')).to be_nil
      end
    end

    describe '#estimate_cost' do
      let(:provider) { create(:ai_provider, provider_type: 'openai') }

      before do
        provider.configuration = {
          model_capabilities: {
            'gpt-4' => {
              cost_per_1k_tokens: { input: 0.03, output: 0.06 }
            }
          }
        }
      end

      it 'calculates cost for token usage' do
        cost = provider.estimate_cost('gpt-4', input_tokens: 1000, output_tokens: 500)
        expect(cost).to eq(0.06) # (1000 * 0.03 / 1000) + (500 * 0.06 / 1000)
      end

      it 'returns 0 for models without cost data' do
        cost = provider.estimate_cost('unknown-model', input_tokens: 1000, output_tokens: 500)
        expect(cost).to eq(0)
      end
    end

    describe '#rate_limit_remaining' do
      let(:provider) { create(:ai_provider,
                             rate_limit: { requests_per_minute: 60 },
                             request_count_last_minute: 45) }

      it 'calculates remaining requests based on rate limit' do
        expect(provider.rate_limit_remaining(:requests_per_minute)).to eq(15)
      end

      it 'returns nil when no rate limit configured' do
        provider.rate_limit = {}
        expect(provider.rate_limit_remaining(:requests_per_minute)).to be_nil
      end
    end

    describe '#can_make_request?' do
      let(:provider) { create(:ai_provider,
                             rate_limit: { requests_per_minute: 60 },
                             request_count_last_minute: 55) }

      it 'returns true when under rate limit' do
        expect(provider.can_make_request?).to be true
      end

      it 'returns false when at rate limit' do
        provider.request_count_last_minute = 60
        expect(provider.can_make_request?).to be false
      end

      it 'returns true when no rate limit configured' do
        provider.rate_limit = {}
        expect(provider.can_make_request?).to be true
      end
    end

    describe '#perform_health_check' do
      let(:provider) { create(:ai_provider) }

      it 'updates health status on successful check' do
        # Mock successful API response
        allow(provider).to receive(:test_api_connection).and_return(true)

        provider.perform_health_check

        expect(provider.health_status).to eq('healthy')
        expect(provider.last_health_check).to be_within(1.second).of(Time.current)
      end

      it 'updates health status on failed check' do
        # Mock failed API response
        allow(provider).to receive(:test_api_connection).and_raise(StandardError, 'Connection failed')

        provider.perform_health_check

        expect(provider.health_status).to eq('unhealthy')
        expect(provider.health_error).to include('Connection failed')
      end

      it 'records detailed health metrics' do
        allow(provider).to receive(:test_api_connection).and_return(true)

        provider.perform_health_check

        expect(provider.health_metrics).to include('response_time_ms')
        expect(provider.health_metrics).to include('last_check_timestamp')
      end
    end

    describe '#increment_usage' do
      let(:provider) { create(:ai_provider) }

      it 'increments usage counters' do
        expect {
          provider.increment_usage(requests: 1, tokens: 150)
        }.to change { provider.reload.total_requests }.by(1)
         .and change { provider.reload.total_tokens }.by(150)
      end

      it 'updates rate limit counters' do
        provider.increment_usage(requests: 1)

        expect(provider.request_count_last_minute).to eq(1)
        expect(provider.request_count_last_hour).to eq(1)
      end
    end

    describe '#usage_statistics' do
      let(:provider) { create(:ai_provider,
                             total_requests: 1000,
                             total_tokens: 50000,
                             total_cost: 25.50) }

      it 'returns comprehensive usage statistics' do
        stats = provider.usage_statistics

        expect(stats[:total_requests]).to eq(1000)
        expect(stats[:total_tokens]).to eq(50000)
        expect(stats[:total_cost]).to eq(25.50)
        expect(stats[:average_tokens_per_request]).to eq(50.0)
        expect(stats[:average_cost_per_request]).to eq(0.0255)
      end

      it 'includes time-based statistics' do
        stats = provider.usage_statistics(include_trends: true)

        expect(stats[:requests_today]).to be_present
        expect(stats[:requests_this_week]).to be_present
        expect(stats[:cost_trend]).to be_present
      end
    end

    describe '#provider_summary' do
      let(:provider) { create(:ai_provider, provider_type: 'openai') }

      it 'returns comprehensive provider information' do
        summary = provider.provider_summary

        expect(summary).to include(
          :id,
          :name,
          :provider_type,
          :is_active,
          :is_default,
          :health_status,
          :available_models,
          :usage_statistics
        )

        expect(summary[:provider_type]).to eq('openai')
        expect(summary[:available_models]).to be_an(Array)
      end
    end
  end

  describe 'class methods' do
    describe '.default_for_account' do
      let(:account) { create(:account) }

      it 'returns default provider for account' do
        default = create(:ai_provider, account: account, is_default: true)
        create(:ai_provider, account: account, is_default: false)

        expect(described_class.default_for_account(account)).to eq(default)
      end

      it 'returns nil when no default provider exists' do
        create(:ai_provider, account: account, is_default: false)
        expect(described_class.default_for_account(account)).to be_nil
      end
    end

    describe '.available_provider_types' do
      it 'returns list of supported provider types' do
        types = described_class.available_provider_types
        expect(types).to include('openai', 'anthropic', 'google', 'azure')
      end

      it 'includes type metadata' do
        types = described_class.available_provider_types(include_metadata: true)
        openai_meta = types.find { |t| t[:type] == 'openai' }

        expect(openai_meta[:name]).to eq('OpenAI')
        expect(openai_meta[:description]).to be_present
        expect(openai_meta[:website]).to be_present
      end
    end

    describe '.health_check_all' do
      let!(:providers) { create_list(:ai_provider, 3) }

      it 'performs health checks on all active providers' do
        # Use a simple spy approach to verify the method is called
        call_count = 0
        allow_any_instance_of(described_class).to receive(:perform_health_check) do
          call_count += 1
          true
        end

        result = described_class.health_check_all
        expect(result[:total_checked]).to eq(3)
        expect(call_count).to eq(3)
      end

      it 'returns health check summary' do
        allow_any_instance_of(described_class).to receive(:perform_health_check)

        summary = described_class.health_check_all
        expect(summary[:total_checked]).to eq(3)
        expect(summary[:healthy_count]).to be >= 0
        expect(summary[:unhealthy_count]).to be >= 0
      end
    end

    describe '.usage_analytics' do
      before do
        create(:ai_provider, total_requests: 1000, total_tokens: 50000)
        create(:ai_provider, total_requests: 500, total_tokens: 25000)
      end

      it 'aggregates usage across all providers' do
        analytics = described_class.usage_analytics

        expect(analytics[:total_requests]).to eq(1500)
        expect(analytics[:total_tokens]).to eq(75000)
        expect(analytics[:average_requests_per_provider]).to eq(750.0)
      end

      it 'includes provider distribution analysis' do
        analytics = described_class.usage_analytics(include_distribution: true)

        expect(analytics[:provider_distribution]).to be_present
        expect(analytics[:top_providers]).to be_present
      end
    end

    describe '.setup_default_providers' do
      let(:account) { create(:account) }

      it 'creates default providers for new accounts' do
        expect {
          described_class.setup_default_providers(account)
        }.to change { account.ai_providers.count }.by_at_least(1)

        expect(account.ai_providers.default.count).to eq(1)
      end

      it 'configures providers with appropriate defaults' do
        described_class.setup_default_providers(account)

        openai_provider = account.ai_providers.find_by(provider_type: 'openai')
        expect(openai_provider.configuration['models']).to be_present
        expect(openai_provider.rate_limit).to be_present
      end
    end

    describe '.cleanup_inactive_providers' do
      before do
        create_list(:ai_provider, 3, is_active: false, updated_at: 2.months.ago)
        create_list(:ai_provider, 2, is_active: true, updated_at: 2.months.ago)
      end

      it 'removes old inactive providers' do
        expect {
          described_class.cleanup_inactive_providers(30.days)
        }.to change { described_class.count }.by(-3)

        # Should preserve active providers
        expect(described_class.active.count).to eq(2)
      end

      it 'preserves providers with recent activity' do
        recent_inactive = create(:ai_provider, is_active: false, updated_at: 1.day.ago)

        described_class.cleanup_inactive_providers(30.days)
        expect(described_class.exists?(recent_inactive.id)).to be true
      end
    end
  end

  describe 'performance and edge cases' do
    describe 'concurrent request handling' do
      it 'handles sequential usage updates safely' do
        provider = create(:ai_provider)

        # Sequential updates work correctly
        10.times do
          provider.reload.increment_usage(requests: 1, tokens: 100)
        end

        expect(provider.reload.total_requests).to eq(10)
        expect(provider.total_tokens).to eq(1000)
      end
    end

    describe 'large configuration handling' do
      it 'handles complex provider configurations efficiently' do
        large_config = {
          models: Array.new(100) { |i| "model-#{i}" },
          model_capabilities: Hash[50.times.map { |i|
            [ "model-#{i}", {
              max_tokens: 4000 + i * 100,
              cost_per_1k_tokens: { input: 0.001 + i * 0.0001, output: 0.002 + i * 0.0002 }
            } ]
          }],
          custom_endpoints: Hash[20.times.map { |i| [ "endpoint_#{i}", "https://api-#{i}.example.com" ] }]
        }

        provider = build(:ai_provider, configuration: large_config)
        expect(provider).to be_valid
        expect(provider.save!).to be true
        expect(provider.available_models.count).to eq(100)
      end
    end

    describe 'unicode and special character handling' do
      it 'handles unicode in provider data' do
        unicode_provider = create(:ai_provider,
                                 name: 'AI Provider 智能提供商 🤖',
                                 description: 'Provider with émojis and 中文字符',
                                 configuration: {
                                   models: [ 'gpt-4-中文', 'claude-français' ],
                                   display_names: {
                                     'gpt-4-中文' => 'GPT-4 中文版本',
                                     'claude-français' => 'Claude en Français 🇫🇷'
                                   }
                                 })

        expect(unicode_provider).to be_valid
        expect(unicode_provider.name).to include('🤖')
        expect(unicode_provider.reload.configuration[:display_names]['claude-français']).to include('🇫🇷')
      end
    end

    describe 'query performance with large datasets' do
      before do
        create_list(:ai_provider, 100, :active)
        create_list(:ai_provider, 50, is_active: false)
      end

      it 'efficiently queries provider statistics' do
        # Verify that analytics and health check methods work with large datasets
        expect { described_class.usage_analytics }.not_to raise_error
        expect { described_class.health_check_all }.not_to raise_error
      end

      it 'efficiently filters and orders large result sets' do
        # Verify query executes successfully with includes and filters
        result = described_class.active
                               .includes(:credentials)
                               .order(:name)
                               .limit(20)
                               .to_a
        expect(result.length).to be <= 20
      end
    end

    describe 'error handling and recovery' do
      it 'handles API failures gracefully during health checks' do
        provider = create(:ai_provider)

        # Simulate network timeout using Timeout::Error (Ruby 3 compatible)
        allow(provider).to receive(:test_api_connection).and_raise(Timeout::Error.new('connection timed out'))

        expect { provider.perform_health_check }.not_to raise_error
        expect(provider.health_status).to eq('unhealthy')
      end

      it 'handles missing configuration gracefully' do
        provider = create(:ai_provider)
        # Clear the configuration virtual attribute
        provider.configuration = nil

        expect { provider.available_models }.not_to raise_error
        # Returns models from supported_models when configuration is nil
        expect(provider.available_models).to be_an(Array)
      end
    end

    describe 'rate limiting edge cases' do
      it 'allows requests when under rate limit' do
        provider = create(:ai_provider,
                         rate_limits: { 'requests_per_minute' => 60 })

        # When request count is below limit, should allow
        expect(provider.can_make_request?).to be true
      end

      it 'blocks requests when rate limit is reached' do
        provider = create(:ai_provider,
                         rate_limits: { 'requests_per_minute' => 60 })

        # Manually set the count to be at the limit via metadata
        provider.request_count_last_minute = 60
        provider.save!

        expect(provider.reload.can_make_request?).to be false
      end
    end
  end
end
