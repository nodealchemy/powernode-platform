# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageLimitService, type: :service do
  let(:account) { create(:account) }
  let(:subscription) { create(:subscription, account: account) }
  let(:plan) { create(:plan, :with_limits) }

  before do
    subscription.update!(plan: plan)
  end

  describe '.can_add_user?' do
    context 'when under user limit' do
      before do
        plan.update!(limits: { 'max_users' => 5 })
        create_list(:user, 2, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.can_add_user?(account)).to be true
      end
    end

    context 'when at user limit' do
      before do
        plan.update!(limits: { 'max_users' => 3 })
        create_list(:user, 3, account: account)
      end

      it 'returns false' do
        expect(UsageLimitService.can_add_user?(account)).to be false
      end
    end

    context 'when over user limit' do
      before do
        plan.update!(limits: { 'max_users' => 2 })
        create_list(:user, 3, account: account)
      end

      it 'returns false' do
        expect(UsageLimitService.can_add_user?(account)).to be false
      end
    end

    context 'when plan has unlimited users' do
      before do
        plan.update!(limits: { 'max_users' => 9999 })
        create_list(:user, 100, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.can_add_user?(account)).to be true
      end
    end

    context 'when account has no subscription' do
      let(:account_without_subscription) { create(:account) }

      it 'returns false' do
        expect(UsageLimitService.can_add_user?(account_without_subscription)).to be false
      end
    end
  end

  describe '.can_create_api_key?' do
    context 'when under API key limit' do
      before do
        plan.update!(limits: { 'max_api_keys' => 5 })
        create_list(:api_key, 2, :active, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.can_create_api_key?(account)).to be true
      end
    end

    context 'when at API key limit' do
      before do
        plan.update!(limits: { 'max_api_keys' => 3 })
        create_list(:api_key, 3, :active, account: account)
      end

      it 'returns false' do
        expect(UsageLimitService.can_create_api_key?(account)).to be false
      end
    end

    context 'when has revoked API keys' do
      before do
        plan.update!(limits: { 'max_api_keys' => 3 })
        create_list(:api_key, 2, :active, account: account)
        create_list(:api_key, 2, :revoked, account: account)
      end

      it 'only counts active API keys' do
        expect(UsageLimitService.can_create_api_key?(account)).to be true
      end
    end

    context 'when plan has unlimited API keys' do
      before do
        plan.update!(limits: { 'max_api_keys' => 999 })
        create_list(:api_key, 50, :active, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.can_create_api_key?(account)).to be true
      end
    end
  end

  describe '.can_create_webhook?' do
    let(:user) { create(:user, account: account) }

    context 'when under webhook limit' do
      before do
        plan.update!(limits: { 'max_webhooks' => 5 })
        create_list(:webhook_endpoint, 2, :active, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.can_create_webhook?(account)).to be true
      end
    end

    context 'when at webhook limit' do
      before do
        plan.update!(limits: { 'max_webhooks' => 3 })
        create_list(:webhook_endpoint, 3, :active, account: account)
      end

      it 'returns false' do
        expect(UsageLimitService.can_create_webhook?(account)).to be false
      end
    end

    context 'when has inactive webhooks' do
      before do
        plan.update!(limits: { 'max_webhooks' => 3 })
        create_list(:webhook_endpoint, 2, :active, account: account)
        create_list(:webhook_endpoint, 2, :inactive, account: account)
      end

      it 'only counts active webhooks' do
        expect(UsageLimitService.can_create_webhook?(account)).to be true
      end
    end

    context 'when plan has unlimited webhooks' do
      before do
        plan.update!(limits: { 'max_webhooks' => 999 })
        create_list(:webhook_endpoint, 50, :active, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.can_create_webhook?(account)).to be true
      end
    end
  end

  describe '.can_create_worker?' do
    context 'when under worker limit' do
      before do
        plan.update!(limits: { 'max_workers' => 5 })
        create_list(:worker, 2, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.can_create_worker?(account)).to be true
      end
    end

    context 'when at worker limit' do
      before do
        plan.update!(limits: { 'max_workers' => 3 })
        create_list(:worker, 3, account: account)
      end

      it 'returns false' do
        expect(UsageLimitService.can_create_worker?(account)).to be false
      end
    end

    context 'when plan has unlimited workers' do
      before do
        plan.update!(limits: { 'max_workers' => 999 })
        create_list(:worker, 50, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.can_create_worker?(account)).to be true
      end
    end
  end

  describe '.current_usage' do
    let!(:user) { create(:user, account: account) }

    before do
      create_list(:user, 3, account: account)
      create_list(:api_key, 2, :active, account: account)
      create_list(:webhook_endpoint, 4, :active, account: account)
      create_list(:worker, 1, account: account)
    end

    it 'returns correct usage counts' do
      expect(UsageLimitService.current_usage(account, 'max_users')).to eq(4) # 3 + 1 existing
      expect(UsageLimitService.current_usage(account, 'max_api_keys')).to eq(2)
      expect(UsageLimitService.current_usage(account, 'max_webhooks')).to eq(4)
      expect(UsageLimitService.current_usage(account, 'max_workers')).to eq(1)
    end
  end

  describe '.usage_summary' do
    let!(:user) { create(:user, account: account) }

    before do
      plan.update!(limits: {
        'max_users' => 10,
        'max_api_keys' => 5,
        'max_webhooks' => 8,
        'max_workers' => 3
      })

      create_list(:user, 2, account: account) # 3 total with existing user
      create_list(:api_key, 1, :active, account: account)
      create_list(:webhook_endpoint, 4, :active, account: account)
      create_list(:worker, 2, account: account)
    end

    it 'returns comprehensive usage summary' do
      summary = UsageLimitService.usage_summary(account)

      expect(summary['max_users'][:current]).to eq(3)
      expect(summary['max_users'][:limit]).to eq(10)
      expect(summary['max_users'][:percentage]).to eq(30.0)
      expect(summary['max_users'][:available]).to eq(7)
      expect(summary['max_users'][:unlimited]).to be false

      expect(summary['max_api_keys'][:current]).to eq(1)
      expect(summary['max_api_keys'][:limit]).to eq(5)
      expect(summary['max_api_keys'][:available]).to eq(4)

      expect(summary['max_webhooks'][:current]).to eq(4)
      expect(summary['max_webhooks'][:percentage]).to eq(50.0)

      expect(summary['max_workers'][:current]).to eq(2)
      expect(summary['max_workers'][:percentage]).to eq(66.7)
    end
  end

  describe '.has_reached_limits?' do
    context 'when no limits are reached' do
      before do
        plan.update!(limits: {
          'max_users' => 10,
          'max_api_keys' => 5,
          'max_webhooks' => 8,
          'max_workers' => 5
        })
        create_list(:user, 2, account: account)
        create_list(:api_key, 1, :active, account: account)
      end

      it 'returns false' do
        expect(UsageLimitService.has_reached_limits?(account)).to be false
      end
    end

    context 'when any limit is reached' do
      before do
        plan.update!(limits: {
          'max_users' => 3,
          'max_api_keys' => 5,
          'max_webhooks' => 8,
          'max_workers' => 5
        })
        create_list(:user, 3, account: account)
        create_list(:api_key, 1, :active, account: account)
      end

      it 'returns true' do
        expect(UsageLimitService.has_reached_limits?(account)).to be true
      end
    end
  end

  describe '.get_limit' do
    before do
      plan.update!(limits: { 'max_users' => 25 })
    end

    it 'returns the specific limit value' do
      expect(UsageLimitService.get_limit(account, 'max_users')).to eq(25)
    end

    it 'returns 0 for missing limit' do
      expect(UsageLimitService.get_limit(account, 'non_existent')).to eq(0)
    end
  end
end
