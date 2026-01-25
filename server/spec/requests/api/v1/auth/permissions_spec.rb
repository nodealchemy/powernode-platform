# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Auth::Permissions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/auth/permissions' do
    context 'with authenticated user' do
      it 'returns user permissions' do
        get '/api/v1/auth/permissions',
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['type']).to eq('user')
        expect(response_data['data']['user_id']).to eq(user.id)
        expect(response_data['data']['account_id']).to eq(user.account_id)
        expect(response_data['data']['email']).to eq(user.email)
        expect(response_data['data']).to have_key('roles')
        expect(response_data['data']).to have_key('permissions')
        expect(response_data['data']).to have_key('permission_version')
        expect(response_data['data']).to have_key('account_status')
        expect(response_data['data']).to have_key('user_status')
      end

      it 'includes permission version hash' do
        get '/api/v1/auth/permissions',
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['permission_version']).to be_present
        expect(response_data['data']['permission_version']).to be_a(String)
        expect(response_data['data']['permission_version'].length).to eq(8)
      end
    end

    context 'with worker authentication' do
      let(:worker) { create(:worker, account: account) }
      let(:worker_payload) do
        {
          sub: worker.id,
          account_id: worker.account_id,
          type: 'worker',
          permissions: worker.permission_names,
          version: Security::JwtService::CURRENT_TOKEN_VERSION
        }
      end
      let(:worker_token) { Security::JwtService.encode(worker_payload) }
      let(:worker_headers) do
        {
          'Authorization' => "Bearer #{worker_token}",
          'Content-Type' => 'application/json'
        }
      end

      it 'returns worker permissions' do
        get '/api/v1/auth/permissions',
            headers: worker_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['type']).to eq('worker')
        expect(response_data['data']['worker_id']).to eq(worker.id)
        expect(response_data['data']['account_id']).to eq(worker.account_id)
        expect(response_data['data']['name']).to eq(worker.name)
        expect(response_data['data']).to have_key('worker_type')
        expect(response_data['data']).to have_key('roles')
        expect(response_data['data']).to have_key('permissions')
        expect(response_data['data']).to have_key('worker_status')
      end
    end

    context 'with service authentication' do
      let(:service_payload) do
        {
          service: 'worker',
          type: 'service',
          exp: 24.hours.from_now.to_i
        }
      end
      let(:service_token) { Security::JwtService.encode(service_payload) }
      let(:service_headers) do
        {
          'Authorization' => "Bearer #{service_token}",
          'Content-Type' => 'application/json'
        }
      end

      it 'returns service permissions' do
        get '/api/v1/auth/permissions',
            headers: service_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['type']).to eq('service')
        expect(response_data['data']['service']).to eq('worker')
        expect(response_data['data']['permissions']).to eq(['*'])
        expect(response_data['data']['permission_version']).to eq('service')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/auth/permissions',
            as: :json

        expect_error_response('Authentication required', 401)
      end
    end
  end

  describe 'GET /api/v1/auth/permissions/check' do
    let(:user_with_permissions) do
      create(:user, account: account).tap do |u|
        allow(u).to receive(:permission_names).and_return(['users.read', 'users.create'])
      end
    end
    let(:perm_headers) { auth_headers_for(user_with_permissions) }

    context 'checking single permission' do
      it 'returns granted status for permission user has' do
        get '/api/v1/auth/permissions/check',
            params: { permissions: 'users.read' },
            headers: perm_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['permissions']).to be_an(Array)
        expect(response_data['data']['permissions'].first['permission']).to eq('users.read')
        expect(response_data['data']['permissions'].first['granted']).to be true
        expect(response_data['data']['has_all']).to be true
        expect(response_data['data']['has_any']).to be true
      end

      it 'returns not granted status for permission user lacks' do
        get '/api/v1/auth/permissions/check',
            params: { permissions: 'users.delete' },
            headers: perm_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['permissions'].first['permission']).to eq('users.delete')
        expect(response_data['data']['permissions'].first['granted']).to be false
        expect(response_data['data']['has_all']).to be false
        expect(response_data['data']['has_any']).to be false
      end
    end

    context 'checking multiple permissions' do
      it 'returns status for all checked permissions' do
        get '/api/v1/auth/permissions/check',
            params: { permissions: ['users.read', 'users.create', 'users.delete'] },
            headers: perm_headers,
            as: :json

        expect_success_response
        response_data = json_response

        permissions = response_data['data']['permissions']
        expect(permissions.length).to eq(3)

        read_perm = permissions.find { |p| p['permission'] == 'users.read' }
        create_perm = permissions.find { |p| p['permission'] == 'users.create' }
        delete_perm = permissions.find { |p| p['permission'] == 'users.delete' }

        expect(read_perm['granted']).to be true
        expect(create_perm['granted']).to be true
        expect(delete_perm['granted']).to be false

        expect(response_data['data']['has_all']).to be false
        expect(response_data['data']['has_any']).to be true
      end
    end

    context 'with service token' do
      let(:service_payload) do
        {
          service: 'worker',
          type: 'service',
          exp: 24.hours.from_now.to_i
        }
      end
      let(:service_token) { Security::JwtService.encode(service_payload) }
      let(:service_headers) do
        {
          'Authorization' => "Bearer #{service_token}",
          'Content-Type' => 'application/json'
        }
      end

      it 'returns granted for all checked permissions' do
        get '/api/v1/auth/permissions/check',
            params: { permissions: ['users.read', 'users.delete', 'accounts.manage'] },
            headers: service_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['permissions'].all? { |p| p['granted'] }).to be true
        expect(response_data['data']['has_all']).to be true
        expect(response_data['data']['has_any']).to be true
      end
    end

    context 'without permissions parameter' do
      it 'returns error' do
        get '/api/v1/auth/permissions/check',
            headers: perm_headers,
            as: :json

        expect_error_response('Permissions parameter required', 400)
      end
    end

    context 'without authentication' do
      it 'returns empty permissions list' do
        get '/api/v1/auth/permissions/check',
            params: { permissions: 'users.read' },
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['permissions'].first['granted']).to be false
        expect(response_data['data']['has_all']).to be false
        expect(response_data['data']['has_any']).to be false
      end
    end
  end
end
