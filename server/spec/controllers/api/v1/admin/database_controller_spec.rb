# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Admin::DatabaseController, type: :controller do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account) }
  let(:regular_user) { create(:user, account: account) }
  let(:internal_worker) { create(:worker) }
  let(:worker_jwt) { Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now) }

  before do
    # Grant system.admin permission to admin user
    admin_role = Role.find_or_create_by!(name: 'system.admin') do |role|
      role.display_name = 'System Administrator'
      role.role_type = 'admin'
      role.description = 'Full system administration access'
    end
    # Ensure the permission exists and is assigned
    system_admin_permission = Permission.find_or_create_by!(name: 'system.admin') do |p|
      p.description = 'Full system admin access'
      p.category = 'admin'
    end
    admin_role.permissions << system_admin_permission unless admin_role.permissions.include?(system_admin_permission)
    admin_user.roles << admin_role unless admin_user.roles.include?(admin_role)
  end

  describe 'GET #pool_stats' do
    context 'with valid worker token' do
      before do
        request.headers['Authorization'] = "Bearer #{worker_jwt}"
      end

      it 'returns database pool statistics' do
        get :pool_stats

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['success']).to be true
        expect(body['data']).to include('size', 'checked_out', 'checked_in')
      end
    end

    context 'with admin permission' do
      before do
        sign_in_as_user(admin_user)
      end

      it 'returns database pool statistics' do
        get :pool_stats

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['success']).to be true
        expect(body['data']['size']).to be_a(Integer)
      end
    end

    context 'with regular user (no permission)' do
      before do
        sign_in_as_user(regular_user)
      end

      it 'returns unauthorized' do
        get :pool_stats

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get :pool_stats

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET #ping' do
    context 'with valid worker JWT' do
      before do
        request.headers['Authorization'] = "Bearer #{worker_jwt}"
      end

      it 'returns successful database ping' do
        get :ping

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['success']).to be true
        expect(body['data']['status']).to eq('ok')
        expect(body['data']).to include('response_time_ms', 'timestamp')
      end

      it 'returns response time in milliseconds' do
        get :ping

        body = JSON.parse(response.body)
        expect(body['data']['response_time_ms']).to be_a(Numeric)
        expect(body['data']['response_time_ms']).to be >= 0
      end
    end

    context 'when database connection fails' do
      before do
        request.headers['Authorization'] = "Bearer #{worker_jwt}"
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError.new('Connection failed'))
      end

      it 'returns service unavailable' do
        get :ping

        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body['success']).to be false
        expect(body['error']).to include('Database ping failed')
      end
    end
  end

  describe 'GET #health' do
    context 'with valid worker JWT' do
      before do
        request.headers['Authorization'] = "Bearer #{worker_jwt}"
      end

      it 'returns comprehensive health status' do
        get :health

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['success']).to be true
        expect(body['data']['status']).to be_in([ 'healthy', 'warning', 'critical' ])
        expect(body['data']['checks']).to include('connection', 'pool_utilization', 'response_time')
      end

      it 'includes connection check' do
        get :health

        body = JSON.parse(response.body)
        expect(body['data']['checks']['connection']).to include('status')
      end

      it 'includes pool utilization metrics' do
        get :health

        body = JSON.parse(response.body)
        pool_check = body['data']['checks']['pool_utilization']
        expect(pool_check).to include('status', 'utilization_percentage')
      end

      it 'includes response time check' do
        get :health

        body = JSON.parse(response.body)
        expect(body['data']['checks']['response_time']).to include('status', 'response_time_ms')
      end
    end

    context 'with invalid worker token' do
      before do
        request.headers['Authorization'] = 'Bearer invalid_token'
      end

      it 'returns forbidden without admin permission' do
        get :health

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'worker JWT authentication' do
    it 'accepts valid worker JWT' do
      request.headers['Authorization'] = "Bearer #{worker_jwt}"
      get :pool_stats

      expect(response).to have_http_status(:ok)
    end

    it 'rejects invalid token without admin auth' do
      request.headers['Authorization'] = 'Bearer wrong_token'
      get :pool_stats

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects expired worker JWT' do
      expired_token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 1.second.ago)
      request.headers['Authorization'] = "Bearer #{expired_token}"
      get :pool_stats

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
