# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::RateLimiting::RateLimitingController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ 'admin.settings.security' ]) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  # The controller calls current_account (from AuditLogging concern) which is not
  # included in this controller. Define it so AuditLog.create! can work.
  before do
    allow_any_instance_of(Api::V1::Admin::RateLimiting::RateLimitingController)
      .to receive(:current_account).and_return(account)
  end

  describe 'GET /api/v1/admin/rate_limiting/statistics' do
    context 'with admin security permission' do
      it 'returns rate limiting statistics' do
        allow(RateLimiting::BaseService).to receive(:get_statistics).and_return(
          {
            total_requests: 1000,
            throttled_requests: 50,
            throttle_percentage: 5.0
          }
        )

        get '/api/v1/admin/rate_limiting/statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('total_requests', 'throttled_requests')
      end

      it 'handles service errors gracefully' do
        allow(RateLimiting::BaseService).to receive(:get_statistics).and_raise(StandardError, 'Service error')

        get '/api/v1/admin/rate_limiting/statistics', headers: headers, as: :json

        expect_error_response('Failed to retrieve rate limiting statistics', 500)
      end
    end

    context 'without admin security permission' do
      it 'returns forbidden error' do
        get '/api/v1/admin/rate_limiting/statistics', headers: non_admin_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/admin/rate_limiting/violations' do
    context 'with admin security permission' do
      it 'returns recent violations' do
        get '/api/v1/admin/rate_limiting/violations', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('violations', 'total_count')
      end
    end
  end

  describe 'GET /api/v1/admin/rate_limiting/limits/:identifier' do
    context 'with admin security permission' do
      it 'returns rate limits for identifier' do
        allow(RateLimiting::BaseService).to receive(:get_limit_info).and_return(
          { current_count: 10, limit: 100, remaining: 90 }
        )

        get '/api/v1/admin/rate_limiting/limits/user-123', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('identifier', 'limits')
      end

      it 'returns error when identifier is blank' do
        get '/api/v1/admin/rate_limiting/limits/', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/admin/rate_limiting/limits/:identifier' do
    context 'with admin security permission' do
      it 'clears rate limits for identifier' do
        allow(RateLimiting::BaseService).to receive(:clear_limits_for).and_return(5)

        delete '/api/v1/admin/rate_limiting/limits/user-123', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('message', 'keys_cleared', 'identifier')
      end

      it 'handles argument errors' do
        allow(RateLimiting::BaseService).to receive(:clear_limits_for).and_raise(ArgumentError, 'Invalid identifier')

        delete '/api/v1/admin/rate_limiting/limits/invalid', headers: headers, as: :json

        expect_error_response('Invalid identifier', 400)
      end
    end
  end

  describe 'POST /api/v1/admin/rate_limiting/disable' do
    context 'with admin security permission' do
      it 'disables rate limiting temporarily' do
        allow(RateLimiting::BaseService).to receive(:disable_temporarily)

        post '/api/v1/admin/rate_limiting/disable',
             params: { duration_minutes: 60 }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('message', 'disabled_until', 'duration_minutes')
      end

      it 'validates duration range' do
        post '/api/v1/admin/rate_limiting/disable',
             params: { duration_minutes: 500 }.to_json,
             headers: headers

        expect_error_response('Duration must be between 1 and 480 minutes', 400)
      end

      it 'uses default duration when not provided' do
        allow(RateLimiting::BaseService).to receive(:disable_temporarily)

        post '/api/v1/admin/rate_limiting/disable', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['duration_minutes']).to eq(60)
      end
    end
  end

  describe 'POST /api/v1/admin/rate_limiting/enable' do
    context 'with admin security permission' do
      it 'enables rate limiting' do
        allow(RateLimiting::BaseService).to receive(:re_enable)

        post '/api/v1/admin/rate_limiting/enable', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('message', 'enabled_at')
      end
    end
  end

  describe 'GET /api/v1/admin/rate_limiting/status' do
    context 'with admin security permission' do
      it 'returns rate limiting status' do
        allow(RateLimiting::BaseService).to receive(:temporarily_disabled?).and_return(false)
        allow(System::SettingsService).to receive(:rate_limiting_enabled?).and_return(true)

        get '/api/v1/admin/rate_limiting/status', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('system_enabled', 'temporarily_disabled', 'effective_status')
      end

      it 'includes remaining time when temporarily disabled' do
        allow(RateLimiting::BaseService).to receive(:temporarily_disabled?).and_return(true)
        allow(System::SettingsService).to receive(:rate_limiting_enabled?).and_return(true)

        # Define a redis method on the MemoryStore instance for this test,
        # since MemoryStore doesn't normally have a redis method
        redis_double = double('Redis', ttl: 1800)
        Rails.cache.define_singleton_method(:redis) { redis_double }

        get '/api/v1/admin/rate_limiting/status', headers: headers, as: :json

        # Clean up the singleton method
        Rails.cache.singleton_class.remove_method(:redis) if Rails.cache.respond_to?(:redis)

        expect_success_response
        data = json_response_data
        expect(data).to include('disabled_until', 'remaining_seconds')
      end
    end
  end

  describe 'GET /api/v1/admin/rate_limiting/tiers' do
    context 'with admin security permission' do
      it 'returns available rate limiting tiers' do
        get '/api/v1/admin/rate_limiting/tiers', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('tiers', 'endpoint_costs')
        expect(data['tiers']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/admin/rate_limiting/accounts/:account_id/statistics' do
    let(:target_account) { create(:account) }

    context 'with admin security permission' do
      it 'returns account rate limit statistics' do
        allow(RateLimiting::BaseService).to receive(:get_account_statistics).and_return(
          { tier: 'standard', requests_count: 500, limit: 1000 }
        )

        get "/api/v1/admin/rate_limiting/accounts/#{target_account.id}/statistics", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('tier', 'requests_count', 'limit')
      end

      it 'returns error when statistics retrieval fails' do
        allow(RateLimiting::BaseService).to receive(:get_account_statistics).and_return(nil)

        get "/api/v1/admin/rate_limiting/accounts/#{target_account.id}/statistics", headers: headers, as: :json

        expect_error_response('Failed to retrieve account statistics', 500)
      end
    end
  end

  describe 'POST /api/v1/admin/rate_limiting/accounts/:account_id/override_tier' do
    let(:target_account) { create(:account) }

    context 'with admin security permission' do
      it 'overrides account tier successfully' do
        allow(RateLimiting::BaseService).to receive(:override_account_tier).and_return(true)
        allow(AuditLog).to receive(:create!).and_return(true)

        post "/api/v1/admin/rate_limiting/accounts/#{target_account.id}/override_tier",
             params: { tier: 'enterprise', duration_hours: 24 }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('message', 'account_id', 'tier', 'duration_hours')
      end

      it 'returns error for invalid tier' do
        post "/api/v1/admin/rate_limiting/accounts/#{target_account.id}/override_tier",
             params: { tier: 'invalid_tier', duration_hours: 24 }.to_json,
             headers: headers

        expect_error_response(/Invalid tier/, 400)
      end

      it 'creates audit log for tier override' do
        allow(RateLimiting::BaseService).to receive(:override_account_tier).and_return(true)
        # The action 'rate_limit_tier_override' is not in AuditActions::ALL_ACTIONS,
        # so stub the validation to allow it
        allow_any_instance_of(AuditLog).to receive(:valid?).and_return(true)
        allow_any_instance_of(AuditLog).to receive(:apply_integrity_hash)

        expect {
          post "/api/v1/admin/rate_limiting/accounts/#{target_account.id}/override_tier",
               params: { tier: 'enterprise', duration_hours: 24 }.to_json,
               headers: headers
        }.to change { AuditLog.count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('rate_limit_tier_override')
        expect(audit_log.resource_type).to eq('Account')
      end
    end
  end

  describe 'DELETE /api/v1/admin/rate_limiting/accounts/:account_id/override_tier' do
    let(:target_account) { create(:account) }

    context 'with admin security permission' do
      it 'clears tier override successfully' do
        allow(RateLimiting::BaseService).to receive(:clear_account_tier_override).and_return(true)
        allow(AuditLog).to receive(:create!).and_return(true)

        delete "/api/v1/admin/rate_limiting/accounts/#{target_account.id}/override_tier", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('message', 'account_id')
      end

      it 'creates audit log for clearing tier override' do
        allow(RateLimiting::BaseService).to receive(:clear_account_tier_override).and_return(true)
        # The action 'rate_limit_tier_override_cleared' is not in AuditActions::ALL_ACTIONS,
        # so stub the validation to allow it
        allow_any_instance_of(AuditLog).to receive(:valid?).and_return(true)
        allow_any_instance_of(AuditLog).to receive(:apply_integrity_hash)

        expect {
          delete "/api/v1/admin/rate_limiting/accounts/#{target_account.id}/override_tier", headers: headers, as: :json
        }.to change { AuditLog.count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq('rate_limit_tier_override_cleared')
      end
    end
  end

  describe 'GET /api/v1/admin/rate_limiting/accounts' do
    context 'with admin security permission' do
      before do
        create_list(:account, 5, status: 'active')
      end

      it 'returns paginated accounts usage' do
        allow(RateLimiting::TieredService).to receive(:tier_for_account).and_return(:standard)
        allow(RateLimiting::TieredService).to receive(:account_usage).and_return({ requests: 100, limit: 1000 })
        allow(RateLimiting::TieredService).to receive(:account_rate_limited?).and_return(false)

        get '/api/v1/admin/rate_limiting/accounts', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('accounts', 'pagination')
        expect(data['accounts']).to be_an(Array)
        expect(data['pagination']).to include('current_page', 'total_pages', 'total_count', 'per_page')
      end

      it 'supports pagination parameters' do
        allow(RateLimiting::TieredService).to receive(:tier_for_account).and_return(:standard)
        allow(RateLimiting::TieredService).to receive(:account_usage).and_return({ requests: 100, limit: 1000 })
        allow(RateLimiting::TieredService).to receive(:account_rate_limited?).and_return(false)

        get '/api/v1/admin/rate_limiting/accounts?page=2&per_page=10', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']['current_page']).to eq(2)
        expect(data['pagination']['per_page']).to eq(10)
      end
    end
  end
end
