# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Permissions', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_role_view) { create(:user, account: account, permissions: [ 'admin.role.view' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  before do
    # Ensure some permissions exist
    create_list(:permission, 5)
  end

  describe 'GET /api/v1/permissions' do
    context 'with admin.role.view permission' do
      let(:headers) { auth_headers_for(user_with_role_view) }

      it 'returns list of all permissions' do
        get '/api/v1/permissions', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to be_an(Array)
        expect(response_data['data'].length).to be >= 5
      end

      it 'includes permission details' do
        get '/api/v1/permissions', headers: headers, as: :json

        response_data = json_response
        first_permission = response_data['data'].first

        expect(first_permission).to include('id', 'name', 'resource', 'action', 'description')
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
    let(:permission) { Permission.first || create(:permission) }

    context 'with admin.role.view permission' do
      it 'returns permission details' do
        get "/api/v1/permissions/#{permission.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => permission.id,
          'name' => permission.name
        )
      end

      it 'includes resource and action fields' do
        get "/api/v1/permissions/#{permission.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to include('resource', 'action', 'description')
      end
    end

    context 'when permission does not exist' do
      it 'returns not found error' do
        get '/api/v1/permissions/nonexistent-id', headers: headers, as: :json

        expect_error_response('Permission not found', 404)
      end
    end
  end
end
