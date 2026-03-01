# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Pages', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ 'admin.access' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  # For GET requests, remove Content-Type: application/json to prevent Rails
  # from wrapping an empty JSON body under the 'page' resource key (parameter wrapping),
  # which conflicts with pagination_params expecting params[:page] to be an integer/nil.
  let(:get_headers) { headers.except('Content-Type').merge('Accept' => 'application/json') }

  describe 'GET /api/v1/admin/pages' do
    let(:headers) { auth_headers_for(admin_user) }

    before do
      create_list(:page, 5, user: admin_user, account: account)
    end

    context 'with admin.access permission' do
      it 'returns paginated list of pages' do
        get '/api/v1/admin/pages', headers: get_headers

        expect_success_response
        data = json_response_data

        expect(data).to be_an(Array)
        expect(data.length).to eq(5)
      end

      it 'includes page details' do
        get '/api/v1/admin/pages', headers: get_headers

        data = json_response_data
        first_page = data.first

        expect(first_page).to include('id', 'title', 'slug', 'status')
      end

      it 'includes author information' do
        get '/api/v1/admin/pages', headers: get_headers

        data = json_response_data
        first_page = data.first

        expect(first_page['author']).to include('id', 'name', 'email')
      end

      it 'includes pagination metadata' do
        get '/api/v1/admin/pages', headers: get_headers

        response_data = json_response
        expect(response_data['meta']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        create(:page, :published, user: admin_user, account: account)

        get '/api/v1/admin/pages',
            params: { status: 'published' },
            headers: get_headers

        expect_success_response
        data = json_response_data

        statuses = data.map { |p| p['status'] }
        expect(statuses.uniq).to eq([ 'published' ])
      end

      it 'filters by author_id' do
        other_user = create(:user, account: account, permissions: [ 'admin.access' ])
        create(:page, user: other_user, account: account)

        get '/api/v1/admin/pages',
            params: { author_id: other_user.id },
            headers: get_headers

        expect_success_response
        data = json_response_data

        author_ids = data.map { |p| p['author']['id'] }
        expect(author_ids.uniq).to eq([ other_user.id ])
      end

      it 'searches by title or content' do
        create(:page, title: 'Unique Search Term Page', user: admin_user, account: account)

        get '/api/v1/admin/pages',
            params: { search: 'Unique Search Term' },
            headers: get_headers

        expect_success_response
        data = json_response_data

        expect(data.length).to eq(1)
        expect(data.first['title']).to include('Unique Search Term')
      end
    end

    context 'without admin.access permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/admin/pages', headers: get_headers

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin/pages', headers: { 'Accept' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/admin/pages/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:page) { create(:page, user: admin_user, account: account) }

    context 'with admin.access permission' do
      it 'returns page details' do
        get "/api/v1/admin/pages/#{page.id}", headers: get_headers

        expect_success_response
        data = json_response_data

        expect(data).to include(
          'id' => page.id,
          'title' => page.title,
          'slug' => page.slug
        )
      end

      it 'includes content and rendered_content' do
        get "/api/v1/admin/pages/#{page.id}", headers: get_headers

        data = json_response_data
        expect(data).to have_key('content')
        expect(data).to have_key('rendered_content')
      end

      it 'includes SEO data' do
        get "/api/v1/admin/pages/#{page.id}", headers: get_headers

        data = json_response_data
        expect(data).to have_key('seo')
      end
    end

    context 'when page does not exist' do
      it 'returns not found error' do
        get '/api/v1/admin/pages/nonexistent-id', headers: get_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/admin/pages' do
    let(:headers) { auth_headers_for(admin_user) }

    context 'with admin.access permission' do
      let(:valid_params) do
        {
          page: {
            title: 'New Test Page',
            slug: 'new-test-page',
            content: 'This is the page content.',
            meta_description: 'A test page description',
            status: 'draft'
          }
        }
      end

      it 'creates a new page' do
        expect {
          post '/api/v1/admin/pages', params: valid_params, headers: headers, as: :json
        }.to change(Page, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['title']).to eq('New Test Page')
      end

      it 'sets current user as author' do
        post '/api/v1/admin/pages', params: valid_params, headers: headers, as: :json

        data = json_response_data
        expect(data['author']['id']).to eq(admin_user.id)
      end
    end

    context 'with invalid data' do
      it 'returns validation error for blank title' do
        post '/api/v1/admin/pages',
             params: { page: { title: '', content: 'Content' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PUT /api/v1/admin/pages/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:page) { create(:page, user: admin_user, account: account) }

    context 'with admin.access permission' do
      it 'updates page successfully' do
        put "/api/v1/admin/pages/#{page.id}",
            params: { page: { title: 'Updated Title' } },
            headers: headers,
            as: :json

        expect_success_response

        page.reload
        expect(page.title).to eq('Updated Title')
      end

      it 'updates content' do
        put "/api/v1/admin/pages/#{page.id}",
            params: { page: { content: 'Updated content here' } },
            headers: headers,
            as: :json

        expect_success_response

        page.reload
        expect(page.content).to eq('Updated content here')
      end
    end
  end

  describe 'DELETE /api/v1/admin/pages/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:page) { create(:page, user: admin_user, account: account) }

    context 'with admin.access permission' do
      it 'deletes page successfully' do
        page_id = page.id

        delete "/api/v1/admin/pages/#{page_id}", headers: headers, as: :json

        expect_success_response
        expect(Page.find_by(id: page_id)).to be_nil
      end
    end
  end

  describe 'POST /api/v1/admin/pages/:id/publish' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:page) { create(:page, :draft, user: admin_user, account: account) }

    context 'with admin.access permission' do
      it 'publishes the page' do
        post "/api/v1/admin/pages/#{page.id}/publish", headers: headers, as: :json

        expect_success_response

        page.reload
        expect(page.status).to eq('published')
        expect(page.published_at).to be_present
      end
    end
  end

  describe 'POST /api/v1/admin/pages/:id/unpublish' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:page) { create(:page, :published, user: admin_user, account: account) }

    context 'with admin.access permission' do
      it 'unpublishes the page' do
        post "/api/v1/admin/pages/#{page.id}/unpublish", headers: headers, as: :json

        expect_success_response

        page.reload
        expect(page.status).to eq('draft')
      end
    end
  end

  describe 'POST /api/v1/admin/pages/:id/duplicate' do
    let(:headers) { auth_headers_for(admin_user) }
    let!(:page) { create(:page, :published, user: admin_user, account: account, title: 'Original Page') }

    context 'with admin.access permission' do
      it 'creates a duplicate of the page' do
        expect {
          post "/api/v1/admin/pages/#{page.id}/duplicate", headers: headers, as: :json
        }.to change(Page, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['title']).to eq('Original Page (Copy)')
        expect(data['status']).to eq('draft')
      end

      it 'sets current user as author of duplicate' do
        post "/api/v1/admin/pages/#{page.id}/duplicate", headers: headers, as: :json

        data = json_response_data
        expect(data['author']['id']).to eq(admin_user.id)
      end
    end
  end
end
