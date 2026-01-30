# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookEndpoint, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:created_by).class_name('User').optional }
    it { should have_many(:webhook_deliveries).dependent(:destroy) }
    # NOTE: webhook_events FK is not in the webhook_events table; skipping
    # NOTE: WebhookDeliveryStat may not exist; testing only if defined
    if defined?(WebhookDeliveryStat)
      it { should have_many(:delivery_stats).class_name('WebhookDeliveryStat').dependent(:destroy) }
    end
  end

  describe 'validations' do
    it { should validate_presence_of(:url) }
    # NOTE: status and timeout_seconds have defaults set by before_validation callback,
    # which defeats shoulda-matchers validate_presence_of. Test manually instead.
    it 'validates status inclusion' do
      endpoint = build(:webhook_endpoint, status: 'invalid')
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:status]).to be_present
    end

    it { should validate_inclusion_of(:content_type).in_array(%w[application/json application/x-www-form-urlencoded]) }

    it 'requires timeout_seconds to be a positive number' do
      endpoint = build(:webhook_endpoint, timeout_seconds: 0)
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:timeout_seconds]).to be_present
    end

    it { should validate_numericality_of(:retry_limit).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(10) }
    it { should validate_inclusion_of(:retry_backoff).in_array(%w[linear exponential]) }

    context 'url format validation' do
      let(:account) { create(:account) }

      it 'accepts valid HTTP URLs' do
        endpoint = build(:webhook_endpoint, account: account, url: 'http://example.com/webhook')
        expect(endpoint).to be_valid
      end

      it 'accepts valid HTTPS URLs' do
        endpoint = build(:webhook_endpoint, account: account, url: 'https://example.com/webhook')
        expect(endpoint).to be_valid
      end

      it 'rejects invalid URLs' do
        endpoint = build(:webhook_endpoint, account: account, url: 'not-a-url')
        expect(endpoint).not_to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let!(:active_endpoint) { create(:webhook_endpoint, account: account, status: 'active', is_active: true) }
    let!(:inactive_endpoint) { create(:webhook_endpoint, account: account, status: 'inactive', is_active: false) }

    describe '.active' do
      it 'returns only active endpoints' do
        expect(described_class.active).to include(active_endpoint)
        expect(described_class.active).not_to include(inactive_endpoint)
      end
    end

    describe '.inactive' do
      it 'returns only inactive endpoints' do
        expect(described_class.inactive).to include(inactive_endpoint)
        expect(described_class.inactive).not_to include(active_endpoint)
      end
    end

    describe '.for_event_type' do
      let!(:specific_endpoint) { create(:webhook_endpoint, account: account, event_types: ['user.created', 'payment.completed']) }
      let!(:other_endpoint) { create(:webhook_endpoint, account: account, event_types: ['subscription.updated']) }

      it 'returns endpoints with matching specific event types' do
        results = described_class.for_event_type('user.created')
        expect(results).to include(specific_endpoint)
      end

      it 'excludes endpoints without matching event types' do
        results = described_class.for_event_type('user.created')
        expect(results).not_to include(other_endpoint)
      end
    end
  end

  describe 'instance methods' do
    let(:account) { create(:account) }
    let(:endpoint) { create(:webhook_endpoint, account: account, status: 'active', is_active: true) }

    describe '#active?' do
      it 'returns true when status is active and is_active is true' do
        endpoint.status = 'active'
        endpoint.is_active = true
        expect(endpoint.active?).to be true
      end

      it 'returns false when status is inactive' do
        endpoint.status = 'inactive'
        expect(endpoint.active?).to be false
      end

      it 'returns false when is_active is false' do
        endpoint.status = 'active'
        endpoint.is_active = false
        expect(endpoint.active?).to be false
      end
    end

    describe '#inactive?' do
      it 'returns true when not active' do
        endpoint.status = 'inactive'
        expect(endpoint.inactive?).to be true
      end

      it 'returns false when active' do
        endpoint.status = 'active'
        endpoint.is_active = true
        expect(endpoint.inactive?).to be false
      end
    end

    describe '#success_rate' do
      it 'returns 100.0 when no deliveries exist' do
        expect(endpoint.success_rate).to eq(100.0)
      end

      it 'calculates success rate from counter columns' do
        endpoint.update_columns(success_count: 7, failure_count: 3)
        expect(endpoint.success_rate).to eq(70.0)
      end

      it 'returns 100.0 when all deliveries successful' do
        endpoint.update_columns(success_count: 5, failure_count: 0)
        expect(endpoint.success_rate).to eq(100.0)
      end
    end

    describe '#failure_rate' do
      it 'returns 0.0 when no deliveries exist' do
        expect(endpoint.failure_rate).to eq(0.0)
      end

      it 'calculates failure rate from counter columns' do
        endpoint.update_columns(success_count: 3, failure_count: 7)
        expect(endpoint.failure_rate).to eq(70.0)
      end
    end

    describe '#total_deliveries' do
      it 'returns 0 when no deliveries exist' do
        expect(endpoint.total_deliveries).to eq(0)
      end

      it 'returns sum of success and failure counts' do
        endpoint.update_columns(success_count: 5, failure_count: 3)
        expect(endpoint.total_deliveries).to eq(8)
      end
    end

    describe '#health_status' do
      it 'returns unknown when no deliveries exist' do
        expect(endpoint.health_status).to eq('unknown')
      end

      it 'returns excellent when success rate is >= 95%' do
        endpoint.update_columns(success_count: 96, failure_count: 4)
        expect(endpoint.health_status).to eq('excellent')
      end

      it 'returns good when success rate is >= 85% and < 95%' do
        endpoint.update_columns(success_count: 90, failure_count: 10)
        expect(endpoint.health_status).to eq('good')
      end

      it 'returns warning when success rate is >= 70% and < 85%' do
        endpoint.update_columns(success_count: 75, failure_count: 25)
        expect(endpoint.health_status).to eq('warning')
      end

      it 'returns critical when success rate is below 70%' do
        endpoint.update_columns(success_count: 50, failure_count: 50)
        expect(endpoint.health_status).to eq('critical')
      end
    end

    describe '#can_receive_event?' do
      it 'returns false when endpoint is inactive' do
        endpoint.status = 'inactive'
        expect(endpoint.can_receive_event?('user.created')).to be false
      end

      it 'returns true when endpoint has wildcard event type' do
        endpoint.event_types = ['*']
        expect(endpoint.can_receive_event?('user.created')).to be true
      end

      it 'returns true when event type matches' do
        endpoint.event_types = ['user.created', 'payment.completed']
        expect(endpoint.can_receive_event?('user.created')).to be true
      end

      it 'returns false when event type does not match' do
        endpoint.event_types = ['payment.completed']
        expect(endpoint.can_receive_event?('user.created')).to be false
      end

      it 'returns true when event_types is blank (receives all)' do
        endpoint.event_types = []
        expect(endpoint.can_receive_event?('user.created')).to be true
      end
    end

    describe '#next_retry_delay' do
      it 'returns linear delay when retry_backoff is linear' do
        endpoint.retry_backoff = 'linear'
        # base_delay = 5, linear = 5 * attempt_number
        expect(endpoint.next_retry_delay(1)).to eq(5)
        expect(endpoint.next_retry_delay(2)).to eq(10)
        expect(endpoint.next_retry_delay(3)).to eq(15)
      end

      it 'returns exponential delay when retry_backoff is exponential' do
        endpoint.retry_backoff = 'exponential'
        # base_delay = 5, exponential = 5 * 2^(attempt_number - 1)
        expect(endpoint.next_retry_delay(1)).to eq(5)
        expect(endpoint.next_retry_delay(2)).to eq(10)
        expect(endpoint.next_retry_delay(3)).to eq(20)
        expect(endpoint.next_retry_delay(4)).to eq(40)
      end

      it 'clamps maximum delay to 300 seconds' do
        endpoint.retry_backoff = 'exponential'
        expect(endpoint.next_retry_delay(10)).to eq(300)
      end
    end

    describe '#tier' do
      it 'defaults to free' do
        expect(endpoint.tier).to eq('free')
      end
    end

    describe '#tier_daily_limit' do
      it 'returns 100 for free tier' do
        endpoint[:tier] = 'free'
        expect(endpoint.tier_daily_limit).to eq(100)
      end

      it 'returns 10000 for pro tier' do
        endpoint[:tier] = 'pro'
        expect(endpoint.tier_daily_limit).to eq(10_000)
      end

      it 'returns infinity for enterprise tier' do
        endpoint[:tier] = 'enterprise'
        expect(endpoint.tier_daily_limit).to eq(Float::INFINITY)
      end
    end

    describe '#masked_secret' do
      it 'returns nil when secret_key is blank' do
        endpoint.secret_key = nil
        expect(endpoint.masked_secret).to be_nil
      end

      it 'masks the middle of the secret key' do
        endpoint.secret_key = 'whsec_abcdefghijklmnopqrstuvwxyz1234567890'
        masked = endpoint.masked_secret
        expect(masked).to start_with('whsec_ab')
        expect(masked).to include('*' * 24)
      end
    end
  end

  describe 'class methods' do
    describe '.available_event_types' do
      it 'returns an array of event type strings' do
        result = described_class.available_event_types
        expect(result).to be_an(Array)
        expect(result).to include('user.created', 'payment.completed', 'test.webhook')
      end
    end

    describe '.event_categories' do
      it 'returns a hash of category names to event type arrays' do
        result = described_class.event_categories
        expect(result).to be_a(Hash)
        expect(result.keys).to include('User Management', 'Account Management', 'Billing & Subscriptions')
      end
    end

    describe '.content_type_options' do
      it 'returns content type options' do
        result = described_class.content_type_options
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
      end
    end

    describe '.retry_backoff_options' do
      it 'returns retry backoff options' do
        result = described_class.retry_backoff_options
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
      end
    end
  end

  describe 'callbacks' do
    let(:account) { create(:account) }

    describe 'set_defaults' do
      it 'sets default status to active' do
        endpoint = build(:webhook_endpoint, account: account, status: nil)
        endpoint.valid?
        expect(endpoint.status).to eq('active')
      end

      it 'sets default timeout_seconds to 30' do
        endpoint = build(:webhook_endpoint, account: account, timeout_seconds: nil)
        endpoint.valid?
        expect(endpoint.timeout_seconds).to eq(30)
      end

      it 'sets default event_types to empty array' do
        endpoint = build(:webhook_endpoint, account: account, event_types: nil)
        endpoint.valid?
        expect(endpoint.event_types).to eq([])
      end
    end

    describe 'generate_secret_token' do
      it 'generates a secret_key on create' do
        endpoint = create(:webhook_endpoint, account: account)
        expect(endpoint.secret_key).to be_present
        expect(endpoint.secret_key).to start_with('whsec_')
      end
    end
  end
end
