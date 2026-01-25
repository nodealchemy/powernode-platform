# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AppFeatures', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['apps.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:app) { create(:app, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/apps/:app_id/features' do
    let!(:features) do
      [
        create(:app_feature, app: app, name: 'Feature A', feature_type: 'toggle', default_enabled: true),
        create(:app_feature, app: app, name: 'Feature B', feature_type: 'quota', default_enabled: false),
        create(:app_feature, app: app, name: 'Feature C', feature_type: 'permission', default_enabled: true)
      ]
    end

    context 'with authorized access' do
      it 'returns all features for the app' do
        get "/api/v1/apps/#{app.id}/features", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(3)
      end

      it 'filters by feature type' do
        get "/api/v1/apps/#{app.id}/features?type=toggle", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(1)
        expect(data.first['feature_type']).to eq('toggle')
      end

      it 'filters by default_enabled status' do
        get "/api/v1/apps/#{app.id}/features?default_enabled=true", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(2)
        expect(data.all? { |f| f['default_enabled'] }).to be true
      end

      it 'searches by name' do
        get "/api/v1/apps/#{app.id}/features?search=Feature%20A", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(1)
        expect(data.first['name']).to eq('Feature A')
      end

      it 'sorts by name' do
        get "/api/v1/apps/#{app.id}/features?sort=name", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        names = data.map { |f| f['name'] }
        expect(names).to eq(names.sort)
      end
    end

    context 'without authorized access' do
      it 'returns forbidden error' do
        get "/api/v1/apps/#{app.id}/features", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Unauthorized to access this app', 403)
      end
    end

    context 'with non-existent app' do
      it 'returns not found error' do
        get "/api/v1/apps/non-existent-id/features", headers: headers, as: :json

        expect_error_response('App not found', 404)
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/features/:id' do
    let(:feature) { create(:app_feature, app: app) }

    context 'with authorized access' do
      it 'returns the feature with detailed information' do
        get "/api/v1/apps/#{app.id}/features/#{feature.id}", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['id']).to eq(feature.id)
        expect(data).to include(
          'name',
          'slug',
          'feature_type',
          'description',
          'default_enabled',
          'dependencies',
          'configuration'
        )
      end
    end

    context 'with non-existent feature' do
      it 'returns not found error' do
        get "/api/v1/apps/#{app.id}/features/non-existent-id", headers: headers, as: :json

        expect_error_response('App feature not found', 404)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/features' do
    let(:valid_params) do
      {
        app_feature: {
          name: 'New Feature',
          slug: 'new-feature',
          feature_type: 'toggle',
          description: 'A new feature',
          default_enabled: true
        }
      }
    end

    context 'with authorized access' do
      it 'creates a new feature' do
        expect do
          post "/api/v1/apps/#{app.id}/features", params: valid_params, headers: headers, as: :json
        end.to change(app.app_features, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('New Feature')
        expect(json_response['message']).to eq('App feature created successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { app_feature: { name: '' } }
        post "/api/v1/apps/#{app.id}/features", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without authorized access' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/features", params: valid_params, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Unauthorized to access this app', 403)
      end
    end
  end

  describe 'PUT /api/v1/apps/:app_id/features/:id' do
    let(:feature) { create(:app_feature, app: app, name: 'Old Name') }
    let(:update_params) do
      {
        app_feature: {
          name: 'Updated Name'
        }
      }
    end

    context 'with authorized access' do
      it 'updates the feature' do
        put "/api/v1/apps/#{app.id}/features/#{feature.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('Updated Name')
        expect(json_response['message']).to eq('App feature updated successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { app_feature: { name: '' } }
        put "/api/v1/apps/#{app.id}/features/#{feature.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/apps/:app_id/features/:id' do
    let!(:feature) { create(:app_feature, app: app) }

    context 'with authorized access' do
      it 'deletes the feature' do
        expect do
          delete "/api/v1/apps/#{app.id}/features/#{feature.id}", headers: headers, as: :json
        end.to change(app.app_features, :count).by(-1)

        expect_success_response
        expect(json_response['message']).to eq('App feature deleted successfully')
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/features/:id/enable_by_default' do
    let(:feature) { create(:app_feature, app: app, default_enabled: false) }

    context 'with authorized access' do
      it 'enables the feature by default' do
        post "/api/v1/apps/#{app.id}/features/#{feature.id}/enable_by_default", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['default_enabled']).to be true
        expect(json_response['message']).to eq('App feature enabled by default')
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/features/:id/disable_by_default' do
    let(:feature) { create(:app_feature, app: app, default_enabled: true) }

    context 'with authorized access' do
      it 'disables the feature by default' do
        post "/api/v1/apps/#{app.id}/features/#{feature.id}/disable_by_default", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['default_enabled']).to be false
        expect(json_response['message']).to eq('App feature disabled by default')
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/features/:id/duplicate' do
    let(:feature) { create(:app_feature, app: app, name: 'Original Feature') }

    context 'with authorized access' do
      it 'duplicates the feature' do
        expect do
          post "/api/v1/apps/#{app.id}/features/#{feature.id}/duplicate", headers: headers, as: :json
        end.to change(app.app_features, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('Original Feature (Copy)')
        expect(json_response['message']).to eq('App feature duplicated successfully')
      end

      it 'duplicates with custom name' do
        post "/api/v1/apps/#{app.id}/features/#{feature.id}/duplicate", params: { name: 'Custom Copy' }, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('Custom Copy')
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/features/types' do
    context 'with authorized access' do
      it 'returns available feature types' do
        get "/api/v1/apps/#{app.id}/features/types", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['types']).to be_an(Array)
        expect(data['types'].first).to include('value', 'label', 'description')
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/features/dependencies' do
    let!(:feature1) { create(:app_feature, app: app, slug: 'feature-1') }
    let!(:feature2) { create(:app_feature, app: app, slug: 'feature-2') }

    context 'with authorized access' do
      it 'returns available dependencies' do
        get "/api/v1/apps/#{app.id}/features/dependencies", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to be_an(Array)
        expect(data.length).to eq(2)
        expect(data.first).to include('id', 'name', 'slug', 'feature_type')
      end

      it 'excludes specified feature from dependencies' do
        get "/api/v1/apps/#{app.id}/features/dependencies?exclude_id=#{feature1.id}", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(1)
        expect(data.first['id']).to eq(feature2.id)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/features/validate_dependencies' do
    let(:feature) { create(:app_feature, app: app, slug: 'feature-1') }
    let(:dependency) { create(:app_feature, app: app, slug: 'feature-2') }

    context 'with valid dependencies' do
      it 'returns validation success' do
        params = { feature_id: feature.id, dependencies: [dependency.slug] }
        post "/api/v1/apps/#{app.id}/features/validate_dependencies", params: params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['valid']).to be true
        expect(data['errors']).to be_empty
      end
    end

    context 'with self-referential dependency' do
      it 'returns validation error' do
        params = { feature_id: feature.id, dependencies: [feature.slug] }
        post "/api/v1/apps/#{app.id}/features/validate_dependencies", params: params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['valid']).to be false
        expect(data['errors']).to include('Feature cannot depend on itself')
      end
    end

    context 'with non-existent dependency' do
      it 'returns validation error' do
        params = { feature_id: feature.id, dependencies: ['non-existent'] }
        post "/api/v1/apps/#{app.id}/features/validate_dependencies", params: params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['valid']).to be false
        expect(data['errors']).to include("Feature 'non-existent' does not exist")
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/features/usage_report' do
    let!(:feature) { create(:app_feature, app: app) }

    context 'with authorized access' do
      it 'returns usage report' do
        get "/api/v1/apps/#{app.id}/features/usage_report", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include('app', 'features', 'summary')
        expect(data['app']).to include('id', 'name')
        expect(data['summary']).to include('total_features', 'used_features', 'unused_features')
      end

      it 'includes feature usage details' do
        get "/api/v1/apps/#{app.id}/features/usage_report", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['features']).to be_an(Array)
        expect(data['features'].first).to include(
          'id',
          'name',
          'slug',
          'feature_type',
          'usage_count',
          'used_in_plans'
        )
      end
    end
  end
end
