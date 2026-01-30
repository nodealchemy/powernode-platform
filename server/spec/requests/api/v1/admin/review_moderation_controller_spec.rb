# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::ReviewModerationController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: ['reviews.moderate']) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  # The app_reviews table does not exist in the database.
  # Use stub_const to replace Marketplace::Review and Review::ModerationAction
  # with plain Ruby classes that don't trigger ActiveRecord schema introspection.
  before do
    review_relation = double('ReviewRelation').tap do |rel|
      allow(rel).to receive(:includes).and_return(rel)
      allow(rel).to receive(:flagged).and_return(rel)
      allow(rel).to receive(:pending_moderation).and_return(rel)
      allow(rel).to receive(:where).and_return(rel)
      allow(rel).to receive(:not).and_return(rel)
      allow(rel).to receive(:order).and_return(rel)
      allow(rel).to receive(:limit).and_return(rel)
      allow(rel).to receive(:offset).and_return(rel)
      allow(rel).to receive(:count).and_return(0)
      allow(rel).to receive(:map).and_return([])
      allow(rel).to receive(:each).and_return(rel)
      allow(rel).to receive(:empty?).and_return(true)
      allow(rel).to receive(:any?).and_return(false)
      allow(rel).to receive(:sum).and_return(0)
      allow(rel).to receive(:by_rating).and_return(rel)
      allow(rel).to receive(:by_date_range).and_return(rel)
      allow(rel).to receive(:search_content).and_return(rel)
    end

    mod_action_relation = double('ModerationActionRelation').tap do |rel|
      allow(rel).to receive(:where).and_return(rel)
      allow(rel).to receive(:group).and_return(rel)
      allow(rel).to receive(:joins).and_return(rel)
      allow(rel).to receive(:group_by_day).and_return({})
      allow(rel).to receive(:count).and_return({})
      allow(rel).to receive(:group_by).and_return({})
      allow(rel).to receive(:transform_values).and_return({})
      allow(rel).to receive(:empty?).and_return(true)
      allow(rel).to receive(:sum).and_return(0)
    end

    # Build fake classes with all needed class methods defined.
    # This avoids verify_partial_doubles failures since the methods exist.
    fake_review_class = Class.new do
      class << self
        def includes(*); end
        def flagged; end
        def pending_moderation; end
        def where(*); end
        def find(*); end
        def by_rating(*); end
        def by_date_range(*); end
        def search_content(*); end
      end
    end

    # Now stub the methods to return our doubles
    allow(fake_review_class).to receive(:includes).and_return(review_relation)
    allow(fake_review_class).to receive(:flagged).and_return(review_relation)
    allow(fake_review_class).to receive(:pending_moderation).and_return(review_relation)
    allow(fake_review_class).to receive(:where).and_return(review_relation)
    allow(fake_review_class).to receive(:find).and_raise(ActiveRecord::RecordNotFound.new('not found', 'Review'))

    fake_mod_action_class = Class.new do
      class << self
        def where(*); end
      end
    end
    allow(fake_mod_action_class).to receive(:where).and_return(mod_action_relation)

    stub_const('Marketplace::Review', fake_review_class)
    stub_const('Review::ModerationAction', fake_mod_action_class)

    # Store references for use in individual tests
    @review_relation = review_relation
    @mod_action_relation = mod_action_relation
    @fake_review_class = fake_review_class
    @fake_mod_action_class = fake_mod_action_class
  end

  describe 'GET /api/v1/admin/review_moderation/queue' do
    context 'with reviews moderate permission' do
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
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:serialize_moderation_reviews).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:moderation_queue_summary).and_return({})

        get '/api/v1/admin/review_moderation/queue?status=pending', headers: headers, as: :json

        expect_success_response
      end

      it 'filters by app_id' do
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:serialize_moderation_reviews).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:moderation_queue_summary).and_return({})

        get '/api/v1/admin/review_moderation/queue?app_id=123', headers: headers, as: :json

        expect_success_response
      end

      it 'supports pagination' do
        allow(@review_relation).to receive(:count).and_return(50)
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:serialize_moderation_reviews).and_return([])
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:moderation_queue_summary).and_return({})

        get '/api/v1/admin/review_moderation/queue?page=2&per_page=20', headers: headers, as: :json

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
        review_double = double('Review', id: '1')
        allow(@fake_review_class).to receive(:where).and_return([review_double])

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
        # Override specific counts for analytics tests
        flagged_rel = double('FlaggedRelation', count: 10)
        pending_rel = double('PendingRelation', count: 5)
        where_rel = double('WhereRelation', count: 2)
        allow(@fake_review_class).to receive(:flagged).and_return(flagged_rel)
        allow(@fake_review_class).to receive(:pending_moderation).and_return(pending_rel)
        allow(@fake_review_class).to receive(:where).and_return(where_rel)
        allow_any_instance_of(Api::V1::Admin::ReviewModerationController).to receive(:calculate_avg_resolution_time).and_return(2.5)
      end

      it 'returns moderation analytics' do
        get '/api/v1/admin/review_moderation/analytics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('queue_stats', 'moderation_actions')
      end

      it 'supports custom time range' do
        get '/api/v1/admin/review_moderation/analytics?days_back=60', headers: headers, as: :json

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
        allow(@fake_review_class).to receive(:find).and_return(review)

        get '/api/v1/admin/review_moderation/history/1', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('review', 'actions')
      end

      it 'returns error when review not found' do
        get '/api/v1/admin/review_moderation/history/999', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/admin/review_moderation/update_settings' do
    context 'with reviews moderate permission' do
      it 'updates moderation settings' do
        allow(AdminSetting).to receive(:set)

        post '/api/v1/admin/review_moderation/update_settings',
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
