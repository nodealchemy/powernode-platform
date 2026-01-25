# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::MarketplaceCategories', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['marketplace.read']) }
  let(:admin_user) { create(:user, account: account, permissions: ['marketplace.admin']) }
  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }

  describe 'GET /api/v1/marketplace_categories' do
    let!(:root_category) { create(:marketplace_category, parent: nil, position: 1, status: 'active') }
    let!(:child_category) { create(:marketplace_category, parent: root_category, position: 2, status: 'active') }
    let!(:inactive_category) { create(:marketplace_category, parent: nil, position: 3, status: 'inactive') }

    context 'with proper permissions' do
      it 'returns list of all categories' do
        get '/api/v1/marketplace_categories', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['categories']).to be_an(Array)
        expect(data['categories'].length).to eq(3)
      end

      it 'filters active categories only' do
        get '/api/v1/marketplace_categories', params: { active_only: 'true' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['categories'].length).to eq(2)
        expect(data['categories'].all? { |c| c['status'] == 'active' }).to be true
      end

      it 'filters root categories only' do
        get '/api/v1/marketplace_categories', params: { root_only: 'true' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['categories'].length).to eq(2)
        expect(data['categories'].all? { |c| c['parent_id'].nil? }).to be true
      end

      it 'filters by parent_id' do
        get '/api/v1/marketplace_categories', params: { parent_id: root_category.id }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['categories'].length).to eq(1)
        expect(data['categories'].first['id']).to eq(child_category.id)
      end
    end

    context 'without marketplace.read permission' do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:no_permission_headers) { auth_headers_for(user_without_permission) }

      it 'returns forbidden error' do
        get '/api/v1/marketplace_categories', headers: no_permission_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/marketplace_categories', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/marketplace_categories/:id' do
    let(:category) { create(:marketplace_category, status: 'active') }
    let!(:child) { create(:marketplace_category, parent: category, status: 'active') }

    context 'with proper permissions' do
      it 'returns category details with children' do
        get "/api/v1/marketplace_categories/#{category.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']).to include(
          'id' => category.id,
          'name' => category.name
        )
        expect(data['category']['children']).to be_an(Array)
        expect(data['category']).to have_key('breadcrumb')
      end

      it 'returns not found for non-existent category' do
        get "/api/v1/marketplace_categories/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Category not found', 404)
      end
    end
  end

  describe 'POST /api/v1/marketplace_categories' do
    let(:valid_params) do
      {
        category: {
          name: 'Test Category',
          slug: 'test-category',
          description: 'A test category',
          status: 'active'
        }
      }
    end

    context 'with admin permissions' do
      it 'creates a new category' do
        expect {
          post '/api/v1/marketplace_categories', params: valid_params, headers: admin_headers, as: :json
        }.to change { MarketplaceCategory.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['category']).to include(
          'name' => 'Test Category',
          'slug' => 'test-category'
        )
      end

      it 'sets position automatically' do
        existing = create(:marketplace_category, parent: nil, position: 5)

        post '/api/v1/marketplace_categories', params: valid_params, headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']['position']).to eq(6)
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { category: { name: nil } }

        post '/api/v1/marketplace_categories', params: invalid_params, headers: admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'without marketplace.admin permission' do
      it 'returns forbidden error' do
        post '/api/v1/marketplace_categories', params: valid_params, headers: headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'PATCH /api/v1/marketplace_categories/:id' do
    let(:category) { create(:marketplace_category) }
    let(:update_params) do
      {
        category: {
          name: 'Updated Category Name',
          description: 'Updated description'
        }
      }
    end

    context 'with admin permissions' do
      it 'updates the category' do
        patch "/api/v1/marketplace_categories/#{category.id}", params: update_params, headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']['name']).to eq('Updated Category Name')
        expect(data['category']['description']).to eq('Updated description')
      end
    end

    context 'without marketplace.admin permission' do
      it 'returns forbidden error' do
        patch "/api/v1/marketplace_categories/#{category.id}", params: update_params, headers: headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'DELETE /api/v1/marketplace_categories/:id' do
    let!(:category) { create(:marketplace_category) }

    context 'with admin permissions' do
      it 'deletes the category' do
        expect {
          delete "/api/v1/marketplace_categories/#{category.id}", headers: admin_headers, as: :json
        }.to change { MarketplaceCategory.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Category deleted')
      end

      it 'prevents deletion of category with subcategories' do
        parent = create(:marketplace_category)
        create(:marketplace_category, parent: parent)

        delete "/api/v1/marketplace_categories/#{parent.id}", headers: admin_headers, as: :json

        expect_error_response('Cannot delete category with subcategories', 422)
      end
    end

    context 'without marketplace.admin permission' do
      it 'returns forbidden error' do
        delete "/api/v1/marketplace_categories/#{category.id}", headers: headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/marketplace_categories/:id/activate' do
    let(:category) { create(:marketplace_category, status: 'inactive') }

    context 'with admin permissions' do
      it 'activates the category' do
        post "/api/v1/marketplace_categories/#{category.id}/activate", headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']['status']).to eq('active')
        expect(data['message']).to eq('Category activated')
      end
    end

    context 'without marketplace.admin permission' do
      it 'returns forbidden error' do
        post "/api/v1/marketplace_categories/#{category.id}/activate", headers: headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/marketplace_categories/:id/deactivate' do
    let(:category) { create(:marketplace_category, status: 'active') }

    context 'with admin permissions' do
      it 'deactivates the category' do
        post "/api/v1/marketplace_categories/#{category.id}/deactivate", headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']['status']).to eq('inactive')
        expect(data['message']).to eq('Category deactivated')
      end
    end

    context 'without marketplace.admin permission' do
      it 'returns forbidden error' do
        post "/api/v1/marketplace_categories/#{category.id}/deactivate", headers: headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/marketplace_categories/:id/reorder' do
    let(:category) { create(:marketplace_category, parent: nil, position: 2) }

    context 'with admin permissions' do
      it 'reorders the category to new position' do
        post "/api/v1/marketplace_categories/#{category.id}/reorder",
             params: { position: 1 },
             headers: admin_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']['position']).to eq(1)
        expect(data['message']).to eq('Category reordered')
      end

      it 'returns error for invalid position' do
        post "/api/v1/marketplace_categories/#{category.id}/reorder",
             params: { position: 0 },
             headers: admin_headers,
             as: :json

        expect_error_response('Invalid position', 422)
      end
    end
  end

  describe 'POST /api/v1/marketplace_categories/bulk_reorder' do
    let!(:cat1) { create(:marketplace_category, position: 1) }
    let!(:cat2) { create(:marketplace_category, position: 2) }
    let!(:cat3) { create(:marketplace_category, position: 3) }

    context 'with admin permissions' do
      it 'reorders multiple categories' do
        post '/api/v1/marketplace_categories/bulk_reorder',
             params: { order: [cat3.id, cat1.id, cat2.id] },
             headers: admin_headers,
             as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Categories reordered')
      end

      it 'returns error when order array is empty' do
        post '/api/v1/marketplace_categories/bulk_reorder',
             params: { order: [] },
             headers: admin_headers,
             as: :json

        expect_error_response('Order array is required', 422)
      end
    end
  end

  describe 'GET /api/v1/marketplace_categories/:id/analytics' do
    let(:category) { create(:marketplace_category, status: 'active') }

    context 'with proper permissions' do
      it 'returns category analytics' do
        get "/api/v1/marketplace_categories/#{category.id}/analytics", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']).to include('id' => category.id)
        expect(data['analytics']).to include(
          'app_count',
          'total_installs',
          'installs_in_period',
          'total_reviews',
          'average_rating'
        )
        expect(data['time_range']).to eq('30d')
      end

      it 'accepts custom time range' do
        get "/api/v1/marketplace_categories/#{category.id}/analytics",
            params: { range: '7d' },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']).to eq('7d')
      end
    end
  end
end
