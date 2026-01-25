# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AppEndpoints', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['apps.read', 'apps.update', 'apps.delete']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:app) { create(:app, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/apps/:app_id/endpoints' do
    let!(:endpoints) do
      [
        create(:app_endpoint, app: app, name: 'Get Users', http_method: 'GET', is_active: true),
        create(:app_endpoint, app: app, name: 'Create User', http_method: 'POST', is_active: true),
        create(:app_endpoint, app: app, name: 'Delete User', http_method: 'DELETE', is_active: false)
      ]
    end

    context 'with apps.read permission' do
      it 'returns all endpoints for the app' do
        get "/api/v1/apps/#{app.id}/endpoints", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['endpoints'].length).to eq(3)
      end

      it 'filters by http_method' do
        get "/api/v1/apps/#{app.id}/endpoints?method=get", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['endpoints'].length).to eq(1)
        expect(data['endpoints'].first['http_method']).to eq('GET')
      end

      it 'filters by active status' do
        get "/api/v1/apps/#{app.id}/endpoints?active=true", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['endpoints'].length).to eq(2)
        expect(data['endpoints'].all? { |e| e['is_active'] }).to be true
      end

      it 'includes pagination metadata' do
        get "/api/v1/apps/#{app.id}/endpoints", headers: headers, as: :json

        expect_success_response
        expect(json_response['data']).to have_key('pagination')
      end
    end

    context 'without apps.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/apps/#{app.id}/endpoints", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.read', 403)
      end
    end

    context 'with non-existent app' do
      it 'returns not found error' do
        get "/api/v1/apps/non-existent-id/endpoints", headers: headers, as: :json

        expect_error_response('App not found', 404)
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/endpoints/:id' do
    let(:endpoint) { create(:app_endpoint, app: app) }

    context 'with apps.read permission' do
      it 'returns the endpoint with analytics' do
        get "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['id']).to eq(endpoint.id)
        expect(data['name']).to eq(endpoint.name)
        expect(data).to have_key('analytics')
      end

      it 'includes endpoint details' do
        get "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'id',
          'name',
          'slug',
          'http_method',
          'path',
          'full_path',
          'is_active'
        )
      end
    end

    context 'without apps.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.read', 403)
      end
    end

    context 'with non-existent endpoint' do
      it 'returns not found error' do
        get "/api/v1/apps/#{app.id}/endpoints/non-existent-id", headers: headers, as: :json

        expect_error_response('API endpoint not found', 404)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/endpoints' do
    let(:valid_params) do
      {
        app_endpoint: {
          name: 'Get Products',
          slug: 'get-products',
          http_method: 'GET',
          path: '/api/products',
          is_active: true
        }
      }
    end

    context 'with apps.update permission' do
      it 'creates a new endpoint' do
        expect do
          post "/api/v1/apps/#{app.id}/endpoints", params: valid_params, headers: headers, as: :json
        end.to change(app.app_endpoints, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('Get Products')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { app_endpoint: { name: '' } }
        post "/api/v1/apps/#{app.id}/endpoints", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/endpoints", params: valid_params, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'PUT /api/v1/apps/:app_id/endpoints/:id' do
    let(:endpoint) { create(:app_endpoint, app: app, name: 'Old Name') }
    let(:update_params) do
      {
        app_endpoint: {
          name: 'New Name'
        }
      }
    end

    context 'with apps.update permission' do
      it 'updates the endpoint' do
        put "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('New Name')
        expect(json_response['message']).to eq('API endpoint updated successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { app_endpoint: { name: '' } }
        put "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        put "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}", params: update_params, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'DELETE /api/v1/apps/:app_id/endpoints/:id' do
    let!(:endpoint) { create(:app_endpoint, app: app) }

    context 'with apps.delete permission' do
      it 'deletes the endpoint' do
        expect do
          delete "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}", headers: headers, as: :json
        end.to change(app.app_endpoints, :count).by(-1)

        expect_success_response
        expect(json_response['message']).to eq('API endpoint deleted successfully')
      end
    end

    context 'without apps.delete permission' do
      let(:user_without_delete) { create(:user, account: account, permissions: ['apps.read', 'apps.update']) }

      it 'returns forbidden error' do
        delete "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}", headers: auth_headers_for(user_without_delete), as: :json

        expect_error_response('Permission denied: apps.delete', 403)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/endpoints/:id/activate' do
    let(:endpoint) { create(:app_endpoint, app: app, is_active: false) }

    context 'with apps.update permission' do
      it 'activates the endpoint' do
        post "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/activate", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['is_active']).to be true
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/activate", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/endpoints/:id/deactivate' do
    let(:endpoint) { create(:app_endpoint, app: app, is_active: true) }

    context 'with apps.update permission' do
      it 'deactivates the endpoint' do
        post "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/deactivate", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['is_active']).to be false
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/deactivate", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/endpoints/:id/test' do
    let(:endpoint) { create(:app_endpoint, app: app) }
    let(:test_params) do
      {
        test_data: { user_id: 123 },
        test_headers: { 'X-Custom-Header' => 'test' }
      }
    end

    context 'with apps.update permission' do
      it 'creates a test call record' do
        expect do
          post "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/test", params: test_params, headers: headers, as: :json
        end.to change(endpoint.app_endpoint_calls, :count).by(1)

        expect_success_response
        data = json_response['data']
        expect(data).to have_key('call_id')
        expect(data).to have_key('status_code')
        expect(data).to have_key('response_time_ms')
      end

      it 'returns test result message' do
        post "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/test", headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('API endpoint test completed')
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/test", params: test_params, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/endpoints/:id/analytics' do
    let(:endpoint) { create(:app_endpoint, app: app) }

    before do
      create_list(:app_endpoint_call, 5, app_endpoint: endpoint, account: account)
    end

    context 'with apps.read permission' do
      it 'returns analytics data' do
        get "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/analytics", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'total_calls',
          'calls_by_day',
          'calls_by_status',
          'average_response_time',
          'success_rate',
          'error_rate'
        )
      end

      it 'respects days parameter' do
        get "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/analytics?days=7", headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without apps.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/apps/#{app.id}/endpoints/#{endpoint.id}/analytics", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.read', 403)
      end
    end
  end
end
