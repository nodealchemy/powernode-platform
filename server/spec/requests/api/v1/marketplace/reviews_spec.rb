# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Marketplace::Reviews', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }
  let(:workflow_template) { create(:ai_workflow_template, :published) }

  before do
    # User model doesn't have avatar_url method but controller's serialize_review calls it.
    # Define it on User so it doesn't raise NoMethodError in the controller.
    User.define_method(:avatar_url) { nil } unless User.method_defined?(:avatar_url)
  end

  describe 'GET /api/v1/marketplace/reviews' do
    context 'without authentication (public access)' do
      let!(:approved_review) { create(:marketplace_review, :approved, reviewable: workflow_template) }
      let!(:pending_review) { create(:marketplace_review, :pending, reviewable: workflow_template) }

      it 'returns only approved reviews for public access' do
        get "/api/v1/marketplace/reviews?item_type=template&item_id=#{workflow_template.id}", as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.all? { |r| r['moderation_status'] == 'approved' }).to be true
      end

      it 'filters by rating' do
        get "/api/v1/marketplace/reviews?item_type=template&item_id=#{workflow_template.id}&rating=5", as: :json

        expect_success_response
      end

      it 'filters verified reviews' do
        get "/api/v1/marketplace/reviews?item_type=template&item_id=#{workflow_template.id}&verified=true", as: :json

        expect_success_response
      end

      it 'sorts by helpful count' do
        get "/api/v1/marketplace/reviews?item_type=template&item_id=#{workflow_template.id}&sort=helpful", as: :json

        expect_success_response
      end

      it 'paginates results' do
        get "/api/v1/marketplace/reviews?item_type=template&item_id=#{workflow_template.id}&page=1&per_page=10", as: :json

        expect_success_response
        meta = json_response['meta']
        expect(meta['current_page']).to eq(1)
        expect(meta['per_page']).to eq(10)
      end

      it 'returns all reviews when no item specified' do
        get '/api/v1/marketplace/reviews', as: :json

        expect_success_response
      end
    end

    context 'with moderator permissions' do
      let(:moderator) { create(:user, account: account, permissions: [ 'marketplace.moderate' ]) }
      let(:moderator_headers) { auth_headers_for(moderator) }

      it 'includes pending reviews when requested' do
        get "/api/v1/marketplace/reviews?item_type=template&item_id=#{workflow_template.id}&include_pending=true",
            headers: moderator_headers,
            as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/marketplace/reviews/:id' do
    let(:review) { create(:marketplace_review, :approved, reviewable: workflow_template) }

    context 'without authentication' do
      it 'returns review details' do
        get "/api/v1/marketplace/reviews/#{review.id}", as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(review.id)
        expect(data['rating']).to eq(review.rating)
        expect(data).to have_key('author')
        expect(data).to have_key('reviewable')
      end
    end
  end

  describe 'POST /api/v1/marketplace/reviews' do
    let(:valid_params) do
      {
        item_type: 'template',
        item_id: workflow_template.id,
        rating: 5,
        title: 'Great template!',
        content: 'This template works perfectly for my needs.'
      }
    end

    context 'with authentication' do
      it 'creates a new review' do
        expect {
          post '/api/v1/marketplace/reviews', params: valid_params, headers: headers, as: :json
        }.to change { MarketplaceReview.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['rating']).to eq(5)
        expect(data['title']).to eq('Great template!')
        expect(data['moderation_status']).to eq('pending')
      end

      it 'prevents duplicate reviews' do
        # Create an existing review for this account/template
        create(:marketplace_review, reviewable: workflow_template, account: account, user: user)

        post '/api/v1/marketplace/reviews', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(422)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('already reviewed')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.merge(rating: nil)

        post '/api/v1/marketplace/reviews', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/marketplace/reviews', params: valid_params, as: :json

        expect_error_response('Access token required', 401)
      end
    end

    context 'for non-existent item' do
      it 'returns error' do
        invalid_params = valid_params.merge(item_id: SecureRandom.uuid)

        post '/api/v1/marketplace/reviews', params: invalid_params, headers: headers, as: :json

        expect_error_response('Item not found', 404)
      end
    end
  end

  describe 'PATCH /api/v1/marketplace/reviews/:id' do
    let(:review) { create(:marketplace_review, :approved, reviewable: workflow_template, account: account, user: user) }
    let(:update_params) do
      {
        rating: 4,
        title: 'Updated title',
        content: 'Updated content'
      }
    end

    context 'with proper authorization' do
      it 'updates the review' do
        patch "/api/v1/marketplace/reviews/#{review.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['rating']).to eq(4)
        expect(data['title']).to eq('Updated title')
        expect(data['moderation_status']).to eq('pending')
      end
    end

    context 'without authorization' do
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account) }
      let(:other_headers) { auth_headers_for(other_user) }

      it 'returns forbidden error' do
        patch "/api/v1/marketplace/reviews/#{review.id}", params: update_params, headers: other_headers, as: :json

        expect_error_response('Cannot edit this review', 403)
      end
    end
  end

  describe 'DELETE /api/v1/marketplace/reviews/:id' do
    let!(:review) { create(:marketplace_review, reviewable: workflow_template, account: account, user: user) }

    context 'with proper authorization' do
      it 'deletes the review' do
        expect {
          delete "/api/v1/marketplace/reviews/#{review.id}", headers: headers, as: :json
        }.to change { MarketplaceReview.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Review deleted successfully')
      end
    end

    context 'without authorization' do
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account) }
      let(:other_headers) { auth_headers_for(other_user) }

      it 'returns forbidden error' do
        delete "/api/v1/marketplace/reviews/#{review.id}", headers: other_headers, as: :json

        expect_error_response('Cannot delete this review', 403)
      end
    end
  end

  describe 'POST /api/v1/marketplace/reviews/:id/helpful' do
    let(:other_account) { create(:account) }
    let(:other_user) { create(:user, account: other_account) }
    let(:review) { create(:marketplace_review, :approved, reviewable: workflow_template, account: other_account, user: other_user) }

    context 'with authentication' do
      it 'marks review as helpful' do
        post "/api/v1/marketplace/reviews/#{review.id}/helpful", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('helpful_count')
      end
    end

    context 'when marking own review' do
      let(:own_review) { create(:marketplace_review, reviewable: workflow_template, account: account, user: user) }

      it 'returns error' do
        post "/api/v1/marketplace/reviews/#{own_review.id}/helpful", headers: headers, as: :json

        expect(response).to have_http_status(422)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('Cannot mark your own review as helpful')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/marketplace/reviews/#{review.id}/helpful", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/marketplace/reviews/:id/approve' do
    let(:review) { create(:marketplace_review, :pending, reviewable: workflow_template) }
    let(:moderator) { create(:user, account: account, permissions: [ 'marketplace.moderate' ]) }
    let(:moderator_headers) { auth_headers_for(moderator) }

    context 'with moderator permissions' do
      it 'approves the review' do
        post "/api/v1/marketplace/reviews/#{review.id}/approve", headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['moderation_status']).to eq('approved')
      end
    end

    context 'without moderator permissions' do
      it 'returns forbidden error' do
        post "/api/v1/marketplace/reviews/#{review.id}/approve", headers: headers, as: :json

        expect_error_response('Forbidden', 403)
      end
    end
  end

  describe 'POST /api/v1/marketplace/reviews/:id/reject' do
    let(:review) { create(:marketplace_review, :pending, reviewable: workflow_template) }
    let(:moderator) { create(:user, account: account, permissions: [ 'marketplace.moderate' ]) }
    let(:moderator_headers) { auth_headers_for(moderator) }

    context 'with moderator permissions' do
      it 'rejects the review' do
        post "/api/v1/marketplace/reviews/#{review.id}/reject", headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['moderation_status']).to eq('rejected')
      end
    end

    context 'without moderator permissions' do
      it 'returns forbidden error' do
        post "/api/v1/marketplace/reviews/#{review.id}/reject", headers: headers, as: :json

        expect_error_response('Forbidden', 403)
      end
    end
  end

  describe 'POST /api/v1/marketplace/reviews/:id/flag' do
    let(:review) { create(:marketplace_review, :approved, reviewable: workflow_template) }

    context 'with authentication' do
      it 'flags the review for moderation' do
        post "/api/v1/marketplace/reviews/#{review.id}/flag", headers: headers, as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Review flagged for moderation')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/marketplace/reviews/#{review.id}/flag", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end
end
