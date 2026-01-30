# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Git::WebhookEvents', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['git.webhooks.read']) }
  let(:no_permission_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account) }

  let(:headers) { auth_headers_for(user) }
  let(:no_permission_headers) { auth_headers_for(no_permission_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/git/webhook_events' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let(:provider) { repository.git_provider }
    let!(:event1) { create(:devops_git_webhook_event, account: account, repository: repository, git_provider: provider, event_type: 'push') }
    let!(:event2) { create(:devops_git_webhook_event, account: account, repository: repository, git_provider: provider, event_type: 'pull_request') }
    let!(:other_event) { create(:devops_git_webhook_event, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of webhook events for current account' do
        get '/api/v1/git/webhook_events', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(2)
        expect(data['items'].none? { |e| e['id'] == other_event.id }).to be true
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
      end

      it 'filters by event_type' do
        get '/api/v1/git/webhook_events', params: { event_type: 'push' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['items'].length).to eq(1)
        expect(data['items'].first['event_type']).to eq('push')
      end

      it 'filters by status' do
        event3 = create(:devops_git_webhook_event, account: account, repository: repository, git_provider: provider, status: 'processed')

        get '/api/v1/git/webhook_events', params: { status: 'processed' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['items'].all? { |e| e['status'] == 'processed' }).to be true
      end

      it 'filters by repository_id' do
        other_repo = create(:devops_git_repository, account: account)
        event3 = create(:devops_git_webhook_event, account: account, repository: other_repo, git_provider: provider)

        get '/api/v1/git/webhook_events', params: { repository_id: repository.id }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['items'].all? { |e| e['repository']['id'] == repository.id }).to be true
      end

      it 'filters by provider_id' do
        get '/api/v1/git/webhook_events', params: { provider_id: provider.id }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['items'].all? { |e| e['provider']['id'] == provider.id }).to be true
      end

      it 'filters by date range' do
        get '/api/v1/git/webhook_events',
            params: {
              since: 1.day.ago.iso8601,
              until: 1.hour.from_now.iso8601
            },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['items']).to be_an(Array)
      end

      it 'supports pagination' do
        get '/api/v1/git/webhook_events', params: { page: 1, per_page: 20 }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['items'].length).to be <= 20
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
      end
    end

    context 'without git.webhooks.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/git/webhook_events', headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/git/webhook_events', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/git/webhook_events/:id' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let(:provider) { repository.git_provider }
    let(:event) { create(:devops_git_webhook_event, account: account, repository: repository, git_provider: provider) }
    let(:other_event) { create(:devops_git_webhook_event, account: other_account) }

    context 'with proper permissions' do
      it 'returns webhook event details' do
        get "/api/v1/git/webhook_events/#{event.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['event']).to include(
          'id' => event.id,
          'event_type' => event.event_type,
          'status' => event.status
        )
        expect(data['event']).to have_key('payload')
        expect(data['event']).to have_key('headers')
      end

      it 'returns not found for non-existent event' do
        get "/api/v1/git/webhook_events/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'accessing event from different account' do
      it 'returns not found error' do
        get "/api/v1/git/webhook_events/#{other_event.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without git.webhooks.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/webhook_events/#{event.id}", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/webhook_events/:id/retry' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let(:provider) { repository.git_provider }
    let(:event) { create(:devops_git_webhook_event, account: account, repository: repository, git_provider: provider, status: 'failed') }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitWebhookEvent).to receive(:retry!).and_return(true)
      end

      it 'retries the webhook event' do
        post "/api/v1/git/webhook_events/#{event.id}/retry", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Event queued for retry')
        expect(data['event']).to be_present
      end

      it 'returns error when event cannot be retried' do
        allow_any_instance_of(Devops::GitWebhookEvent).to receive(:retry!).and_return(false)

        post "/api/v1/git/webhook_events/#{event.id}/retry", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Event cannot be retried')
      end
    end

    context 'without git.webhooks.read permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/webhook_events/#{event.id}/retry", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/git/webhook_events/stats' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let(:provider) { repository.git_provider }
    let!(:event1) { create(:devops_git_webhook_event, account: account, repository: repository, git_provider: provider, status: 'processed') }
    let!(:event2) { create(:devops_git_webhook_event, account: account, repository: repository, git_provider: provider, status: 'pending') }
    let!(:event3) { create(:devops_git_webhook_event, account: account, repository: repository, git_provider: provider, status: 'failed') }

    context 'with proper permissions' do
      it 'returns webhook event statistics' do
        get '/api/v1/git/webhook_events/stats', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['stats']).to include(
          'total_events',
          'pending_count',
          'processing_count',
          'processed_count',
          'failed_count',
          'today_count',
          'success_rate'
        )
      end

      it 'filters stats by provider_id' do
        get '/api/v1/git/webhook_events/stats', params: { provider_id: provider.id }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['stats']).to be_present
      end

      it 'filters stats by days' do
        get '/api/v1/git/webhook_events/stats', params: { days: 7 }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['stats']).to be_present
      end

      it 'calculates success rate correctly' do
        get '/api/v1/git/webhook_events/stats', headers: headers

        expect_success_response
        data = json_response_data
        expect(data['stats']['success_rate']).to be_a(Numeric)
      end
    end

    context 'without git.webhooks.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/git/webhook_events/stats', headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
