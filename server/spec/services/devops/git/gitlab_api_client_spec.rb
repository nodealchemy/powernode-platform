# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::Git::GitlabApiClient do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, :gitlab) }
  let(:credential) { create(:git_provider_credential, :gitlab, provider: provider, account: account) }
  let(:client) { described_class.new(credential) }

  before do
    allow(credential).to receive(:access_token).and_return('test_gitlab_token')
  end

  describe '#test_connection' do
    context 'when connection is successful' do
      before do
        stub_request(:get, 'https://gitlab.com/api/v4/user')
          .to_return(
            status: 200,
            body: { username: 'testuser', id: 123, avatar_url: 'https://example.com/avatar.png' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success with user data' do
        result = client.test_connection

        expect(result[:success]).to be true
        expect(result[:username]).to eq('testuser')
      end
    end

    context 'when authentication fails' do
      before do
        stub_request(:get, 'https://gitlab.com/api/v4/user')
          .to_return(
            status: 401,
            body: { message: '401 Unauthorized' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns failure with error message' do
        result = client.test_connection
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end
  end

  describe '#list_repositories' do
    before do
      stub_request(:get, /gitlab\.com\/api\/v4\/projects/)
        .to_return(
          status: 200,
          body: [
            {
              id: 1,
              name: 'project1',
              path_with_namespace: 'user/project1',
              visibility: 'public',
              namespace: { path: 'user' }
            },
            {
              id: 2,
              name: 'project2',
              path_with_namespace: 'user/project2',
              visibility: 'private',
              namespace: { path: 'user' }
            }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of projects as repositories' do
      repos = client.list_repositories

      expect(repos.length).to eq(2)
      expect(repos.first["full_name"]).to eq('user/project1')
    end
  end

  describe '#get_repository' do
    before do
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo')
        .to_return(
          status: 200,
          body: {
            id: 123,
            name: 'repo',
            path_with_namespace: 'owner/repo',
            description: 'A test project',
            visibility: 'private',
            default_branch: 'main',
            http_url_to_repo: 'https://gitlab.com/owner/repo.git',
            ssh_url_to_repo: 'git@gitlab.com:owner/repo.git',
            web_url: 'https://gitlab.com/owner/repo',
            star_count: 50,
            forks_count: 10,
            open_issues_count: 3,
            namespace: { path: 'owner' }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns project details' do
      repo = client.get_repository('owner', 'repo')

      expect(repo["name"]).to eq('repo')
      expect(repo["full_name"]).to eq('owner/repo')
      expect(repo["private"]).to be true
    end
  end

  describe '#list_branches' do
    before do
      stub_request(:get, /gitlab\.com\/api\/v4\/projects\/.*\/repository\/branches/)
        .to_return(
          status: 200,
          body: [
            { name: 'main', protected: true, commit: { id: 'abc123' } },
            { name: 'develop', protected: false, commit: { id: 'def456' } }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of branches' do
      branches = client.list_branches('owner', 'repo')

      expect(branches.length).to eq(2)
      expect(branches.first["name"]).to eq('main')
    end
  end

  describe '#list_commits' do
    before do
      stub_request(:get, /gitlab\.com\/api\/v4\/projects\/.*\/repository\/commits/)
        .to_return(
          status: 200,
          body: [
            {
              id: 'abc123',
              message: 'Initial commit',
              author_name: 'Test User',
              author_email: 'test@example.com',
              created_at: '2024-01-01T00:00:00Z'
            }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of commits' do
      commits = client.list_commits('owner', 'repo')

      expect(commits.length).to eq(1)
      expect(commits.first["sha"]).to eq('abc123')
    end
  end

  describe '#list_pull_requests' do
    before do
      stub_request(:get, /gitlab\.com\/api\/v4\/projects\/.*\/merge_requests/)
        .to_return(
          status: 200,
          body: [
            {
              id: 100,
              iid: 1,
              title: 'Feature MR',
              state: 'opened',
              author: { username: 'testuser' },
              source_branch: 'feature',
              target_branch: 'main'
            }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns merge requests as pull requests' do
      prs = client.list_pull_requests('owner', 'repo')

      expect(prs.length).to eq(1)
      expect(prs.first["number"]).to eq(1)
      expect(prs.first["state"]).to eq('opened')
    end
  end

  describe '#list_issues' do
    before do
      stub_request(:get, /gitlab\.com\/api\/v4\/projects\/.*\/issues/)
        .to_return(
          status: 200,
          body: [
            {
              id: 200,
              iid: 5,
              title: 'Bug report',
              state: 'opened',
              author: { username: 'reporter' }
            }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of issues' do
      issues = client.list_issues('owner', 'repo')

      expect(issues.length).to eq(1)
      expect(issues.first["number"]).to eq(5)
    end
  end

  # =============================================================================
  # WEBHOOK MANAGEMENT
  # =============================================================================

  describe '#create_webhook' do
    let(:repository) { create(:git_repository, owner: 'owner', name: 'repo') }

    before do
      stub_request(:post, 'https://gitlab.com/api/v4/projects/owner%2Frepo/hooks')
        .to_return(
          status: 201,
          body: { id: 12345 }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates a project hook' do
      result = client.create_webhook(repository, 'secret123')

      expect(result[:success]).to be true
      expect(result[:webhook_id]).to eq('12345')
    end
  end

  describe '#delete_webhook' do
    let(:repository) { create(:git_repository, owner: 'owner', name: 'repo', webhook_id: '12345') }

    before do
      stub_request(:delete, 'https://gitlab.com/api/v4/projects/owner%2Frepo/hooks/12345')
        .to_return(status: 204)
    end

    it 'deletes the project hook' do
      result = client.delete_webhook(repository)

      expect(result[:success]).to be true
    end
  end

  # =============================================================================
  # CI/CD - GITLAB PIPELINES
  # =============================================================================

  describe '#list_workflow_runs' do
    before do
      stub_request(:get, /gitlab\.com\/api\/v4\/projects\/.*\/pipelines/)
        .to_return(
          status: 200,
          body: [
            {
              id: 111,
              ref: 'main',
              sha: 'abc123',
              status: 'success',
              source: 'push',
              created_at: '2024-01-01T00:00:00Z',
              updated_at: '2024-01-01T00:10:00Z'
            },
            {
              id: 222,
              ref: 'develop',
              sha: 'def456',
              status: 'running',
              source: 'push',
              created_at: '2024-01-02T00:00:00Z'
            }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of pipelines' do
      runs = client.list_workflow_runs('owner', 'repo')

      expect(runs.length).to eq(2)
      expect(runs.first["id"]).to eq(111)
    end
  end

  describe '#get_workflow_run' do
    before do
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/pipelines/111')
        .to_return(
          status: 200,
          body: {
            id: 111,
            ref: 'main',
            sha: 'abc123',
            status: 'success',
            web_url: 'https://gitlab.com/owner/repo/-/pipelines/111'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns pipeline details' do
      run = client.get_workflow_run('owner', 'repo', 111)

      expect(run["id"]).to eq(111)
    end
  end

  describe '#get_workflow_run_jobs' do
    before do
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/pipelines/111/jobs')
        .to_return(
          status: 200,
          body: [
            { id: 1, name: 'build', status: 'success' },
            { id: 2, name: 'test', status: 'success' }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of pipeline jobs' do
      jobs = client.get_workflow_run_jobs('owner', 'repo', 111)

      expect(jobs.length).to eq(2)
    end
  end

  describe '#get_job_logs' do
    before do
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/jobs/1/trace')
        .to_return(status: 200, body: "Running build...\nBuild complete!")
    end

    it 'returns job trace' do
      logs = client.get_job_logs('owner', 'repo', 1)

      expect(logs).to include('Running build')
    end
  end

  describe '#trigger_workflow' do
    before do
      stub_request(:post, 'https://gitlab.com/api/v4/projects/owner%2Frepo/pipeline')
        .to_return(
          status: 201,
          body: { id: 333 }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates a new pipeline' do
      result = client.trigger_workflow('owner', 'repo', nil, 'main')

      expect(result[:success]).to be true
      expect(result[:pipeline_id]).to eq(333)
    end
  end

  describe '#cancel_workflow_run' do
    before do
      stub_request(:post, 'https://gitlab.com/api/v4/projects/owner%2Frepo/pipelines/111/cancel')
        .to_return(
          status: 200,
          body: { id: 111, status: 'canceled' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'cancels the pipeline' do
      result = client.cancel_workflow_run('owner', 'repo', 111)

      expect(result[:success]).to be true
    end
  end

  describe '#rerun_workflow' do
    before do
      stub_request(:post, 'https://gitlab.com/api/v4/projects/owner%2Frepo/pipelines/111/retry')
        .to_return(
          status: 201,
          body: { id: 444 }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'retries the pipeline' do
      result = client.rerun_workflow('owner', 'repo', 111)

      expect(result[:success]).to be true
      expect(result[:pipeline_id]).to eq(444)
    end
  end

  # =============================================================================
  # COMMIT STATUSES
  # =============================================================================

  describe '#get_commit_statuses' do
    before do
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/repository/commits/abc123/statuses')
        .to_return(
          status: 200,
          body: [
            { id: 1, status: 'success', name: 'ci/build', description: 'Build passed' },
            { id: 2, status: 'pending', name: 'ci/test', description: 'Tests running' }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns commit statuses' do
      statuses = client.get_commit_statuses('owner', 'repo', 'abc123')

      expect(statuses.length).to eq(2)
      expect(statuses.first['context']).to eq('ci/build')
    end
  end

  describe '#create_commit_status' do
    before do
      stub_request(:post, 'https://gitlab.com/api/v4/projects/owner%2Frepo/statuses/abc123')
        .with(
          body: hash_including(state: 'success', name: 'ci/build')
        )
        .to_return(
          status: 201,
          body: { id: 1, status: 'success', name: 'ci/build' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates a commit status' do
      result = client.create_commit_status('owner', 'repo', 'abc123', 'success',
                                           context: 'ci/build',
                                           description: 'Build passed')

      expect(result[:success]).to be true
    end
  end

  # =============================================================================
  # BRANCH PROTECTION
  # =============================================================================

  describe '#get_branch_protection' do
    context 'when branch is protected' do
      before do
        stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/protected_branches/main')
          .to_return(
            status: 200,
            body: {
              name: 'main',
              push_access_levels: [ { access_level: 40 } ],
              merge_access_levels: [ { access_level: 40 } ],
              allow_force_push: false,
              code_owner_approval_required: true
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns branch protection settings' do
        protection = client.get_branch_protection('owner', 'repo', 'main')

        expect(protection['name']).to eq('main')
        expect(protection['allow_force_push']).to be false
        expect(protection['code_owner_approval_required']).to be true
      end
    end

    context 'when branch is not protected' do
      before do
        stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/protected_branches/develop')
          .to_return(
            status: 404,
            body: { message: '404 Not found' }.to_json,
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
      # GitLab requires delete then create
      stub_request(:delete, 'https://gitlab.com/api/v4/projects/owner%2Frepo/protected_branches/main')
        .to_return(status: 204)

      stub_request(:post, 'https://gitlab.com/api/v4/projects/owner%2Frepo/protected_branches')
        .with(
          body: hash_including(name: 'main', push_access_level: 40)
        )
        .to_return(
          status: 201,
          body: {
            name: 'main',
            push_access_levels: [ { access_level: 40 } ],
            merge_access_levels: [ { access_level: 40 } ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'updates branch protection and returns success' do
      result = client.update_branch_protection('owner', 'repo', 'main',
                                               push_access_level: 40,
                                               merge_access_level: 40)

      expect(result[:success]).to be true
      expect(result[:protection]).to be_present
      expect(result[:protection]['name']).to eq('main')
    end
  end

  describe '#delete_branch_protection' do
    context 'when successful' do
      before do
        stub_request(:delete, 'https://gitlab.com/api/v4/projects/owner%2Frepo/protected_branches/main')
          .to_return(status: 204)
      end

      it 'deletes protection and returns success' do
        result = client.delete_branch_protection('owner', 'repo', 'main')

        expect(result[:success]).to be true
      end
    end

    context 'when branch is not protected' do
      before do
        stub_request(:delete, 'https://gitlab.com/api/v4/projects/owner%2Frepo/protected_branches/develop')
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
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/protected_branches')
        .to_return(
          status: 200,
          body: [
            { name: 'main', push_access_levels: [ { access_level: 40 } ] },
            { name: 'release', push_access_levels: [ { access_level: 30 } ] }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of protected branches' do
      branches = client.list_protected_branches('owner', 'repo')

      expect(branches.length).to eq(2)
      expect(branches.first['name']).to eq('main')
    end
  end

  # =============================================================================
  # DEPLOY KEYS
  # =============================================================================

  describe '#list_deploy_keys' do
    before do
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/deploy_keys')
        .to_return(
          status: 200,
          body: [
            { id: 1, title: 'Deploy key 1', key: 'ssh-rsa AAAA...', can_push: false },
            { id: 2, title: 'Deploy key 2', key: 'ssh-rsa BBBB...', can_push: true }
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
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Frepo/deploy_keys/1')
        .to_return(
          status: 200,
          body: { id: 1, title: 'Deploy key 1', key: 'ssh-rsa AAAA...', can_push: false }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns deploy key details' do
      key = client.get_deploy_key('owner', 'repo', 1)

      expect(key[:id]).to eq(1)
      expect(key[:title]).to eq('Deploy key 1')
      expect(key[:read_only]).to be true
    end
  end

  describe '#create_deploy_key' do
    before do
      stub_request(:post, 'https://gitlab.com/api/v4/projects/owner%2Frepo/deploy_keys')
        .with(
          body: hash_including(title: 'CI Deploy', key: 'ssh-rsa AAAA...')
        )
        .to_return(
          status: 201,
          body: { id: 3, title: 'CI Deploy', key: 'ssh-rsa AAAA...', can_push: false }.to_json,
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
        stub_request(:delete, 'https://gitlab.com/api/v4/projects/owner%2Frepo/deploy_keys/1')
          .to_return(status: 204)
      end

      it 'deletes the key and returns success' do
        result = client.delete_deploy_key('owner', 'repo', 1)

        expect(result[:success]).to be true
      end
    end

    context 'when key already deleted' do
      before do
        stub_request(:delete, 'https://gitlab.com/api/v4/projects/owner%2Frepo/deploy_keys/999')
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
    it 'raises NotFoundError on 404' do
      stub_request(:get, 'https://gitlab.com/api/v4/projects/owner%2Fnonexistent')
        .to_return(
          status: 404,
          body: { message: '404 Project Not Found' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect { client.get_repository('owner', 'nonexistent') }.to raise_error(Devops::Git::ApiClient::NotFoundError)
    end

    it 'raises RateLimitError on 429' do
      stub_request(:get, 'https://gitlab.com/api/v4/user')
        .to_return(
          status: 429,
          body: { message: 'Too Many Requests' }.to_json,
          headers: { 'Content-Type' => 'application/json', 'RateLimit-Remaining' => '0' }
        )

      expect { client.current_user }.to raise_error(Devops::Git::ApiClient::RateLimitError)
    end
  end
end
