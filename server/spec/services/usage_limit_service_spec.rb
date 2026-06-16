# frozen_string_literal: true

require 'rails_helper'

# Entitlements::UsageLimitService is a CORE service that gates core resources
# (users, API keys, webhooks, workers). Limits are only enforced when an entitlements
# provider is registered (an extension injects one via
# Powernode::ExtensionRegistry.provider(:entitlements)). In core mode — the public/
# self-hosted release and the default test environment — no provider is registered, so
# every limit is unlimited and all features are enabled.
#
# This spec covers both the core-mode (provider-absent) behavior and the enforcement
# path with a stubbed provider. The real provider-present behavior is also covered in
# the business extension's own suite, where Billing::EntitlementsProvider is loaded.
RSpec.describe Entitlements::UsageLimitService, type: :service do
  let(:account) { create(:account) }

  describe 'core mode (provider absent) — unlimited' do
    before do
      # Sanity: no entitlements provider registered in the default (core) test env.
      expect(Powernode::ExtensionRegistry.provider(:entitlements)).to be_nil
    end

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

  describe 'provider present (entitlements injected)' do
    # Stub the registry lookup so this core-mode spec can exercise the enforcement path
    # without loading the business extension (stub-the-seam load-order pattern).
    let(:plan) do
      double('Plan', limits: { 'max_users' => 3, 'max_api_keys' => 5, 'max_webhooks' => 2, 'max_workers' => 1 })
    end
    let(:provider) { double('EntitlementsProvider', plan_for: plan) }

    before do
      allow(Powernode::ExtensionRegistry).to receive(:provider).and_call_original
      allow(Powernode::ExtensionRegistry).to receive(:provider).with(:entitlements).and_return(provider)
    end

    it 'surfaces the plan limit via get_limit' do
      expect(Entitlements::UsageLimitService.get_limit(account, 'max_users')).to eq(3)
    end

    it 'reports a finite, non-unlimited limit in usage_summary' do
      summary = Entitlements::UsageLimitService.usage_summary(account)
      expect(summary['max_users'][:limit]).to eq(3)
      expect(summary['max_users'][:unlimited]).to be false
    end

    it 'denies resource creation when the account has no plan (unsubscribed)' do
      allow(provider).to receive(:plan_for).and_return(nil)
      expect(Entitlements::UsageLimitService.can_add_user?(account)).to be false
      expect(Entitlements::UsageLimitService.get_limit(account, 'max_users')).to eq(0)
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
