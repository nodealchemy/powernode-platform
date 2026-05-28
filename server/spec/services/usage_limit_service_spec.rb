# frozen_string_literal: true

require 'rails_helper'

# Entitlements::UsageLimitService is a CORE service that gates core resources
# (users, API keys, webhooks, workers). Limits are only enforced when billing is
# active (business extension loaded + :business_mode on). In core mode — the state
# of the public/self-hosted release and the default test environment — every limit
# is unlimited and all features are enabled.
#
# This spec covers the core-mode (billing-absent) behavior. The business-mode
# enforcement behavior (subscription/plan-driven limits) is covered in the business
# extension's own suite, where Billing::Subscription / Billing::Plan are loaded.
RSpec.describe Entitlements::UsageLimitService, type: :service do
  let(:account) { create(:account) }

  before do
    # Sanity: these tests assert the billing-absent path.
    expect(Shared::FeatureGateService.billing_enabled?).to be(false)
  end

  describe 'core mode (billing absent) — unlimited' do
    it 'allows adding users regardless of count' do
      create_list(:user, 25, account: account)
      expect(Entitlements::UsageLimitService.can_add_user?(account)).to be true
    end

    it 'allows creating API keys regardless of count' do
      create_list(:api_key, 25, :active, account: account)
      expect(Entitlements::UsageLimitService.can_create_api_key?(account)).to be true
    end

    it 'allows creating webhooks regardless of count' do
      create_list(:webhook_endpoint, 25, :active, account: account)
      expect(Entitlements::UsageLimitService.can_create_webhook?(account)).to be true
    end

    it 'allows creating workers regardless of count' do
      create_list(:worker, 25, account: account)
      expect(Entitlements::UsageLimitService.can_create_worker?(account)).to be true
    end

    it 'never reports limits as reached' do
      create_list(:user, 25, account: account)
      expect(Entitlements::UsageLimitService.has_reached_limits?(account)).to be false
    end

    it 'reports an unlimited ceiling for any limit type' do
      expect(Entitlements::UsageLimitService.get_limit(account, 'max_users')).to eq(9999)
      expect(Entitlements::UsageLimitService.get_limit(account, 'max_api_keys')).to eq(9999)
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

    it 'returns real usage counts (billing-agnostic)' do
      expect(Entitlements::UsageLimitService.current_usage(account, 'max_users')).to eq(4) # 3 + 1 existing
      expect(Entitlements::UsageLimitService.current_usage(account, 'max_api_keys')).to eq(2)
      expect(Entitlements::UsageLimitService.current_usage(account, 'max_webhooks')).to eq(4)
      expect(Entitlements::UsageLimitService.current_usage(account, 'max_workers')).to eq(1)
    end
  end

  describe '.usage_summary in core mode' do
    let!(:user) { create(:user, account: account) }

    before do
      create_list(:user, 2, account: account) # 3 total with existing user
      create_list(:api_key, 1, :active, account: account)
    end

    it 'returns an unlimited summary that still reflects real current counts' do
      summary = Entitlements::UsageLimitService.usage_summary(account)

      expect(summary['max_users'][:current]).to eq(3)
      expect(summary['max_users'][:unlimited]).to be true
      expect(summary['max_users'][:limit]).to eq(9999)
      expect(summary['max_users'][:percentage]).to eq(0)
      expect(summary['max_users'][:available]).to eq(Float::INFINITY)

      expect(summary['max_api_keys'][:current]).to eq(1)
      expect(summary['max_api_keys'][:unlimited]).to be true
    end
  end
end
