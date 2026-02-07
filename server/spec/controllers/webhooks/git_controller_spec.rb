# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::GitController, type: :controller do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
  let(:repository) { create(:git_repository, :with_webhook, credential: credential, account: account) }
  let(:webhook_secret) { repository.webhook_secret }

  let(:worker_api_client) { instance_double(WorkerApiClient) }

  before do
    allow(WorkerApiClient).to receive(:new).and_return(worker_api_client)
    allow(worker_api_client).to receive(:queue_git_webhook_processing)
    @request.headers['Content-Type'] = 'application/json'
  end

  # =============================================================================
  # GITHUB WEBHOOKS
  # =============================================================================

  describe 'POST #handle (GitHub)' do
    let(:github_push_payload) do
      {
        repository: { full_name: repository.full_name },
        ref: 'refs/heads/main',
        after: 'abc123def456',
        head_commit: { id: 'abc123def456' },
        sender: { login: 'testuser', id: 12345 }
      }.to_json
    end

    def github_signature(body, secret)
      "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, body)}"
    end

    context 'with valid signature' do
      before do
        @request.headers['X-GitHub-Event'] = 'push'
        @request.headers['X-GitHub-Delivery'] = SecureRandom.uuid
        @request.headers['X-Hub-Signature-256'] = github_signature(github_push_payload, webhook_secret)
      end

      it 'creates webhook event and queues job' do
        expect(worker_api_client).to receive(:queue_git_webhook_processing).with(kind_of(String))

        expect {
          post :handle, params: { provider_type: 'github' }, body: github_push_payload, as: :json
        }.to change(Devops::GitWebhookEvent, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['received']).to be true
        expect(json['data']['event_id']).to be_present
      end

      it 'extracts event data correctly' do
        post :handle, params: { provider_type: 'github' }, body: github_push_payload, as: :json

        event = Devops::GitWebhookEvent.last
        expect(event.event_type).to eq('push')
        expect(event.sender_username).to eq('testuser')
        expect(event.ref).to eq('refs/heads/main')
        expect(event.sha).to eq('abc123def456')
        expect(event.status).to eq('pending')
      end
    end

    context 'with invalid signature' do
      before do
        @request.headers['X-GitHub-Event'] = 'push'
        @request.headers['X-Hub-Signature-256'] = 'sha256=invalid_signature'
      end

      it 'returns unauthorized error' do
        post :handle, params: { provider_type: 'github' }, body: github_push_payload, as: :json

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Invalid signature')
      end

      it 'does not create webhook event' do
        expect {
          post :handle, params: { provider_type: 'github' }, body: github_push_payload, as: :json
        }.not_to change(Devops::GitWebhookEvent, :count)
      end
    end

    context 'with missing signature' do
      before do
        @request.headers['X-GitHub-Event'] = 'push'
        # No X-Hub-Signature-256 header
      end

      it 'returns unauthorized error' do
        post :handle, params: { provider_type: 'github' }, body: github_push_payload, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with unknown repository' do
      let(:unknown_payload) do
        { repository: { full_name: 'unknown/repo' } }.to_json
      end

      before do
        @request.headers['X-GitHub-Event'] = 'push'
        @request.headers['X-Hub-Signature-256'] = github_signature(unknown_payload, 'secret')
      end

      it 'returns not found error' do
        post :handle, params: { provider_type: 'github' }, body: unknown_payload, as: :json

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Repository not found')
      end
    end

    context 'with pull request event' do
      let(:pr_payload) do
        {
          repository: { full_name: repository.full_name },
          action: 'opened',
          pull_request: {
            head: { sha: 'pr_sha_123' },
            number: 42
          },
          sender: { login: 'contributor', id: 99999 }
        }.to_json
      end

      before do
        @request.headers['X-GitHub-Event'] = 'pull_request'
        @request.headers['X-GitHub-Delivery'] = SecureRandom.uuid
        @request.headers['X-Hub-Signature-256'] = github_signature(pr_payload, webhook_secret)
      end

      it 'extracts pull request data' do
        post :handle, params: { provider_type: 'github' }, body: pr_payload, as: :json

        expect(response).to have_http_status(:ok)
        event = Devops::GitWebhookEvent.last
        expect(event.event_type).to eq('pull_request')
        expect(event.action).to eq('opened')
        expect(event.sha).to eq('pr_sha_123')
      end
    end
  end

  # =============================================================================
  # GITLAB WEBHOOKS
  # =============================================================================

  describe 'POST #handle (GitLab)' do
    let(:gitlab_provider) { create(:git_provider, :gitlab) }
    let(:gitlab_credential) { create(:git_provider_credential, provider: gitlab_provider, account: account) }
    let(:gitlab_repository) { create(:git_repository, :with_webhook, credential: gitlab_credential, account: account) }
    let(:gitlab_secret) { gitlab_repository.webhook_secret }

    let(:gitlab_push_payload) do
      {
        project: { path_with_namespace: gitlab_repository.full_name },
        ref: 'refs/heads/main',
        after: 'gitlab_sha_456',
        user: { username: 'gitlab_user', id: 1001 }
      }.to_json
    end

    context 'with valid token' do
      before do
        @request.headers['X-Gitlab-Event'] = 'Push Hook'
        @request.headers['X-Gitlab-Event-UUID'] = SecureRandom.uuid
        @request.headers['X-Gitlab-Token'] = gitlab_secret
      end

      it 'creates webhook event' do
        expect {
          post :handle, params: { provider_type: 'gitlab' }, body: gitlab_push_payload, as: :json
        }.to change(Devops::GitWebhookEvent, :count).by(1)

        expect(response).to have_http_status(:ok)
      end

      it 'normalizes event type' do
        post :handle, params: { provider_type: 'gitlab' }, body: gitlab_push_payload, as: :json

        event = Devops::GitWebhookEvent.last
        expect(event.event_type).to eq('push')
        expect(event.sender_username).to eq('gitlab_user')
      end
    end

    context 'with invalid token' do
      before do
        @request.headers['X-Gitlab-Event'] = 'Push Hook'
        @request.headers['X-Gitlab-Token'] = 'wrong_token'
      end

      it 'returns unauthorized error' do
        post :handle, params: { provider_type: 'gitlab' }, body: gitlab_push_payload, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with merge request event' do
      let(:mr_payload) do
        {
          project: { path_with_namespace: gitlab_repository.full_name },
          object_attributes: {
            action: 'open',
            last_commit: { id: 'mr_commit_sha' }
          },
          user: { username: 'mr_author', id: 2002 }
        }.to_json
      end

      before do
        @request.headers['X-Gitlab-Event'] = 'Merge Request Hook'
        @request.headers['X-Gitlab-Event-UUID'] = SecureRandom.uuid
        @request.headers['X-Gitlab-Token'] = gitlab_secret
      end

      it 'extracts merge request data' do
        post :handle, params: { provider_type: 'gitlab' }, body: mr_payload, as: :json

        expect(response).to have_http_status(:ok)
        event = Devops::GitWebhookEvent.last
        expect(event.event_type).to eq('merge_request')
        expect(event.action).to eq('open')
        expect(event.sha).to eq('mr_commit_sha')
      end
    end
  end

  # =============================================================================
  # GITEA WEBHOOKS
  # =============================================================================

  describe 'POST #handle (Gitea)' do
    let(:gitea_provider) { create(:git_provider, :gitea) }
    let(:gitea_credential) { create(:git_provider_credential, provider: gitea_provider, account: account) }
    let(:gitea_repository) { create(:git_repository, :with_webhook, credential: gitea_credential, account: account) }
    let(:gitea_secret) { gitea_repository.webhook_secret }

    let(:gitea_push_payload) do
      {
        repository: { full_name: gitea_repository.full_name },
        ref: 'refs/heads/develop',
        after: 'gitea_sha_789',
        sender: { login: 'gitea_user', id: 3003 }
      }.to_json
    end

    def gitea_signature(body, secret)
      "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, body)}"
    end

    context 'with X-Gitea-Signature (raw HMAC)' do
      before do
        @request.headers['X-Gitea-Event'] = 'push'
        @request.headers['X-Gitea-Delivery'] = SecureRandom.uuid
        # Gitea can use raw HMAC without sha256= prefix
        @request.headers['X-Gitea-Signature'] = OpenSSL::HMAC.hexdigest('sha256', gitea_secret, gitea_push_payload)
      end

      it 'verifies raw HMAC signature' do
        post :handle, params: { provider_type: 'gitea' }, body: gitea_push_payload, as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with X-Hub-Signature-256 (GitHub-compatible)' do
      before do
        @request.headers['X-Gitea-Event'] = 'push'
        @request.headers['X-Gitea-Delivery'] = SecureRandom.uuid
        @request.headers['X-Hub-Signature-256'] = gitea_signature(gitea_push_payload, gitea_secret)
      end

      it 'verifies GitHub-style signature' do
        post :handle, params: { provider_type: 'gitea' }, body: gitea_push_payload, as: :json

        expect(response).to have_http_status(:ok)
      end

      it 'extracts event data correctly' do
        post :handle, params: { provider_type: 'gitea' }, body: gitea_push_payload, as: :json

        event = Devops::GitWebhookEvent.last
        expect(event.event_type).to eq('push')
        expect(event.sender_username).to eq('gitea_user')
        expect(event.ref).to eq('refs/heads/develop')
        expect(event.sha).to eq('gitea_sha_789')
      end
    end

    context 'with invalid signature' do
      before do
        @request.headers['X-Gitea-Event'] = 'push'
        @request.headers['X-Gitea-Signature'] = 'invalid_signature'
      end

      it 'returns unauthorized error' do
        post :handle, params: { provider_type: 'gitea' }, body: gitea_push_payload, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # =============================================================================
  # UNKNOWN PROVIDER
  # =============================================================================

  describe 'POST #handle (Unknown Provider)' do
    it 'returns bad request for unknown provider' do
      post :handle, params: { provider_type: 'bitbucket' }, body: '{}', as: :json

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Unknown provider')
    end
  end

  # =============================================================================
  # ERROR HANDLING
  # =============================================================================

  describe 'error handling' do
    let(:payload) do
      { repository: { full_name: repository.full_name } }.to_json
    end

    before do
      @request.headers['X-GitHub-Event'] = 'push'
      @request.headers['X-Hub-Signature-256'] = github_signature(payload, webhook_secret)
    end

    def github_signature(body, secret)
      "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, body)}"
    end

    context 'when job queueing fails' do
      before do
        allow(worker_api_client).to receive(:queue_git_webhook_processing)
          .and_raise(WorkerApiClient::ApiError, 'Worker API connection failed')
      end

      it 'returns success but marks event as queued_failed' do
        expect {
          post :handle, params: { provider_type: 'github' }, body: payload, as: :json
        }.to change(Devops::GitWebhookEvent, :count).by(1)

        expect(response).to have_http_status(:ok)
        event = Devops::GitWebhookEvent.last
        expect(event.status).to eq('queued_failed')
        expect(event.error_message).to include('Worker API connection failed')
      end
    end
  end

  # =============================================================================
  # HEADER EXTRACTION
  # =============================================================================

  describe 'header extraction' do
    let(:payload) do
      {
        repository: { full_name: repository.full_name },
        sender: { login: 'testuser', id: 123 }
      }.to_json
    end

    before do
      @request.headers['X-GitHub-Event'] = 'push'
      @request.headers['X-GitHub-Delivery'] = 'delivery-uuid-123'
      @request.headers['X-GitHub-Hook-ID'] = 'hook-456'
      @request.headers['User-Agent'] = 'GitHub-Hookshot/abc123'
      @request.headers['X-Hub-Signature-256'] = github_signature(payload, webhook_secret)
    end

    def github_signature(body, secret)
      "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, body)}"
    end

    it 'captures relevant headers in event' do
      post :handle, params: { provider_type: 'github' }, body: payload, as: :json

      event = Devops::GitWebhookEvent.last
      expect(event.headers).to include('X-GitHub-Event' => 'push')
      expect(event.headers).to include('X-GitHub-Delivery' => 'delivery-uuid-123')
      expect(event.headers).to include('X-GitHub-Hook-ID' => 'hook-456')
      expect(event.headers).to include('User-Agent' => 'GitHub-Hookshot/abc123')
    end
  end
end
