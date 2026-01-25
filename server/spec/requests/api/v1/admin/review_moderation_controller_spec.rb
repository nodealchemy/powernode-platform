# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::ReviewModerationController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: ['reviews.moderate']) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  describe 'GET /api/v1/admin/review_moderation/queue' do
    context 'with reviews moderate permission' do
      before do
        # Create test app and reviews (assuming these models exist)
        # Skip actual database creation in this spec for brevity
        allow(Marketplace::Review).to receive_message_chain(:includes, :flagged, :order, :count).and_return(0)
        allow(Marketplace::Review).to receive_message_chain(:includes, :flagged, :order, :limit, :offset).and_return([])
      end

      it 'returns moderation queue' do
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:serialize_moderation_reviews).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:moderation_queue_summary).and_return(
          { total_flagged: 0, total_pending: 0 }
        )

        get '/api/v1/admin/review_moderation/queue', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('reviews', 'pagination', 'summary')
      end

      it 'filters by status' do
        allow(Marketplace::Review).to receive_message_chain(:includes, :pending_moderation, :order, :count).and_return(0)
        allow(Marketplace::Review).to receive_message_chain(:includes, :pending_moderation, :order, :limit, :offset).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:serialize_moderation_reviews).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:moderation_queue_summary).and_return({})

        get '/api/v1/admin/review_moderation/queue', params: { status: 'pending' }, headers: headers, as: :json

        expect_success_response
      end

      it 'filters by app_id' do
        allow(Marketplace::Review).to receive_message_chain(:includes, :flagged, :where, :order, :count).and_return(0)
        allow(Marketplace::Review).to receive_message_chain(:includes, :flagged, :where, :order, :limit, :offset).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:serialize_moderation_reviews).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:moderation_queue_summary).and_return({})

        get '/api/v1/admin/review_moderation/queue', params: { app_id: '123' }, headers: headers, as: :json

        expect_success_response
      end

      it 'supports pagination' do
        allow(Marketplace::Review).to receive_message_chain(:includes, :flagged, :order, :count).and_return(50)
        allow(Marketplace::Review).to receive_message_chain(:includes, :flagged, :order, :limit, :offset).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:serialize_moderation_reviews).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:moderation_queue_summary).and_return({})

        get '/api/v1/admin/review_moderation/queue', params: { page: 2, per_page: 20 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']['page']).to eq(2)
        expect(data['pagination']['per_page']).to eq(20)
      end
    end

    context 'without reviews moderate permission' do
      it 'returns forbidden error' do
        get '/api/v1/admin/review_moderation/queue', headers: non_admin_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/admin/review_moderation/bulk_action' do
    context 'with reviews moderate permission' do
      it 'returns error when no reviews selected' do
        post '/api/v1/admin/review_moderation/bulk_action',
             params: { review_ids: [], action: 'approve' }.to_json,
             headers: headers

        expect_error_response('No reviews selected', 422)
      end

      it 'returns error for invalid action' do
        allow(Marketplace::Review).to receive(:where).and_return([
          double('Review', id: '1')
        ])

        post '/api/v1/admin/review_moderation/bulk_action',
             params: { review_ids: ['1'], action: 'invalid_action' }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data['failed']).to be > 0
      end
    end
  end

  describe 'GET /api/v1/admin/review_moderation/analytics' do
    context 'with reviews moderate permission' do
      before do
        allow(Marketplace::Review).to receive_message_chain(:flagged, :count).and_return(10)
        allow(Marketplace::Review).to receive_message_chain(:pending_moderation, :count).and_return(5)
        allow(Marketplace::Review).to receive_message_chain(:where, :count).and_return(2)
        allow(Review::ModerationAction).to receive_message_chain(:where, :group, :count).and_return({})
        allow(Review::ModerationAction).to receive_message_chain(:where, :joins, :group, :count).and_return({})
        allow(Review::ModerationAction).to receive_message_chain(:where, :group_by_day, :count).and_return({})
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:calculate_avg_resolution_time).and_return(2.5)
      end

      it 'returns moderation analytics' do
        get '/api/v1/admin/review_moderation/analytics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('queue_stats', 'moderation_actions')
      end

      it 'supports custom time range' do
        get '/api/v1/admin/review_moderation/analytics', params: { days_back: 60 }, headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/admin/review_moderation/history/:review_id' do
    context 'with reviews moderate permission' do
      it 'returns moderation history for a review' do
        review = double('Review',
          id: '1',
          display_title: 'Test Review',
          rating: 4,
          moderation_status: 'approved',
          created_at: Time.current,
          review_moderation_actions: double('Actions', includes: double('IncludedActions', order: []))
        )
        allow(Marketplace::Review).to receive(:find).and_return(review)

        get '/api/v1/admin/review_moderation/history/1', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('review', 'actions')
      end

      it 'returns error when review not found' do
        allow(Marketplace::Review).to receive(:find).and_raise(ActiveRecord::RecordNotFound)

        get '/api/v1/admin/review_moderation/history/999', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/admin/review_moderation/settings' do
    context 'with reviews moderate permission' do
      it 'updates moderation settings' do
        allow(AdminSetting).to receive(:set)

        post '/api/v1/admin/review_moderation/settings',
             params: {
               settings: {
                 auto_flag_threshold: 2.5,
                 auto_approve_threshold: 4.5,
                 spam_keywords: ['spam', 'fake'],
                 require_verification_for_reviews: true
               }
             }.to_json,
             headers: headers

        expect_success_response
        expect(AdminSetting).to have_received(:set).at_least(:once)
      end
    end
  end

  describe 'GET /api/v1/admin/review_moderation/settings' do
    context 'with reviews moderate permission' do
      it 'returns current moderation settings' do
        allow(AdminSetting).to receive(:get).with('review_auto_flag_threshold', '2.0').and_return('2.0')
        allow(AdminSetting).to receive(:get).with('review_auto_approve_threshold', '4.0').and_return('4.0')
        allow(AdminSetting).to receive(:get).with('review_spam_keywords', '').and_return('spam,fake')
        allow(AdminSetting).to receive(:get).with('require_verification_for_reviews', 'false').and_return('true')

        get '/api/v1/admin/review_moderation/settings', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('settings')
        expect(data['settings']).to include(
          'auto_flag_threshold',
          'auto_approve_threshold',
          'spam_keywords',
          'require_verification_for_reviews'
        )
      end
    end
  end
end
