# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AppReviews', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['reviews.moderate']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:app) { create(:app) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/apps/:app_id/reviews' do
    let!(:reviews) do
      [
        create(:app_review, app: app, rating: 5, moderation_status: 'approved'),
        create(:app_review, app: app, rating: 4, moderation_status: 'approved'),
        create(:app_review, app: app, rating: 3, moderation_status: 'approved')
      ]
    end

    context 'without authentication' do
      it 'returns public reviews' do
        get "/api/v1/apps/#{app.id}/reviews", as: :json

        expect_success_response
        data = json_response['data']
        expect(data['reviews'].length).to eq(3)
      end

      it 'includes pagination metadata' do
        get "/api/v1/apps/#{app.id}/reviews", as: :json

        expect_success_response
        expect(json_response['data']['pagination']).to include(
          'page',
          'per_page',
          'total_count',
          'total_pages'
        )
      end
    end

    context 'with filters' do
      it 'filters by rating' do
        get "/api/v1/apps/#{app.id}/reviews?rating=5", as: :json

        expect_success_response
        data = json_response['data']
        expect(data['reviews'].length).to eq(1)
        expect(data['reviews'].first['rating']).to eq(5)
      end

      it 'filters by verified purchases only' do
        get "/api/v1/apps/#{app.id}/reviews?verified_only=true", as: :json

        expect_success_response
      end

      it 'filters high quality reviews' do
        get "/api/v1/apps/#{app.id}/reviews?high_quality=true", as: :json

        expect_success_response
      end
    end

    context 'with sorting' do
      it 'sorts by helpful count' do
        get "/api/v1/apps/#{app.id}/reviews?sort_by=helpful", as: :json

        expect_success_response
        data = json_response['data']
        expect(data['filters_applied']['sort_by']).to eq('helpful')
      end

      it 'sorts by rating high to low' do
        get "/api/v1/apps/#{app.id}/reviews?sort_by=rating_high", as: :json

        expect_success_response
      end
    end

    context 'with pagination' do
      it 'respects per_page parameter' do
        get "/api/v1/apps/#{app.id}/reviews?per_page=2", as: :json

        expect_success_response
        data = json_response['data']
        expect(data['reviews'].length).to eq(2)
        expect(data['pagination']['per_page']).to eq(2)
      end

      it 'caps per_page at 50' do
        get "/api/v1/apps/#{app.id}/reviews?per_page=100", as: :json

        expect_success_response
        data = json_response['data']
        expect(data['pagination']['per_page']).to eq(50)
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/reviews/summary' do
    before do
      create(:review_aggregation_cache, app: app)
    end

    context 'without authentication' do
      it 'returns review summary statistics' do
        get "/api/v1/apps/#{app.id}/reviews/summary", as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'average_rating',
          'total_reviews',
          'rating_distribution',
          'sentiment_distribution'
        )
      end
    end
  end

  describe 'GET /api/v1/reviews/:id' do
    let(:review) { create(:app_review, app: app, moderation_status: 'approved') }

    context 'without authentication' do
      it 'returns the review with extended details' do
        get "/api/v1/reviews/#{review.id}", as: :json

        expect_success_response
        data = json_response['data']['review']
        expect(data['id']).to eq(review.id)
        expect(data).to include(
          'rating',
          'title',
          'content',
          'moderation_status',
          'media_attachments',
          'responses'
        )
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/reviews' do
    let(:valid_params) do
      {
        review: {
          rating: 5,
          title: 'Great app!',
          content: 'This app is amazing and works perfectly.'
        }
      }
    end

    context 'with authenticated user' do
      it 'creates a new review' do
        expect do
          post "/api/v1/apps/#{app.id}/reviews", params: valid_params, headers: headers, as: :json
        end.to change(app.app_reviews, :count).by(1)

        expect_success_response
        data = json_response['data']['review']
        expect(data['rating']).to eq(5)
        expect(data['title']).to eq('Great app!')
      end

      it 'prevents duplicate reviews from same account' do
        create(:app_review, app: app, account: account)
        post "/api/v1/apps/#{app.id}/reviews", params: valid_params, headers: headers, as: :json

        expect_error_response('You have already reviewed this app', 422)
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { review: { rating: 0 } }
        post "/api/v1/apps/#{app.id}/reviews", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/apps/#{app.id}/reviews", params: valid_params, as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/reviews/:id' do
    let(:review) { create(:app_review, app: app, account: account, title: 'Old Title') }
    let(:update_params) do
      {
        review: {
          title: 'Updated Title'
        }
      }
    end

    context 'as review owner' do
      it 'updates the review' do
        patch "/api/v1/reviews/#{review.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']['review']
        expect(data['title']).to eq('Updated Title')
      end
    end

    context 'as different user' do
      let(:other_user) { create(:user, permissions: []) }

      it 'returns forbidden error' do
        patch "/api/v1/reviews/#{review.id}", params: update_params, headers: auth_headers_for(other_user), as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'DELETE /api/v1/reviews/:id' do
    let!(:review) { create(:app_review, app: app, account: account) }

    context 'as review owner' do
      it 'deletes the review' do
        expect do
          delete "/api/v1/reviews/#{review.id}", headers: headers, as: :json
        end.to change(AppReview, :count).by(-1)

        expect_success_response
        expect(json_response['message']).to eq('Review deleted successfully')
      end
    end

    context 'as moderator' do
      it 'can delete any review' do
        other_review = create(:app_review, app: app)
        expect do
          delete "/api/v1/reviews/#{other_review.id}", headers: headers, as: :json
        end.to change(AppReview, :count).by(-1)

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/reviews/:id/vote' do
    let(:review) { create(:app_review, app: app, moderation_status: 'approved') }

    context 'with authenticated user' do
      it 'marks review as helpful' do
        post "/api/v1/reviews/#{review.id}/vote", params: { vote_type: 'helpful' }, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('Marked as helpful')
        data = json_response['data']
        expect(data['user_vote']['is_helpful']).to be true
      end

      it 'marks review as unhelpful' do
        post "/api/v1/reviews/#{review.id}/vote", params: { vote_type: 'unhelpful' }, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('Marked as unhelpful')
        data = json_response['data']
        expect(data['user_vote']['is_helpful']).to be false
      end

      it 'toggles vote when voting same way twice' do
        post "/api/v1/reviews/#{review.id}/vote", params: { vote_type: 'helpful' }, headers: headers, as: :json
        post "/api/v1/reviews/#{review.id}/vote", params: { vote_type: 'helpful' }, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('Vote removed')
        data = json_response['data']
        expect(data['user_vote']).to be_nil
      end
    end
  end

  describe 'POST /api/v1/reviews/:id/flag' do
    let(:review) { create(:app_review, app: app, moderation_status: 'approved') }

    context 'with authenticated user' do
      it 'flags review for moderation' do
        post "/api/v1/reviews/#{review.id}/flag", params: { reason: 'Spam content' }, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('Review flagged for moderation')
      end

      it 'prevents flagging already flagged review' do
        review.update(flagged_for_review: true)
        post "/api/v1/reviews/#{review.id}/flag", params: { reason: 'Spam' }, headers: headers, as: :json

        expect_error_response('Review is already flagged', 422)
      end
    end
  end

  describe 'POST /api/v1/reviews/:id/moderate' do
    let(:review) { create(:app_review, app: app, moderation_status: 'flagged') }

    context 'with reviews.moderate permission' do
      it 'approves flagged review' do
        post "/api/v1/reviews/#{review.id}/moderate", params: { action: 'approve' }, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('Review approved')
      end

      it 'rejects flagged review' do
        post "/api/v1/reviews/#{review.id}/moderate", params: { action: 'reject', reason: 'Spam' }, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('Review rejected')
      end

      it 'removes review' do
        post "/api/v1/reviews/#{review.id}/moderate", params: { action: 'remove', reason: 'Violates policy' }, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('Review removed')
      end

      it 'restores review' do
        post "/api/v1/reviews/#{review.id}/moderate", params: { action: 'restore' }, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('Review restored')
      end

      it 'returns error for invalid action' do
        post "/api/v1/reviews/#{review.id}/moderate", params: { action: 'invalid' }, headers: headers, as: :json

        expect_error_response('Invalid moderation action', 422)
      end
    end

    context 'without reviews.moderate permission' do
      it 'returns forbidden error' do
        post "/api/v1/reviews/#{review.id}/moderate", params: { action: 'approve' }, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end
end
