# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Git::GithubApiClient do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, :github, provider: provider, account: account) }
  let(:client) { described_class.new(credential) }

  before do
    allow(credential).to receive(:access_token).and_return('test_github_token')
  end

  describe '#test_connection' do
    context 'when connection is successful' do
      before do
        stub_request(:get, 'https://api.github.com/user')
          .to_return(
            status: 200,
            body: { login: 'testuser', id: 123, avatar_url: 'https://example.com/avatar.png' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success with user data' do
        result = client.test_connection

        expect(result[:success]).to be true
        expect(result[:user][:login]).to eq('testuser')
        expect(result[:username]).to eq('testuser')
      end
    end

    context 'when authentication fails' do
      before do
        stub_request(:get, 'https://api.github.com/user')
          .to_return(
            status: 401,
            body: { message: 'Bad credentials' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises authentication error' do
        expect { client.test_connection }.to raise_error(Git::ApiClient::AuthenticationError)
      end
    end
  end

  describe '#list_repositories' do
    before do
      stub_request(:get, /api\.github\.com\/user\/repos/)
        .to_return(
          status: 200,
          body: [
            { id: 1, name: 'repo1', full_name: 'user/repo1', private: false },
            { id: 2, name: 'repo2', full_name: 'user/repo2', private: true }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of repositories' do
      repos = client.list_repositories

      expect(repos.length).to eq(2)
      expect(repos.first[:name]).to eq('repo1')
    end
  end

  describe '#get_repository' do
    let(:repo_response) do
      {
        id: 123,
        name: 'test-repo',
        full_name: 'owner/test-repo',
        description: 'A test repository',
        private: false,
        default_branch: 'main',
        clone_url: 'https://github.com/owner/test-repo.git',
        ssh_url: 'git@github.com:owner/test-repo.git',
        html_url: 'https://github.com/owner/test-repo',
        stargazers_count: 100,
        forks_count: 25,
        open_issues_count: 5
      }
    end

    before do
      stub_request(:get, 'https://api.github.com/repos/owner/test-repo')
        .to_return(
          status: 200,
          body: repo_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns repository details' do
      repo = client.get_repository('owner', 'test-repo')

      expect(repo[:name]).to eq('test-repo')
      expect(repo[:full_name]).to eq('owner/test-repo')
      expect(repo[:stargazers_count]).to eq(100)
    end
  end

  describe '#list_branches' do
    before do
      stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/branches/)
        .to_return(
          status: 200,
          body: [
            { name: 'main', protected: true },
            { name: 'develop', protected: false }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of branches' do
      branches = client.list_branches('owner', 'repo')

      expect(branches.length).to eq(2)
      expect(branches.first[:name]).to eq('main')
    end
  end

  describe '#list_commits' do
    before do
      stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/commits/)
        .to_return(
          status: 200,
          body: [
            {
              sha: 'abc123',
              commit: { message: 'Initial commit', author: { name: 'Test', date: '2024-01-01T00:00:00Z' } },
              author: { login: 'testuser' }
            }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of commits' do
      commits = client.list_commits('owner', 'repo', sha: 'main')

      expect(commits.length).to eq(1)
      expect(commits.first[:sha]).to eq('abc123')
    end
  end

  describe '#list_pull_requests' do
    before do
      stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/pulls/)
        .to_return(
          status: 200,
          body: [
            {
              number: 1,
              title: 'Feature PR',
              state: 'open',
              user: { login: 'testuser' }
            }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of pull requests' do
      prs = client.list_pull_requests('owner', 'repo', state: 'open')

      expect(prs.length).to eq(1)
      expect(prs.first[:number]).to eq(1)
    end
  end

  # =============================================================================
  # WEBHOOK MANAGEMENT
  # =============================================================================

  describe '#create_webhook' do
    let(:webhook_url) { 'https://example.com/webhooks/git/github' }

    before do
      stub_request(:post, 'https://api.github.com/repos/owner/repo/hooks')
        .to_return(
          status: 201,
          body: {
            id: 12345,
            active: true,
            events: %w[push pull_request]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates a webhook' do
      result = client.create_webhook('owner', 'repo', webhook_url, events: %w[push pull_request])

      expect(result[:id]).to eq(12345)
      expect(result[:active]).to be true
    end
  end

  describe '#delete_webhook' do
    before do
      stub_request(:delete, 'https://api.github.com/repos/owner/repo/hooks/12345')
        .to_return(status: 204)
    end

    it 'deletes the webhook' do
      result = client.delete_webhook('owner', 'repo', '12345')

      expect(result[:success]).to be true
    end
  end

  # =============================================================================
  # CI/CD - GITHUB ACTIONS
  # =============================================================================

  describe '#list_workflow_runs' do
    before do
      stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/actions\/runs/)
        .to_return(
          status: 200,
          body: {
            total_count: 2,
            workflow_runs: [
              {
                id: 111,
                name: 'CI',
                status: 'completed',
                conclusion: 'success',
                run_number: 42
              },
              {
                id: 222,
                name: 'CI',
                status: 'in_progress',
                conclusion: nil,
                run_number: 43
              }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of workflow runs' do
      runs = client.list_workflow_runs('owner', 'repo')

      expect(runs[:total_count]).to eq(2)
      expect(runs[:workflow_runs].length).to eq(2)
    end
  end

  describe '#get_workflow_run' do
    before do
      stub_request(:get, 'https://api.github.com/repos/owner/repo/actions/runs/111')
        .to_return(
          status: 200,
          body: {
            id: 111,
            name: 'CI',
            status: 'completed',
            conclusion: 'success'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns workflow run details' do
      run = client.get_workflow_run('owner', 'repo', 111)

      expect(run[:id]).to eq(111)
      expect(run[:conclusion]).to eq('success')
    end
  end

  describe '#list_workflow_jobs' do
    before do
      stub_request(:get, 'https://api.github.com/repos/owner/repo/actions/runs/111/jobs')
        .to_return(
          status: 200,
          body: {
            total_count: 2,
            jobs: [
              { id: 1, name: 'build', status: 'completed', conclusion: 'success' },
              { id: 2, name: 'test', status: 'completed', conclusion: 'success' }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of jobs for workflow run' do
      jobs = client.list_workflow_jobs('owner', 'repo', 111)

      expect(jobs[:total_count]).to eq(2)
      expect(jobs[:jobs].length).to eq(2)
    end
  end

  describe '#get_job_logs' do
    before do
      stub_request(:get, 'https://api.github.com/repos/owner/repo/actions/jobs/1/logs')
        .to_return(status: 200, body: "Running tests...\nAll tests passed!")
    end

    it 'returns job logs' do
      logs = client.get_job_logs('owner', 'repo', 1)

      expect(logs).to include('Running tests')
    end
  end

  describe '#trigger_workflow' do
    before do
      stub_request(:post, 'https://api.github.com/repos/owner/repo/actions/workflows/ci.yml/dispatches')
        .to_return(status: 204)
    end

    it 'triggers a workflow dispatch' do
      result = client.trigger_workflow('owner', 'repo', 'ci.yml', 'main')

      expect(result[:success]).to be true
    end
  end

  describe '#cancel_workflow_run' do
    before do
      stub_request(:post, 'https://api.github.com/repos/owner/repo/actions/runs/111/cancel')
        .to_return(status: 202)
    end

    it 'cancels the workflow run' do
      result = client.cancel_workflow_run('owner', 'repo', 111)

      expect(result[:success]).to be true
    end
  end

  describe '#rerun_workflow' do
    before do
      stub_request(:post, 'https://api.github.com/repos/owner/repo/actions/runs/111/rerun')
        .to_return(status: 201)
    end

    it 'reruns the workflow' do
      result = client.rerun_workflow('owner', 'repo', 111)

      expect(result[:success]).to be true
    end
  end

  # =============================================================================
  # WEBHOOK SIGNATURE VERIFICATION
  # =============================================================================

  describe '#verify_webhook_signature' do
    let(:secret) { 'webhook_secret_123' }
    let(:payload) { '{"action":"push"}' }

    it 'verifies valid signature' do
      signature = 'sha256=' + OpenSSL::HMAC.hexdigest('SHA256', secret, payload)

      result = client.verify_webhook_signature(payload, signature, secret)

      expect(result).to be true
    end

    it 'rejects invalid signature' do
      result = client.verify_webhook_signature(payload, 'sha256=invalid', secret)

      expect(result).to be false
    end
  end

  # =============================================================================
  # COMMIT STATUSES
  # =============================================================================

  describe '#get_commit_statuses' do
    before do
      stub_request(:get, 'https://api.github.com/repos/owner/repo/commits/abc123/statuses')
        .to_return(
          status: 200,
          body: [
            { id: 1, state: 'success', context: 'ci/build', description: 'Build passed' },
            { id: 2, state: 'pending', context: 'ci/test', description: 'Tests running' }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns commit statuses' do
      statuses = client.get_commit_statuses('owner', 'repo', 'abc123')

      expect(statuses.length).to eq(2)
      expect(statuses.first[:state]).to eq('success')
      expect(statuses.first[:context]).to eq('ci/build')
    end
  end

  describe '#get_combined_status' do
    before do
      stub_request(:get, 'https://api.github.com/repos/owner/repo/commits/abc123/status')
        .to_return(
          status: 200,
          body: {
            state: 'success',
            total_count: 2,
            statuses: [
              { state: 'success', context: 'ci/build' },
              { state: 'success', context: 'ci/test' }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns combined status' do
      result = client.get_combined_status('owner', 'repo', 'abc123')

      expect(result[:state]).to eq('success')
      expect(result[:total_count]).to eq(2)
    end
  end

  describe '#create_commit_status' do
    before do
      stub_request(:post, 'https://api.github.com/repos/owner/repo/statuses/abc123')
        .with(
          body: hash_including(state: 'success', context: 'ci/build')
        )
        .to_return(
          status: 201,
          body: { id: 1, state: 'success', context: 'ci/build' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates a commit status' do
      result = client.create_commit_status('owner', 'repo', 'abc123', 'success',
                                           context: 'ci/build',
                                           description: 'Build passed',
                                           target_url: 'https://ci.example.com/build/123')

      expect(result[:success]).to be true
      expect(result[:state]).to eq('success')
    end
  end

  # =============================================================================
  # BRANCH PROTECTION
  # =============================================================================

  describe '#get_branch_protection' do
    context 'when branch is protected' do
      before do
        stub_request(:get, 'https://api.github.com/repos/owner/repo/branches/main/protection')
          .to_return(
            status: 200,
            body: {
              required_status_checks: { strict: true, contexts: ['ci/build'] },
              enforce_admins: { enabled: true },
              required_pull_request_reviews: { required_approving_review_count: 2 },
              restrictions: nil
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns branch protection settings' do
        protection = client.get_branch_protection('owner', 'repo', 'main')

        expect(protection[:required_status_checks]).to be_present
        expect(protection[:required_status_checks][:strict]).to be true
        expect(protection[:enforce_admins][:enabled]).to be true
      end
    end

    context 'when branch is not protected' do
      before do
        stub_request(:get, 'https://api.github.com/repos/owner/repo/branches/develop/protection')
          .to_return(
            status: 404,
            body: { message: 'Branch not protected' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns nil' do
        protection = client.get_branch_protection('owner', 'repo', 'develop')

        expect(protection).to be_nil
      end
    end
  end

  describe '#update_branch_protection' do
    before do
      stub_request(:put, 'https://api.github.com/repos/owner/repo/branches/main/protection')
        .with(
          body: hash_including(
            required_status_checks: { strict: true, contexts: ['ci/build'] },
            enforce_admins: true
          )
        )
        .to_return(
          status: 200,
          body: {
            required_status_checks: { strict: true, contexts: ['ci/build'] },
            enforce_admins: { enabled: true }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'updates branch protection and returns success' do
      result = client.update_branch_protection('owner', 'repo', 'main',
                                               required_status_checks: { strict: true, contexts: ['ci/build'] },
                                               enforce_admins: true)

      expect(result[:success]).to be true
      expect(result[:protection]).to be_present
    end
  end

  describe '#delete_branch_protection' do
    context 'when successful' do
      before do
        stub_request(:delete, 'https://api.github.com/repos/owner/repo/branches/main/protection')
          .to_return(status: 204)
      end

      it 'deletes protection and returns success' do
        result = client.delete_branch_protection('owner', 'repo', 'main')

        expect(result[:success]).to be true
      end
    end

    context 'when branch is not protected' do
      before do
        stub_request(:delete, 'https://api.github.com/repos/owner/repo/branches/develop/protection')
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'returns success (idempotent)' do
        result = client.delete_branch_protection('owner', 'repo', 'develop')

        expect(result[:success]).to be true
      end
    end
  end

  describe '#list_protected_branches' do
    before do
      stub_request(:get, /api\.github\.com\/repos\/owner\/repo\/branches/)
        .with(query: hash_including(protected: 'true'))
        .to_return(
          status: 200,
          body: [
            { name: 'main', protected: true },
            { name: 'release', protected: true }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of protected branches' do
      branches = client.list_protected_branches('owner', 'repo')

      expect(branches.length).to eq(2)
      expect(branches.first[:name]).to eq('main')
      expect(branches.first[:protected]).to be true
    end
  end

  # =============================================================================
  # DEPLOY KEYS
  # =============================================================================

  describe '#list_deploy_keys' do
    before do
      stub_request(:get, 'https://api.github.com/repos/owner/repo/keys')
        .to_return(
          status: 200,
          body: [
            { id: 1, title: 'Deploy key 1', key: 'ssh-rsa AAAA...', read_only: true },
            { id: 2, title: 'Deploy key 2', key: 'ssh-rsa BBBB...', read_only: false }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of deploy keys' do
      keys = client.list_deploy_keys('owner', 'repo')

      expect(keys.length).to eq(2)
      expect(keys.first[:id]).to eq(1)
      expect(keys.first[:title]).to eq('Deploy key 1')
      expect(keys.first[:read_only]).to be true
    end
  end

  describe '#get_deploy_key' do
    before do
      stub_request(:get, 'https://api.github.com/repos/owner/repo/keys/1')
        .to_return(
          status: 200,
          body: { id: 1, title: 'Deploy key 1', key: 'ssh-rsa AAAA...', read_only: true }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns deploy key details' do
      key = client.get_deploy_key('owner', 'repo', 1)

      expect(key[:id]).to eq(1)
      expect(key[:title]).to eq('Deploy key 1')
    end
  end

  describe '#create_deploy_key' do
    before do
      stub_request(:post, 'https://api.github.com/repos/owner/repo/keys')
        .with(
          body: hash_including(title: 'CI Deploy', key: 'ssh-rsa AAAA...')
        )
        .to_return(
          status: 201,
          body: { id: 3, title: 'CI Deploy', key: 'ssh-rsa AAAA...', read_only: true }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates a deploy key and returns success' do
      result = client.create_deploy_key('owner', 'repo', 'CI Deploy', 'ssh-rsa AAAA...')

      expect(result[:success]).to be true
      expect(result[:key][:id]).to eq(3)
      expect(result[:key][:title]).to eq('CI Deploy')
    end
  end

  describe '#delete_deploy_key' do
    context 'when successful' do
      before do
        stub_request(:delete, 'https://api.github.com/repos/owner/repo/keys/1')
          .to_return(status: 204)
      end

      it 'deletes the key and returns success' do
        result = client.delete_deploy_key('owner', 'repo', 1)

        expect(result[:success]).to be true
      end
    end

    context 'when key already deleted' do
      before do
        stub_request(:delete, 'https://api.github.com/repos/owner/repo/keys/999')
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'returns success (idempotent)' do
        result = client.delete_deploy_key('owner', 'repo', 999)

        expect(result[:success]).to be true
      end
    end
  end

  # =============================================================================
  # ERROR HANDLING
  # =============================================================================

  describe 'error handling' do
    it 'raises RateLimitError on 403 with rate limit message' do
      stub_request(:get, 'https://api.github.com/user')
        .to_return(
          status: 403,
          body: { message: 'API rate limit exceeded' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect { client.test_connection }.to raise_error(Git::ApiClient::RateLimitError)
    end

    it 'raises NotFoundError on 404' do
      stub_request(:get, 'https://api.github.com/repos/owner/nonexistent')
        .to_return(
          status: 404,
          body: { message: 'Not Found' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect { client.get_repository('owner', 'nonexistent') }.to raise_error(Git::ApiClient::NotFoundError)
    end

    it 'raises ServerError on 500' do
      stub_request(:get, 'https://api.github.com/user')
        .to_return(
          status: 500,
          body: { message: 'Internal Server Error' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect { client.test_connection }.to raise_error(Git::ApiClient::ServerError)
    end
  end
end
