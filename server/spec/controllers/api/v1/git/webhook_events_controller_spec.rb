# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Git::WebhookEventsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Permission users
  let(:webhook_read_user) { create(:user, account: account, permissions: [ 'git.webhooks.read' ]) }
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  let(:provider) { create(:git_provider, :github) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # WEBHOOK EVENT LISTING
  # =============================================================================

  describe 'GET #index' do
    let!(:event1) { create(:git_webhook_event, :push, git_provider: provider, account: account) }
    let!(:event2) { create(:git_webhook_event, :pull_request, git_provider: provider, account: account) }
    let!(:other_event) { create(:git_webhook_event) }

    context 'with valid permissions' do
      before { sign_in webhook_read_user }

      it 'returns webhook events for the account' do
        get :index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['items'].length).to eq(2)
      end

      it 'excludes events from other accounts' do
        get :index

        json = JSON.parse(response.body)
        event_ids = json['data']['items'].map { |e| e['id'] }
        expect(event_ids).not_to include(other_event.id)
      end

      it 'filters by event_type' do
        get :index, params: { event_type: 'push' }

        json = JSON.parse(response.body)
        expect(json['data']['items'].length).to eq(1)
        expect(json['data']['items'].first['event_type']).to eq('push')
      end

      it 'filters by status' do
        processed_event = create(:git_webhook_event, :processed, git_provider: provider, account: account)

        get :index, params: { status: 'processed' }

        json = JSON.parse(response.body)
        event_ids = json['data']['items'].map { |e| e['id'] }
        expect(event_ids).to include(processed_event.id)
      end

      it 'filters by provider_id' do
        other_provider = create(:git_provider)
        other_provider_event = create(:git_webhook_event, git_provider: other_provider, account: account)

        get :index, params: { provider_id: provider.id }

        json = JSON.parse(response.body)
        event_ids = json['data']['items'].map { |e| e['id'] }
        expect(event_ids).to include(event1.id, event2.id)
        expect(event_ids).not_to include(other_provider_event.id)
      end

      it 'includes pagination metadata' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to be_present
      end

      it 'orders by created_at desc' do
        get :index

        json = JSON.parse(response.body)
        created_ats = json['data']['items'].map { |e| Time.parse(e['created_at']) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        get :index

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #show' do
    let(:event) { create(:git_webhook_event, git_provider: provider, account: account) }

    context 'with valid permissions' do
      before { sign_in webhook_read_user }

      it 'returns event details' do
        get :show, params: { id: event.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['event']['id']).to eq(event.id)
      end

      it 'includes payload' do
        get :show, params: { id: event.id }

        json = JSON.parse(response.body)
        expect(json['data']['event']['payload']).to be_present
      end

      it 'includes processing information' do
        processed_event = create(:git_webhook_event, :processed, git_provider: provider, account: account)

        get :show, params: { id: processed_event.id }

        json = JSON.parse(response.body)
        expect(json['data']['event']['processed_at']).to be_present
        expect(json['data']['event']['processing_result']).to be_present
      end
    end

    context 'when event belongs to another account' do
      let(:other_event) { create(:git_webhook_event) }
      before { sign_in webhook_read_user }

      it 'returns not found error' do
        get :show, params: { id: other_event.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # WEBHOOK EVENT STATISTICS
  # =============================================================================

  describe 'GET #stats' do
    before do
      create_list(:git_webhook_event, 5, :processed, git_provider: provider, account: account)
      create_list(:git_webhook_event, 2, :failed, git_provider: provider, account: account)
      create(:git_webhook_event, :pending, git_provider: provider, account: account)
    end

    context 'with valid permissions' do
      before { sign_in webhook_read_user }

      it 'returns webhook event statistics' do
        get :stats

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['stats']).to include(
          'total_events',
          'processed_count',
          'failed_count',
          'pending_count'
        )
      end

      it 'filters stats by provider' do
        get :stats, params: { provider_id: provider.id }

        expect(response).to have_http_status(:success)
      end

      it 'filters stats by date range' do
        get :stats, params: { days: 7 }

        expect(response).to have_http_status(:success)
      end
    end
  end
end
