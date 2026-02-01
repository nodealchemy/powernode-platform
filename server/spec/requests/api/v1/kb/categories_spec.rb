# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Kb::Categories', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['kb.manage']) }
  let(:editor_user) { create(:user, account: account, permissions: ['kb.update']) }
  let(:read_only_user) { create(:user, account: account, permissions: []) }

  let(:headers) { auth_headers_for(user) }
  let(:editor_headers) { auth_headers_for(editor_user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }

  let!(:public_category) do
    KnowledgeBase::Category.create!(
      name: 'Public Category',
      slug: 'public-category',
      description: 'A public category',
      is_public: true,
      sort_order: 1
    )
  end

  let!(:private_category) do
    KnowledgeBase::Category.create!(
      name: 'Private Category',
      slug: 'private-category',
      description: 'A private category',
      is_public: false,
      sort_order: 2
    )
  end

  let!(:child_category) do
    KnowledgeBase::Category.create!(
      name: 'Child Category',
      slug: 'child-category',
      description: 'A child category',
      is_public: true,
      parent: public_category,
      sort_order: 1
    )
  end

  describe 'GET /api/v1/kb/categories' do
    context 'public view (no auth)' do
      it 'returns only public root categories with children' do
        get '/api/v1/kb/categories', as: :json

        expect(response).to have_http_status(:success)
        data = json_response
        expect(data['data']).to be_an(Array)
        expect(data['data'].length).to eq(1)
        expect(data['data'].first['name']).to eq('Public Category')
        expect(data['data'].first).to have_key('children')
        expect(data['data'].first['children'].length).to eq(1)
      end
    end

    context 'admin view' do
      it 'returns all categories when admin flag set' do
        get '/api/v1/kb/categories?admin=true', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['categories'].length).to be >= 2
        expect(data).to have_key('pagination')
      end

      it 'searches categories by name' do
        get '/api/v1/kb/categories?admin=true&search=Public', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['categories'].all? { |c| c['name'].include?('Public') }).to be true
      end

      it 'supports pagination' do
        get '/api/v1/kb/categories?admin=true&page=1&per_page=10', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_pages', 'total_count', 'per_page')
      end
    end

    context 'without manage permissions' do
      it 'returns public view even with admin flag' do
        get '/api/v1/kb/categories?admin=true', headers: read_only_headers, as: :json

        expect(response).to have_http_status(:success)
        data = json_response
        expect(data['data']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/kb/categories/tree' do
    context 'public view' do
      it 'returns tree structure of public categories' do
        get '/api/v1/kb/categories/tree', as: :json

        expect(response).to have_http_status(:success)
        data = json_response
        expect(data['data']).to be_an(Array)
        expect(data['data'].first).to include('id', 'name', 'slug', 'children')
        expect(data['data'].first['children']).to be_an(Array)
      end
    end

    context 'admin view with permissions' do
      it 'returns full category tree including private categories' do
        get '/api/v1/kb/categories/tree', headers: headers, as: :json

        expect(response).to have_http_status(:success)
        data = json_response
        expect(data['data'].length).to be >= 2
      end
    end
  end

  describe 'GET /api/v1/kb/categories/:id' do
    let!(:article) do
      KnowledgeBase::Article.create!(
        title: 'Test Article',
        slug: 'test-article',
        content: 'Content',
        status: 'published',
        is_public: true,
        category: public_category,
        author: user,
        published_at: Time.current
      )
    end

    context 'public view' do
      it 'returns public category with articles' do
        get "/api/v1/kb/categories/#{public_category.id}", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['category']).to include(
          'id' => public_category.id,
          'name' => 'Public Category',
          'slug' => 'public-category'
        )
        expect(data['articles']).to be_an(Array)
        expect(data['articles'].length).to eq(1)
      end

      it 'returns not found for private category' do
        get "/api/v1/kb/categories/#{private_category.id}", as: :json

        expect_error_response('Category not found', 404)
      end

      it 'returns not found for non-existent category' do
        get '/api/v1/kb/categories/00000000-0000-0000-0000-000000000000', as: :json

        expect_error_response('Category not found', 404)
      end
    end

    context 'admin view' do
      it 'returns detailed category info for admin' do
        get "/api/v1/kb/categories/#{public_category.id}?admin=true", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']).to include(
          'id' => public_category.id,
          'name' => 'Public Category',
          'is_public' => true,
          'sort_order' => 1
        )
        expect(data['category']).to have_key('metadata')
      end

      it 'returns forbidden for non-manager' do
        get "/api/v1/kb/categories/#{public_category.id}?admin=true", headers: editor_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'POST /api/v1/kb/categories' do
    let(:category_params) do
      {
        category: {
          name: 'New Category',
          slug: 'new-category',
          description: 'A new category',
          is_public: true,
          sort_order: 10,
          icon: 'book',
          color: '#3b82f6'
        }
      }
    end

    context 'with kb.manage permission' do
      it 'creates a new category' do
        expect {
          post '/api/v1/kb/categories', params: category_params, headers: headers, as: :json
        }.to change(KnowledgeBase::Category, :count).by(1)

        expect_success_response
        data = json_response_data
        expect(data['category']).to include(
          'name' => 'New Category',
          'slug' => 'new-category',
          'is_public' => true
        )
      end

      it 'creates category with parent' do
        params_with_parent = category_params.deep_merge(
          category: { parent_id: public_category.id }
        )

        post '/api/v1/kb/categories', params: params_with_parent, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']['parent_id']).to eq(public_category.id)
      end

      it 'returns validation errors for invalid data' do
        invalid_params = { category: { name: '' } }

        post '/api/v1/kb/categories', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without kb.manage permission' do
      it 'returns forbidden error' do
        post '/api/v1/kb/categories', params: category_params, headers: editor_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/kb/categories', params: category_params, as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/kb/categories/:id' do
    let(:update_params) do
      {
        category: {
          name: 'Updated Category',
          description: 'Updated description'
        }
      }
    end

    context 'with kb.manage permission' do
      it 'updates the category' do
        patch "/api/v1/kb/categories/#{public_category.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['category']['name']).to eq('Updated Category')
        expect(public_category.reload.name).to eq('Updated Category')
      end

      it 'returns validation errors for invalid data' do
        invalid_params = { category: { name: '' } }

        patch "/api/v1/kb/categories/#{public_category.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without kb.manage permission' do
      it 'returns forbidden error' do
        patch "/api/v1/kb/categories/#{public_category.id}", params: update_params, headers: editor_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'for non-existent category' do
      it 'returns not found error' do
        patch '/api/v1/kb/categories/00000000-0000-0000-0000-000000000000', params: update_params, headers: headers, as: :json

        expect_error_response('Category not found', 404)
      end
    end
  end

  describe 'DELETE /api/v1/kb/categories/:id' do
    let(:empty_category) do
      KnowledgeBase::Category.create!(
        name: 'Empty Category',
        slug: 'empty-category',
        is_public: true
      )
    end

    context 'with kb.manage permission' do
      it 'deletes an empty category' do
        category_id = empty_category.id

        expect {
          delete "/api/v1/kb/categories/#{category_id}", headers: headers, as: :json
        }.to change(KnowledgeBase::Category, :count).by(-1)

        expect_success_response
      end

      it 'returns error when category has articles' do
        KnowledgeBase::Article.create!(
          title: 'Test Article',
          slug: 'test-article',
          content: 'Content',
          status: 'draft',
          category: public_category,
          author: user
        )

        delete "/api/v1/kb/categories/#{public_category.id}", headers: headers, as: :json

        expect_error_response('Cannot delete category with articles', 400)
      end
    end

    context 'without kb.manage permission' do
      it 'returns forbidden error' do
        delete "/api/v1/kb/categories/#{empty_category.id}", headers: editor_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'for non-existent category' do
      it 'returns not found error' do
        delete '/api/v1/kb/categories/00000000-0000-0000-0000-000000000000', headers: headers, as: :json

        expect_error_response('Category not found', 404)
      end
    end
  end
end
