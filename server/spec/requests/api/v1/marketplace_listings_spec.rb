# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::MarketplaceListings', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:app) { create(:marketplace_definition, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/marketplace_listings' do
    context 'without authentication (public access)' do
      let!(:approved_listing) { create(:marketplace_listing, :approved) }
      let!(:pending_listing) { create(:marketplace_listing, :pending) }

      it 'returns only approved listings for public access' do
        get '/api/v1/marketplace_listings', as: :json

        expect_success_response
        data = json_response_data['data']
        expect(data).to be_an(Array)
        expect(data.all? { |l| l['review_status'] == 'approved' }).to be true
      end

      it 'filters by category' do
        get '/api/v1/marketplace_listings', params: { category: 'productivity' }, as: :json

        expect_success_response
      end

      it 'filters by featured' do
        get '/api/v1/marketplace_listings', params: { featured: 'true' }, as: :json

        expect_success_response
      end

      it 'searches listings' do
        get '/api/v1/marketplace_listings', params: { search: 'test' }, as: :json

        expect_success_response
      end

      it 'sorts by title' do
        get '/api/v1/marketplace_listings', params: { sort: 'title' }, as: :json

        expect_success_response
      end

      it 'paginates results' do
        get '/api/v1/marketplace_listings', params: { page: 1, per_page: 10 }, as: :json

        expect_success_response
        meta = json_response_data['meta']['pagination']
        expect(meta['current_page']).to eq(1)
        expect(meta['per_page']).to eq(10)
      end
    end

    context 'with authentication' do
      it 'allows filtering by status for authenticated users' do
        get '/api/v1/marketplace_listings', params: { status: 'pending' }, headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/marketplace_listings/:id' do
    let(:listing) { create(:marketplace_listing, :approved) }

    context 'without authentication' do
      it 'returns listing details' do
        get "/api/v1/marketplace_listings/#{listing.id}", as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(listing.id)
        expect(data['title']).to eq(listing.title)
      end
    end

    context 'with authentication' do
      it 'returns detailed listing information' do
        listing = create(:marketplace_listing, app: app)

        get "/api/v1/marketplace_listings/#{listing.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(listing.id)
        expect(data).to have_key('app')
      end
    end
  end

  describe 'POST /api/v1/marketplace_listings' do
    let(:valid_params) do
      {
        app_id: app.id,
        marketplace_listing: {
          title: 'Test Listing',
          short_description: 'A test listing',
          long_description: 'A longer test description',
          category: 'productivity'
        }
      }
    end

    context 'with authentication and app ownership' do
      it 'creates a new marketplace listing' do
        expect {
          post '/api/v1/marketplace_listings', params: valid_params, headers: headers, as: :json
        }.to change { MarketplaceListing.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['title']).to eq('Test Listing')
        expect(data['review_status']).to eq('pending')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.deep_merge(marketplace_listing: { title: nil })

        post '/api/v1/marketplace_listings', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/marketplace_listings', params: valid_params, as: :json

        expect_error_response('Authentication required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/marketplace_listings/:id' do
    let(:listing) { create(:marketplace_listing, app: app) }
    let(:update_params) do
      {
        app_id: app.id,
        marketplace_listing: {
          title: 'Updated Title',
          short_description: 'Updated description'
        }
      }
    end

    context 'with proper authorization' do
      it 'updates the listing' do
        patch "/api/v1/marketplace_listings/#{listing.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['title']).to eq('Updated Title')
        expect(data['short_description']).to eq('Updated description')
      end
    end

    context 'without authorization' do
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account) }
      let(:other_headers) { auth_headers_for(other_user) }

      it 'returns forbidden error' do
        patch "/api/v1/marketplace_listings/#{listing.id}", params: update_params, headers: other_headers, as: :json

        expect_error_response('App not found', 404)
      end
    end
  end

  describe 'DELETE /api/v1/marketplace_listings/:id' do
    let!(:listing) { create(:marketplace_listing, app: app) }

    context 'with proper authorization' do
      it 'deletes the listing' do
        expect {
          delete "/api/v1/marketplace_listings/#{listing.id}",
                 params: { app_id: app.id },
                 headers: headers,
                 as: :json
        }.to change { MarketplaceListing.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Marketplace listing deleted successfully')
      end
    end
  end

  describe 'POST /api/v1/marketplace_listings/:id/submit' do
    let(:listing) { create(:marketplace_listing, :rejected, app: app) }

    context 'with proper authorization' do
      it 'resubmits a rejected listing' do
        post "/api/v1/marketplace_listings/#{listing.id}/submit",
             params: { app_id: app.id },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['review_status']).to eq('pending')
      end
    end

    context 'when listing is not rejected' do
      let(:approved_listing) { create(:marketplace_listing, :approved, app: app) }

      it 'returns error' do
        post "/api/v1/marketplace_listings/#{approved_listing.id}/submit",
             params: { app_id: app.id },
             headers: headers,
             as: :json

        expect_error_response('Listing must be rejected to resubmit', 422)
      end
    end
  end

  describe 'POST /api/v1/marketplace_listings/:id/approve' do
    let(:listing) { create(:marketplace_listing, :pending, app: app) }
    let(:reviewer_user) { create(:user, account: account, permissions: ['marketplace.review']) }
    let(:reviewer_headers) { auth_headers_for(reviewer_user) }

    context 'with review permissions' do
      it 'approves the listing' do
        post "/api/v1/marketplace_listings/#{listing.id}/approve",
             params: { app_id: app.id, notes: 'Looks good' },
             headers: reviewer_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['review_status']).to eq('approved')
      end
    end

    context 'without review permissions' do
      it 'returns forbidden error' do
        post "/api/v1/marketplace_listings/#{listing.id}/approve",
             params: { app_id: app.id },
             headers: headers,
             as: :json

        expect_error_response('Unauthorized to review listings', 403)
      end
    end
  end

  describe 'POST /api/v1/marketplace_listings/:id/reject' do
    let(:listing) { create(:marketplace_listing, :pending, app: app) }
    let(:reviewer_user) { create(:user, account: account, permissions: ['marketplace.review']) }
    let(:reviewer_headers) { auth_headers_for(reviewer_user) }

    context 'with review permissions' do
      it 'rejects the listing with notes' do
        post "/api/v1/marketplace_listings/#{listing.id}/reject",
             params: { app_id: app.id, notes: 'Needs improvement' },
             headers: reviewer_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['review_status']).to eq('rejected')
      end

      it 'requires rejection notes' do
        post "/api/v1/marketplace_listings/#{listing.id}/reject",
             params: { app_id: app.id },
             headers: reviewer_headers,
             as: :json

        expect_error_response('Rejection notes are required', 400)
      end
    end
  end

  describe 'POST /api/v1/marketplace_listings/:id/feature' do
    let(:listing) { create(:marketplace_listing, :approved, app: app) }
    let(:admin_user) { create(:user, account: account, permissions: ['marketplace.admin']) }
    let(:admin_headers) { auth_headers_for(admin_user) }

    context 'with admin permissions' do
      it 'features the listing' do
        post "/api/v1/marketplace_listings/#{listing.id}/feature",
             params: { app_id: app.id },
             headers: admin_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['featured']).to be true
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        post "/api/v1/marketplace_listings/#{listing.id}/feature",
             params: { app_id: app.id },
             headers: headers,
             as: :json

        expect_error_response('Unauthorized to perform admin actions', 403)
      end
    end
  end

  describe 'POST /api/v1/marketplace_listings/:id/unfeature' do
    let(:listing) { create(:marketplace_listing, :featured, app: app) }
    let(:admin_user) { create(:user, account: account, permissions: ['marketplace.admin']) }
    let(:admin_headers) { auth_headers_for(admin_user) }

    context 'with admin permissions' do
      it 'unfeatures the listing' do
        post "/api/v1/marketplace_listings/#{listing.id}/unfeature",
             params: { app_id: app.id },
             headers: admin_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['featured']).to be false
      end
    end
  end

  describe 'GET /api/v1/marketplace_listings/categories' do
    context 'without authentication' do
      it 'returns available categories' do
        get '/api/v1/marketplace_listings/categories', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end
end
