# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::ReviewResponses', type: :request do
  let(:account) { create(:account) }
  let(:app_owner_account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:moderator) { create(:user, account: account, permissions: ['reviews.moderate']) }
  let(:app_owner) { create(:user, account: app_owner_account, permissions: []) }

  let(:headers) { auth_headers_for(user) }
  let(:moderator_headers) { auth_headers_for(moderator) }
  let(:owner_headers) { auth_headers_for(app_owner) }

  let(:marketplace_app) { create(:marketplace_definition, account: app_owner_account) }
  let!(:app_review) do
    Marketplace::Review.create!(
      app: marketplace_app,
      account: account,
      rating: 4,
      title: 'Great app',
      content: 'Really useful and well designed',
      moderation_status: 'approved'
    )
  end

  let!(:review_response) do
    Review::Response.create!(
      app_review: app_review,
      account: app_owner_account,
      content: 'Thank you for your feedback!',
      response_type: 'vendor_response',
      status: 'approved',
      approved_at: Time.current,
      approved_by: app_owner_account
    )
  end

  describe 'GET /api/v1/app_reviews/:app_review_id/responses' do
    let!(:pending_response) do
      Review::Response.create!(
        app_review: app_review,
        account: account,
        content: 'This is a pending response',
        response_type: 'customer_service',
        status: 'pending'
      )
    end

    context 'as a regular user' do
      it 'returns only approved responses' do
        get "/api/v1/app_reviews/#{app_review.id}/responses", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['responses']).to be_an(Array)
        expect(data['responses'].length).to eq(1)
        expect(data['responses'].first['status']).to eq('approved')
        expect(data['review']).to include('id' => app_review.id)
      end

      it 'sorts by newest first by default' do
        get "/api/v1/app_reviews/#{app_review.id}/responses", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['responses'].first['id']).to eq(review_response.id)
      end

      it 'sorts by oldest when requested' do
        get "/api/v1/app_reviews/#{app_review.id}/responses", params: { sort_by: 'oldest' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['responses'].first['id']).to eq(review_response.id)
      end
    end

    context 'as a moderator' do
      it 'returns all responses when no filter specified' do
        get "/api/v1/app_reviews/#{app_review.id}/responses", headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['responses'].length).to eq(2)
      end

      it 'filters by status when specified' do
        get "/api/v1/app_reviews/#{app_review.id}/responses",
            params: { status: 'pending' },
            headers: moderator_headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['responses'].length).to eq(1)
        expect(data['responses'].first['status']).to eq('pending')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/app_reviews/#{app_review.id}/responses", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/review_responses/:id' do
    context 'with authentication' do
      it 'returns review response details' do
        get "/api/v1/review_responses/#{review_response.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['response']).to include(
          'id' => review_response.id,
          'content' => 'Thank you for your feedback!',
          'response_type' => 'vendor_response',
          'status' => 'approved'
        )
        expect(data['response']).to have_key('approved_at')
        expect(data['response']).to have_key('metadata')
      end

      it 'returns not found for non-existent response' do
        get "/api/v1/review_responses/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Couldn\'t find Review::Response', 500)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/review_responses/#{review_response.id}", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/app_reviews/:app_review_id/responses' do
    let(:valid_params) do
      {
        response: {
          content: 'Thank you for the detailed review!',
          response_type: 'vendor_response'
        }
      }
    end

    context 'as app owner' do
      it 'creates a response with auto-approval' do
        expect {
          post "/api/v1/app_reviews/#{app_review.id}/responses",
               params: valid_params,
               headers: owner_headers,
               as: :json
        }.to change { app_review.responses.count }.by(1)

        expect_success_response
        data = json_response_data
        expect(data['response']['content']).to eq('Thank you for the detailed review!')
        expect(data['response']['status']).to eq('approved')
        expect(data['message']).to eq('Response posted successfully')
      end
    end

    context 'as regular user' do
      it 'creates a response pending approval' do
        expect {
          post "/api/v1/app_reviews/#{app_review.id}/responses",
               params: valid_params,
               headers: headers,
               as: :json
        }.to change { app_review.responses.count }.by(1)

        expect_success_response
        data = json_response_data
        expect(data['response']['status']).to eq('pending')
        expect(data['message']).to eq('Response submitted for approval')
      end

      it 'returns validation errors for invalid content' do
        invalid_params = valid_params.deep_merge(response: { content: 'short' })

        post "/api/v1/app_reviews/#{app_review.id}/responses",
             params: invalid_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns validation errors for missing response_type' do
        invalid_params = valid_params.deep_merge(response: { response_type: nil })

        post "/api/v1/app_reviews/#{app_review.id}/responses",
             params: invalid_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/app_reviews/#{app_review.id}/responses",
             params: valid_params,
             as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/review_responses/:id' do
    let(:user_response) do
      Review::Response.create!(
        app_review: app_review,
        account: account,
        content: 'Original content here',
        response_type: 'customer_service',
        status: 'approved',
        approved_at: Time.current,
        approved_by: account
      )
    end

    let(:update_params) do
      {
        response: {
          content: 'Updated content for the response'
        }
      }
    end

    context 'as response owner' do
      it 'updates the response' do
        patch "/api/v1/review_responses/#{user_response.id}",
              params: update_params,
              headers: headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['response']['content']).to eq('Updated content for the response')
        expect(data['message']).to eq('Response updated successfully')
      end

      it 'resets to pending if content changed and not auto-approved' do
        patch "/api/v1/review_responses/#{user_response.id}",
              params: update_params,
              headers: headers,
              as: :json

        user_response.reload
        expect(user_response.status).to eq('pending')
        expect(user_response.approved_at).to be_nil
      end
    end

    context 'as moderator' do
      it 'can update any response' do
        patch "/api/v1/review_responses/#{review_response.id}",
              params: update_params,
              headers: moderator_headers,
              as: :json

        expect_success_response
      end
    end

    context 'as different user' do
      let(:other_user) { create(:user, account: create(:account), permissions: []) }
      let(:other_headers) { auth_headers_for(other_user) }

      it 'returns forbidden error' do
        patch "/api/v1/review_responses/#{review_response.id}",
              params: update_params,
              headers: other_headers,
              as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'DELETE /api/v1/review_responses/:id' do
    let(:user_response) do
      Review::Response.create!(
        app_review: app_review,
        account: account,
        content: 'Response to delete',
        response_type: 'customer_service',
        status: 'pending'
      )
    end

    context 'as response owner' do
      it 'deletes the response' do
        expect {
          delete "/api/v1/review_responses/#{user_response.id}", headers: headers, as: :json
        }.to change { Review::Response.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Response deleted successfully')
      end
    end

    context 'as moderator' do
      it 'can delete any response' do
        expect {
          delete "/api/v1/review_responses/#{review_response.id}", headers: moderator_headers, as: :json
        }.to change { Review::Response.count }.by(-1)

        expect_success_response
      end
    end

    context 'as different user' do
      let(:other_user) { create(:user, account: create(:account), permissions: []) }
      let(:other_headers) { auth_headers_for(other_user) }

      it 'returns forbidden error' do
        delete "/api/v1/review_responses/#{review_response.id}", headers: other_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/review_responses/:id/approve' do
    let(:pending_response) do
      Review::Response.create!(
        app_review: app_review,
        account: account,
        content: 'Pending response content',
        response_type: 'customer_service',
        status: 'pending'
      )
    end

    context 'as moderator' do
      it 'approves the response' do
        post "/api/v1/review_responses/#{pending_response.id}/approve",
             headers: moderator_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['response']['status']).to eq('approved')
        expect(data['message']).to eq('Response approved successfully')

        pending_response.reload
        expect(pending_response.status).to eq('approved')
        expect(pending_response.approved_at).to be_present
      end

      it 'returns error when response already approved' do
        post "/api/v1/review_responses/#{review_response.id}/approve",
             headers: moderator_headers,
             as: :json

        expect_error_response('Response is already approved', 422)
      end
    end

    context 'as regular user' do
      it 'returns forbidden error' do
        post "/api/v1/review_responses/#{pending_response.id}/approve",
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/review_responses/#{pending_response.id}/approve", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/review_responses/:id/reject' do
    let(:pending_response) do
      Review::Response.create!(
        app_review: app_review,
        account: account,
        content: 'Pending response content',
        response_type: 'customer_service',
        status: 'pending'
      )
    end

    let(:reject_params) do
      {
        reason: 'Inappropriate content'
      }
    end

    context 'as moderator' do
      it 'rejects the response' do
        post "/api/v1/review_responses/#{pending_response.id}/reject",
             params: reject_params,
             headers: moderator_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['response']['status']).to eq('rejected')
        expect(data['message']).to eq('Response rejected')

        pending_response.reload
        expect(pending_response.status).to eq('rejected')
      end

      it 'returns error when response already rejected' do
        pending_response.update!(status: 'rejected')

        post "/api/v1/review_responses/#{pending_response.id}/reject",
             params: reject_params,
             headers: moderator_headers,
             as: :json

        expect_error_response('Response is already rejected', 422)
      end
    end

    context 'as regular user' do
      it 'returns forbidden error' do
        post "/api/v1/review_responses/#{pending_response.id}/reject",
             params: reject_params,
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/review_responses/#{pending_response.id}/reject",
             params: reject_params,
             as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end
end
