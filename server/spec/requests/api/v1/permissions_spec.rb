# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Permissions', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  # The controller authorizes via admin.role.read / admin.access / system.admin.
  let(:user_with_role_view) { create(:user, account: account, permissions: [ 'admin.role.read' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  # Permissions are CODE-defined (the Permissions catalog is the source of
  # truth) — there are no DB rows to seed.

  describe 'GET /api/v1/permissions' do
    context 'with admin.role.read permission' do
      let(:headers) { auth_headers_for(user_with_role_view) }

      it 'returns the catalog of all permissions' do
        get '/api/v1/permissions', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to be_an(Array)
        expect(response_data['data'].length).to eq(Permissions.all_permissions.size)
      end

      it 'includes permission details derived from the catalog name' do
        get '/api/v1/permissions', headers: headers, as: :json

        response_data = json_response
        first_permission = response_data['data'].first

        expect(first_permission).to include('id', 'name', 'resource', 'action', 'description')
        # id === name (no DB row)
        expect(first_permission['id']).to eq(first_permission['name'])
      end

      it 'includes roles_count' do
        get '/api/v1/permissions', headers: headers, as: :json

        response_data = json_response
        first_permission = response_data['data'].first

        expect(first_permission).to have_key('roles_count')
      end
    end

    context 'with admin.access permission' do
      let(:headers) { auth_headers_for(admin_user) }

      it 'returns permissions list' do
        get '/api/v1/permissions', headers: headers, as: :json

        expect_success_response
        expect(json_response['data']).to be_an(Array)
      end
    end

    context 'without required permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/permissions', headers: headers, as: :json

        expect_error_response('Unauthorized access to permissions', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/permissions', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/permissions/:id' do
    let(:headers) { auth_headers_for(user_with_role_view) }
    # :id is the permission NAME (the catalog is keyed by name).
    let(:permission_name) { 'users.read' }

    context 'with admin.role.read permission' do
      it 'returns permission details' do
        get "/api/v1/permissions/#{permission_name}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => permission_name,
          'name' => permission_name
        )
      end

      it 'includes resource and action fields' do
        get "/api/v1/permissions/#{permission_name}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to include('resource', 'action', 'description')
        expect(response_data['data']['resource']).to eq('users')
        expect(response_data['data']['action']).to eq('read')
      end
    end

    context 'when permission does not exist' do
      it 'returns not found error' do
        get '/api/v1/permissions/totally.bogus', headers: headers, as: :json

        expect_error_response('Permission not found', 404)
      end
    end
  end
end
