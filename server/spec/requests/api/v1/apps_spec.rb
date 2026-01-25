# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Apps', type: :request do
  let(:account) { create(:account) }
  let(:user_with_permission) { create(:user, account: account, permissions: ['apps.manage']) }
  let(:user_with_admin_permission) { create(:user, account: account, permissions: ['apps.manage', 'admin.marketplace.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  # Helper to create App since factory may not exist
  let(:create_app) do
    ->(attrs = {}) {
      App.create!({
        account: account,
        name: "Test App #{SecureRandom.hex(4)}",
        slug: "test-app-#{SecureRandom.hex(4)}",
        description: 'A test application',
        short_description: 'Test app',
        category: 'productivity',
        status: 'draft',
        version: '1.0.0'
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/apps' do
    let(:headers) { auth_headers_for(user_with_permission) }

    before do
      3.times { create_app.call }
    end

    context 'with apps.manage permission' do
      it 'returns list of apps' do
        get '/api/v1/apps', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to be_an(Array)
        expect(response_data['data']['data'].length).to eq(3)
      end

      it 'includes app details' do
        get '/api/v1/apps', headers: headers, as: :json

        response_data = json_response
        first_app = response_data['data']['data'].first

        expect(first_app).to include('id', 'name', 'slug', 'status', 'version')
      end

      it 'includes pagination' do
        get '/api/v1/apps', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        create_app.call(status: 'published')

        get '/api/v1/apps',
            params: { status: 'published' },
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        statuses = response_data['data']['data'].map { |a| a['status'] }
        expect(statuses.uniq).to eq(['published'])
      end

      it 'searches by name' do
        create_app.call(name: 'Unique Search App')

        get '/api/v1/apps',
            params: { search: 'Unique Search' },
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data'].length).to eq(1)
        expect(response_data['data']['data'].first['name']).to include('Unique Search')
      end
    end

    context 'with admin.marketplace.manage permission' do
      let(:headers) { auth_headers_for(user_with_admin_permission) }

      it 'returns all apps across accounts' do
        other_account = create(:account)
        App.create!(
          account: other_account,
          name: 'Other Account App',
          slug: 'other-account-app',
          description: 'App from other account',
          status: 'draft',
          version: '1.0.0'
        )

        get '/api/v1/apps', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data'].length).to eq(4)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/apps', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/apps/:id' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:app) { create_app.call }

    context 'with apps.manage permission' do
      it 'returns app details' do
        get "/api/v1/apps/#{app.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to include(
          'id' => app.id,
          'name' => app.name,
          'slug' => app.slug
        )
      end
    end

    context 'when app does not exist' do
      it 'returns not found error' do
        get '/api/v1/apps/nonexistent-id', headers: headers, as: :json

        expect_error_response('App not found', 404)
      end
    end

    context 'when accessing other account app' do
      let(:other_account) { create(:account) }
      let(:other_app) do
        App.create!(
          account: other_account,
          name: 'Other App',
          slug: 'other-app',
          description: 'Other account app',
          status: 'draft',
          version: '1.0.0'
        )
      end

      it 'returns not found error' do
        get "/api/v1/apps/#{other_app.id}", headers: headers, as: :json

        expect_error_response('App not found', 404)
      end
    end
  end

  describe 'POST /api/v1/apps' do
    let(:headers) { auth_headers_for(user_with_permission) }

    context 'with apps.manage permission' do
      let(:valid_params) do
        {
          app: {
            name: 'New Test App',
            slug: 'new-test-app',
            description: 'A new test application',
            short_description: 'New app',
            category: 'productivity'
          }
        }
      end

      it 'creates a new app' do
        expect {
          post '/api/v1/apps', params: valid_params, headers: headers, as: :json
        }.to change(App, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['data']['name']).to eq('New Test App')
      end

      it 'sets initial status as draft' do
        post '/api/v1/apps', params: valid_params, headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['data']['status']).to eq('draft')
      end
    end
  end

  describe 'PUT /api/v1/apps/:id' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:app) { create_app.call }

    context 'with apps.manage permission' do
      it 'updates app successfully' do
        put "/api/v1/apps/#{app.id}",
            params: { app: { description: 'Updated description' } },
            headers: headers,
            as: :json

        expect_success_response

        app.reload
        expect(app.description).to eq('Updated description')
      end
    end
  end

  describe 'DELETE /api/v1/apps/:id' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:app) { create_app.call }

    context 'with apps.manage permission' do
      it 'deletes app successfully' do
        app_id = app.id

        delete "/api/v1/apps/#{app_id}", headers: headers, as: :json

        expect_success_response
        expect(App.find_by(id: app_id)).to be_nil
      end
    end
  end

  describe 'POST /api/v1/apps/:id/publish' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:app) { create_app.call(status: 'under_review') }

    context 'with apps.manage permission' do
      it 'publishes app' do
        allow_any_instance_of(App).to receive(:under_review?).and_return(true)
        allow_any_instance_of(App).to receive(:publish!).and_return(true)

        post "/api/v1/apps/#{app.id}/publish", headers: headers, as: :json

        expect_success_response
      end

      it 'prevents publishing non-review app' do
        draft_app = create_app.call(status: 'draft')
        allow_any_instance_of(App).to receive(:under_review?).and_return(false)

        post "/api/v1/apps/#{draft_app.id}/publish", headers: headers, as: :json

        expect_error_response('App must be in review status to publish', 422)
      end
    end
  end

  describe 'POST /api/v1/apps/:id/unpublish' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:app) { create_app.call(status: 'published') }

    context 'with apps.manage permission' do
      it 'unpublishes app' do
        allow_any_instance_of(App).to receive(:published?).and_return(true)
        allow_any_instance_of(App).to receive(:unpublish!).and_return(true)

        post "/api/v1/apps/#{app.id}/unpublish", headers: headers, as: :json

        expect_success_response
      end

      it 'prevents unpublishing non-published app' do
        draft_app = create_app.call(status: 'draft')
        allow_any_instance_of(App).to receive(:published?).and_return(false)

        post "/api/v1/apps/#{draft_app.id}/unpublish", headers: headers, as: :json

        expect_error_response('App must be published to unpublish', 422)
      end
    end
  end

  describe 'POST /api/v1/apps/:id/submit_for_review' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:app) { create_app.call(status: 'draft') }

    context 'with apps.manage permission' do
      it 'submits app for review' do
        allow_any_instance_of(App).to receive(:draft?).and_return(true)
        allow_any_instance_of(App).to receive(:submit_for_review!).and_return(true)

        post "/api/v1/apps/#{app.id}/submit_for_review", headers: headers, as: :json

        expect_success_response
      end

      it 'prevents submitting non-draft app' do
        published_app = create_app.call(status: 'published')
        allow_any_instance_of(App).to receive(:draft?).and_return(false)

        post "/api/v1/apps/#{published_app.id}/submit_for_review", headers: headers, as: :json

        expect_error_response('App must be in draft status to submit for review', 422)
      end
    end
  end

  describe 'GET /api/v1/apps/:id/analytics' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:app) { create_app.call }

    context 'with apps.manage permission' do
      it 'returns app analytics' do
        allow_any_instance_of(App).to receive(:subscription_count).and_return(10)
        allow_any_instance_of(App).to receive(:active_subscriptions_count).and_return(8)
        allow_any_instance_of(App).to receive(:total_revenue).and_return(1000)
        allow_any_instance_of(App).to receive(:monthly_revenue).and_return(100)
        allow_any_instance_of(App).to receive(:average_rating).and_return(4.5)
        allow_any_instance_of(App).to receive(:total_reviews).and_return(20)
        allow_any_instance_of(App).to receive(:download_count).and_return(50)
        allow_any_instance_of(App).to receive(:recent_activity_summary).and_return({})

        get "/api/v1/apps/#{app.id}/analytics", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to include('subscription_count', 'total_revenue')
      end
    end
  end
end
