# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::Git::GiteaApiClient do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, :gitea) }
  let(:credential) do
    create(:git_provider_credential,
           provider: provider,
           account: account,
           auth_type: 'personal_access_token')
  end
  let(:client) { described_class.new(credential) }
  let(:base_url) { provider.api_base_url }

  before do
    allow(credential).to receive(:access_token).and_return('test_gitea_token')
  end

  # =============================================================================
  # INITIALIZATION
  # =============================================================================

  describe '#initialize' do
    it 'requires a configured API base URL' do
      provider_without_url = create(:git_provider, provider_type: 'gitea', api_base_url: nil)
      credential_without_url = create(:git_provider_credential,
                                       provider: provider_without_url,
                                       account: account)
      allow(credential_without_url).to receive(:access_token).and_return('token')

      expect { described_class.new(credential_without_url) }
        .to raise_error(ArgumentError, /Gitea requires a configured API base URL/)
    end

    it 'initializes successfully with valid configuration' do
      expect { client }.not_to raise_error
    end
  end

  # =============================================================================
  # CONNECTION TESTING
  # =============================================================================

  describe '#test_connection' do
    context 'with valid credentials' do
      before do
        stub_request(:get, "#{base_url}/user")
          .with(headers: { 'Authorization' => 'token test_gitea_token' })
          .to_return(
            status: 200,
            body: {
              id: 1,
              login: 'giteauser',
              username: 'giteauser',
              email: 'gitea@example.com',
              avatar_url: 'https://gitea.example.com/avatar/1'
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success with user information' do
        result = client.test_connection

        expect(result[:success]).to be true
        expect(result[:username]).to eq('giteauser')
        expect(result[:user_id]).to eq('1')
        expect(result[:email]).to eq('gitea@example.com')
        expect(result[:avatar_url]).to eq('https://gitea.example.com/avatar/1')
      end
    end

    context 'with invalid credentials' do
      before do
        stub_request(:get, "#{base_url}/user")
          .to_return(status: 401, body: { message: 'Unauthorized' }.to_json)
      end

      it 'returns failure with error message' do
        result = client.test_connection

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end
  end

  describe '#current_user' do
    before do
      stub_request(:get, "#{base_url}/user")
        .to_return(
          status: 200,
          body: { id: 1, login: 'giteauser', email: 'gitea@example.com' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns user data' do
      result = client.current_user

      expect(result['login']).to eq('giteauser')
      expect(result['email']).to eq('gitea@example.com')
    end
  end

  # =============================================================================
  # REPOSITORIES
  # =============================================================================

  describe '#list_repositories' do
    let(:repo_response) do
      [
        {
          id: 1,
          name: 'project-one',
          full_name: 'org/project-one',
          description: 'First project',
          private: false,
          fork: false,
          archived: false,
          default_branch: 'main',
          clone_url: 'https://gitea.example.com/org/project-one.git',
          ssh_url: 'git@gitea.example.com:org/project-one.git',
          html_url: 'https://gitea.example.com/org/project-one',
          stars_count: 10,
          forks_count: 5,
          open_issues_count: 3,
          language: 'Ruby',
          topics: %w[api backend],
          owner: { login: 'org' }
        },
        {
          id: 2,
          name: 'project-two',
          full_name: 'org/project-two',
          description: 'Second project',
          private: true,
          fork: false,
          archived: false,
          default_branch: 'develop',
          clone_url: 'https://gitea.example.com/org/project-two.git',
          ssh_url: 'git@gitea.example.com:org/project-two.git',
          html_url: 'https://gitea.example.com/org/project-two',
          stars_count: 0,
          forks_count: 0,
          open_issues_count: 0,
          owner: { username: 'org' }
        }
      ]
    end

    before do
      stub_request(:get, "#{base_url}/user/repos")
        .with(query: { page: 1, limit: 30 })
        .to_return(
          status: 200,
          body: repo_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns normalized repository list' do
      repos = client.list_repositories

      expect(repos.length).to eq(2)
      expect(repos.first['name']).to eq('project-one')
      expect(repos.first['full_name']).to eq('org/project-one')
      expect(repos.first['private']).to be false
      expect(repos.first['stargazers_count']).to eq(10)
      expect(repos.first['topics']).to eq(%w[api backend])
      expect(repos.first['owner']['login']).to eq('org')
    end

    it 'supports pagination' do
      stub_request(:get, "#{base_url}/user/repos")
        .with(query: { page: 2, limit: 50 })
        .to_return(status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' })

      repos = client.list_repositories(page: 2, per_page: 50)
      expect(repos).to eq([])
    end
  end

  describe '#list_org_repositories' do
    before do
      stub_request(:get, "#{base_url}/orgs/myorg/repos")
        .with(query: { page: 1, limit: 30 })
        .to_return(
          status: 200,
          body: [ { id: 1, name: 'org-repo', full_name: 'myorg/org-repo', owner: { login: 'myorg' } } ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns organization repositories' do
      repos = client.list_org_repositories('myorg')

      expect(repos.length).to eq(1)
      expect(repos.first['name']).to eq('org-repo')
    end
  end

  describe '#get_repository' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo")
        .to_return(
          status: 200,
          body: {
            id: 1,
            name: 'repo',
            full_name: 'owner/repo',
            description: 'Test repo',
            private: false,
            default_branch: 'main',
            owner: { login: 'owner' }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns normalized repository data' do
      repo = client.get_repository('owner', 'repo')

      expect(repo['name']).to eq('repo')
      expect(repo['full_name']).to eq('owner/repo')
      expect(repo['owner']['login']).to eq('owner')
    end
  end

  # =============================================================================
  # BRANCHES
  # =============================================================================

  describe '#list_branches' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/branches")
        .with(query: { page: 1, limit: 30 })
        .to_return(
          status: 200,
          body: [
            { name: 'main', protected: true },
            { name: 'develop', protected: false }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns branch list' do
      branches = client.list_branches('owner', 'repo')

      expect(branches.length).to eq(2)
      expect(branches.first['name']).to eq('main')
      expect(branches.first['protected']).to be true
    end
  end

  describe '#get_branch' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/branches/main")
        .to_return(
          status: 200,
          body: { name: 'main', commit: { sha: 'abc123' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns branch details' do
      branch = client.get_branch('owner', 'repo', 'main')

      expect(branch['name']).to eq('main')
      expect(branch['commit']['sha']).to eq('abc123')
    end
  end

  # =============================================================================
  # COMMITS
  # =============================================================================

  describe '#list_commits' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/commits")
        .with(query: { page: 1, limit: 30 })
        .to_return(
          status: 200,
          body: [
            { sha: 'abc123', commit: { message: 'Initial commit' } },
            { sha: 'def456', commit: { message: 'Add feature' } }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns commit list' do
      commits = client.list_commits('owner', 'repo')

      expect(commits.length).to eq(2)
      expect(commits.first['sha']).to eq('abc123')
    end

    it 'filters by sha' do
      stub_request(:get, "#{base_url}/repos/owner/repo/commits")
        .with(query: { page: 1, limit: 30, sha: 'develop' })
        .to_return(status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' })

      commits = client.list_commits('owner', 'repo', sha: 'develop')
      expect(commits).to eq([])
    end
  end

  # =============================================================================
  # PULL REQUESTS
  # =============================================================================

  describe '#list_pull_requests' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/pulls")
        .with(query: { state: 'open', page: 1, limit: 30 })
        .to_return(
          status: 200,
          body: [
            { number: 1, title: 'Feature PR', state: 'open', user: { login: 'contributor' } },
            { number: 2, title: 'Bug fix', state: 'open', user: { login: 'developer' } }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns pull request list' do
      prs = client.list_pull_requests('owner', 'repo')

      expect(prs.length).to eq(2)
      expect(prs.first['number']).to eq(1)
      expect(prs.first['title']).to eq('Feature PR')
    end

    it 'filters by state' do
      stub_request(:get, "#{base_url}/repos/owner/repo/pulls")
        .with(query: { state: 'closed', page: 1, limit: 30 })
        .to_return(status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' })

      prs = client.list_pull_requests('owner', 'repo', state: 'closed')
      expect(prs).to eq([])
    end
  end

  describe '#get_pull_request' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/pulls/42")
        .to_return(
          status: 200,
          body: {
            number: 42,
            title: 'Important feature',
            state: 'open',
            body: 'This adds an important feature',
            user: { login: 'contributor' }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns pull request details' do
      pr = client.get_pull_request('owner', 'repo', 42)

      expect(pr['number']).to eq(42)
      expect(pr['title']).to eq('Important feature')
      expect(pr['user']['login']).to eq('contributor')
    end
  end

  # =============================================================================
  # ISSUES
  # =============================================================================

  describe '#list_issues' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/issues")
        .with(query: { state: 'open', page: 1, limit: 30 })
        .to_return(
          status: 200,
          body: [
            { number: 1, title: 'Bug report', state: 'open' },
            { number: 2, title: 'Feature request', state: 'open' }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns issue list' do
      issues = client.list_issues('owner', 'repo')

      expect(issues.length).to eq(2)
      expect(issues.first['number']).to eq(1)
      expect(issues.first['title']).to eq('Bug report')
    end
  end

  describe '#get_issue' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/issues/10")
        .to_return(
          status: 200,
          body: { number: 10, title: 'Critical bug', state: 'open', body: 'Details here' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns issue details' do
      issue = client.get_issue('owner', 'repo', 10)

      expect(issue['number']).to eq(10)
      expect(issue['title']).to eq('Critical bug')
    end
  end

  # =============================================================================
  # WEBHOOKS
  # =============================================================================

  describe '#list_webhooks' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/hooks")
        .to_return(
          status: 200,
          body: [
            { id: 1, url: 'https://example.com/webhook', active: true },
            { id: 2, url: 'https://other.com/hook', active: false }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns webhook list' do
      hooks = client.list_webhooks('owner', 'repo')

      expect(hooks.length).to eq(2)
      expect(hooks.first['id']).to eq(1)
      expect(hooks.first['active']).to be true
    end
  end

  describe '#create_webhook' do
    let(:repository) { create(:git_repository, credential: credential, owner: 'owner', name: 'repo') }

    context 'when successful' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/hooks")
          .with(
            body: hash_including(
              type: 'gitea',
              active: true,
              events: array_including('push', 'pull_request')
            )
          )
          .to_return(
            status: 201,
            body: { id: 123, active: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'creates webhook and returns success' do
        result = client.create_webhook(repository, 'secret_token')

        expect(result[:success]).to be true
        expect(result[:webhook_id]).to eq('123')
      end
    end

    context 'when API fails' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/hooks")
          .to_return(status: 403, body: { message: 'Permission denied' }.to_json)
      end

      it 'returns failure' do
        result = client.create_webhook(repository, 'secret')

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end
  end

  describe '#delete_webhook' do
    let(:repository) do
      create(:git_repository, :with_webhook,
             credential: credential,
             owner: 'owner',
             name: 'repo',
             webhook_id: '456')
    end

    context 'when successful' do
      before do
        stub_request(:delete, "#{base_url}/repos/owner/repo/hooks/456")
          .to_return(status: 204)
      end

      it 'deletes webhook and returns success' do
        result = client.delete_webhook(repository)

        expect(result[:success]).to be true
      end
    end

    context 'when webhook already deleted (404)' do
      before do
        stub_request(:delete, "#{base_url}/repos/owner/repo/hooks/456")
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'returns success (idempotent)' do
        result = client.delete_webhook(repository)

        expect(result[:success]).to be true
      end
    end

    context 'when no webhook configured' do
      let(:repo_without_webhook) { create(:git_repository, credential: credential, webhook_id: nil) }

      it 'returns error' do
        result = client.delete_webhook(repo_without_webhook)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No webhook configured')
      end
    end
  end

  # =============================================================================
  # GITEA ACTIONS (ACT RUNNER CI/CD)
  # =============================================================================

  describe '#list_workflow_runs' do
    let(:runs_response) do
      {
        workflow_runs: [
          {
            id: 100,
            name: 'CI Build',
            display_title: 'CI Build',
            status: 'completed',
            conclusion: 'success',
            run_number: 42,
            event: 'push',
            head_branch: 'main',
            head_sha: 'abc123',
            html_url: 'https://gitea.example.com/owner/repo/actions/runs/100',
            created_at: '2025-01-01T10:00:00Z',
            run_started_at: '2025-01-01T10:01:00Z',
            completed_at: '2025-01-01T10:05:00Z',
            actor: { login: 'developer' }
          },
          {
            id: 99,
            name: 'Deploy',
            status: 'in_progress',
            conclusion: nil,
            run_number: 41,
            event: 'workflow_dispatch',
            head_branch: 'release',
            head_sha: 'def456',
            actor: { username: 'deployer' }
          }
        ]
      }
    end

    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/actions/runs")
        .with(query: { page: 1, limit: 30 })
        .to_return(
          status: 200,
          body: runs_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns normalized workflow runs' do
      runs = client.list_workflow_runs('owner', 'repo')

      expect(runs.length).to eq(2)
      expect(runs.first['id']).to eq(100)
      expect(runs.first['name']).to eq('CI Build')
      expect(runs.first['status']).to eq('completed')
      expect(runs.first['conclusion']).to eq('success')
      expect(runs.first['run_number']).to eq(42)
      expect(runs.first['actor']['login']).to eq('developer')
    end

    it 'normalizes status values' do
      runs = client.list_workflow_runs('owner', 'repo')

      expect(runs.last['status']).to eq('in_progress')
    end

    context 'when actions are not enabled' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/actions/runs")
          .with(query: { page: 1, limit: 30 })
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'returns empty array' do
        runs = client.list_workflow_runs('owner', 'repo')
        expect(runs).to eq([])
      end
    end
  end

  describe '#get_workflow_run' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/actions/runs/100")
        .to_return(
          status: 200,
          body: {
            id: 100,
            name: 'CI Build',
            status: 'completed',
            conclusion: 'success',
            run_number: 42,
            event: 'push',
            head_branch: 'main',
            head_sha: 'abc123',
            actor: { login: 'developer' }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns normalized workflow run' do
      run = client.get_workflow_run('owner', 'repo', 100)

      expect(run['id']).to eq(100)
      expect(run['name']).to eq('CI Build')
      expect(run['status']).to eq('completed')
    end
  end

  describe '#get_workflow_run_jobs' do
    let(:jobs_response) do
      {
        jobs: [
          {
            id: 501,
            name: 'build',
            status: 'completed',
            conclusion: 'success',
            started_at: '2025-01-01T10:01:00Z',
            completed_at: '2025-01-01T10:03:00Z',
            runner_name: 'act-runner-1',
            runner_id: 10,
            steps: [
              { name: 'Checkout', status: 'completed', conclusion: 'success', number: 1 },
              { name: 'Build', status: 'completed', conclusion: 'success', number: 2 }
            ]
          },
          {
            id: 502,
            name: 'test',
            status: 'running',
            conclusion: nil,
            started_at: '2025-01-01T10:03:00Z',
            runner_name: 'act-runner-2',
            runner_id: 11,
            steps: []
          }
        ]
      }
    end

    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/actions/runs/100/jobs")
        .to_return(
          status: 200,
          body: jobs_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns normalized jobs' do
      jobs = client.get_workflow_run_jobs('owner', 'repo', 100)

      expect(jobs.length).to eq(2)
      expect(jobs.first['id']).to eq(501)
      expect(jobs.first['name']).to eq('build')
      expect(jobs.first['status']).to eq('completed')
      expect(jobs.first['runner_name']).to eq('act-runner-1')
      expect(jobs.first['runner_id']).to eq('10')
      expect(jobs.first['steps'].length).to eq(2)
    end

    context 'when not found' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/actions/runs/999/jobs")
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'returns empty array' do
        jobs = client.get_workflow_run_jobs('owner', 'repo', 999)
        expect(jobs).to eq([])
      end
    end
  end

  describe '#get_job_logs' do
    context 'when logs are available' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/actions/jobs/501/logs")
          .to_return(
            status: 200,
            body: "Step 1: Checkout\n> git checkout main\nStep 2: Build\n> npm run build\nBuild complete!",
            headers: { 'Content-Type' => 'text/plain' }
          )
      end

      it 'returns raw log content' do
        logs = client.get_job_logs('owner', 'repo', 501)

        expect(logs).to include('git checkout')
        expect(logs).to include('Build complete!')
      end
    end

    context 'when logs are not found' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/actions/jobs/999/logs")
          .to_return(status: 404)
      end

      it 'returns nil' do
        logs = client.get_job_logs('owner', 'repo', 999)
        expect(logs).to be_nil
      end
    end
  end

  describe '#list_workflows' do
    context 'when workflows exist' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/actions/workflows")
          .to_return(
            status: 200,
            body: {
              workflows: [
                { id: 1, name: 'CI', path: '.gitea/workflows/ci.yaml', state: 'active' },
                { id: 2, name: 'Deploy', path: '.gitea/workflows/deploy.yaml', state: 'active' }
              ]
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns workflow list' do
        workflows = client.list_workflows('owner', 'repo')

        expect(workflows.length).to eq(2)
        expect(workflows.first['name']).to eq('CI')
        expect(workflows.first['path']).to eq('.gitea/workflows/ci.yaml')
      end
    end

    context 'when actions are not enabled' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/actions/workflows")
          .to_return(status: 404)
      end

      it 'returns empty array' do
        workflows = client.list_workflows('owner', 'repo')
        expect(workflows).to eq([])
      end
    end
  end

  describe '#trigger_workflow' do
    context 'when successful' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/actions/workflows/ci.yaml/dispatches")
          .with(body: { ref: 'main', inputs: { deploy_env: 'staging' } }.to_json)
          .to_return(status: 204)
      end

      it 'triggers workflow and returns success' do
        result = client.trigger_workflow('owner', 'repo', 'ci.yaml', 'main', { deploy_env: 'staging' })

        expect(result[:success]).to be true
      end
    end

    context 'when workflow not found' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/actions/workflows/missing.yaml/dispatches")
          .to_return(status: 404, body: { message: 'Workflow not found' }.to_json)
      end

      it 'returns failure' do
        result = client.trigger_workflow('owner', 'repo', 'missing.yaml', 'main', {})

        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end
  end

  describe '#cancel_workflow_run' do
    context 'when successful' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/actions/runs/100/cancel")
          .to_return(status: 202)
      end

      it 'cancels run and returns success' do
        result = client.cancel_workflow_run('owner', 'repo', 100)

        expect(result[:success]).to be true
      end
    end

    context 'when run is already completed' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/actions/runs/100/cancel")
          .to_return(status: 409, body: { message: 'Cannot cancel completed run' }.to_json)
      end

      it 'returns failure' do
        result = client.cancel_workflow_run('owner', 'repo', 100)

        expect(result[:success]).to be false
      end
    end
  end

  describe '#rerun_workflow' do
    context 'when successful' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/actions/runs/100/rerun")
          .to_return(status: 201)
      end

      it 'reruns workflow and returns success' do
        result = client.rerun_workflow('owner', 'repo', 100)

        expect(result[:success]).to be true
      end
    end

    context 'when rerun fails' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/actions/runs/100/rerun")
          .to_return(status: 500, body: { message: 'Internal error' }.to_json)
      end

      it 'returns failure' do
        result = client.rerun_workflow('owner', 'repo', 100)

        expect(result[:success]).to be false
      end
    end
  end

  # =============================================================================
  # ACT RUNNER MANAGEMENT
  # =============================================================================

  describe '#list_runners' do
    let(:runners_response) do
      {
        runners: [
          {
            id: 10,
            name: 'act-runner-1',
            status: 'online',
            busy: false,
            labels: [ { name: 'ubuntu-latest' }, { name: 'docker' } ],
            version: '0.2.6',
            os: 'linux',
            arch: 'amd64'
          },
          {
            id: 11,
            name: 'act-runner-2',
            busy: true,
            labels: [ 'self-hosted', 'arm64' ],
            version: '0.2.6',
            os: 'linux',
            arch: 'arm64'
          }
        ]
      }
    end

    context 'with repo scope' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/actions/runners")
          .to_return(
            status: 200,
            body: runners_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns normalized runners' do
        runners = client.list_runners(:repo, 'owner', 'repo')

        expect(runners.length).to eq(2)
        expect(runners.first['id']).to eq(10)
        expect(runners.first['name']).to eq('act-runner-1')
        expect(runners.first['status']).to eq('online')
        expect(runners.first['busy']).to be false
        expect(runners.first['labels']).to eq([ 'ubuntu-latest', 'docker' ])
        expect(runners.first['os']).to eq('linux')
        expect(runners.first['arch']).to eq('amd64')
      end

      it 'infers status from busy flag when status missing' do
        runners = client.list_runners(:repo, 'owner', 'repo')

        expect(runners.last['status']).to eq('busy')
        expect(runners.last['busy']).to be true
      end
    end

    context 'with org scope' do
      before do
        stub_request(:get, "#{base_url}/orgs/myorg/actions/runners")
          .to_return(status: 200, body: runners_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'calls org endpoint' do
        runners = client.list_runners(:org, 'myorg')

        expect(runners.length).to eq(2)
      end
    end

    context 'with admin scope' do
      before do
        stub_request(:get, "#{base_url}/admin/actions/runners")
          .to_return(status: 200, body: runners_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'calls admin endpoint' do
        runners = client.list_runners(:admin)

        expect(runners.length).to eq(2)
      end
    end

    context 'with invalid scope' do
      it 'raises ArgumentError' do
        expect { client.list_runners(:invalid, 'owner', 'repo') }
          .to raise_error(ArgumentError, /Invalid scope/)
      end
    end

    context 'when actions not enabled' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/actions/runners")
          .to_return(status: 404)
      end

      it 'returns empty array' do
        runners = client.list_runners(:repo, 'owner', 'repo')
        expect(runners).to eq([])
      end
    end
  end

  describe '#get_runner' do
    before do
      stub_request(:get, "#{base_url}/admin/actions/runners/10")
        .to_return(
          status: 200,
          body: {
            id: 10,
            name: 'act-runner-1',
            status: 'online',
            busy: false,
            labels: [ { name: 'ubuntu-latest' } ],
            version: '0.2.6'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns normalized runner' do
      runner = client.get_runner(10)

      expect(runner['id']).to eq(10)
      expect(runner['name']).to eq('act-runner-1')
      expect(runner['status']).to eq('online')
    end
  end

  describe '#runner_registration_token' do
    context 'with repo scope' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/actions/runners/registration-token")
          .to_return(
            status: 201,
            body: { token: 'registration_token_abc123' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns registration token' do
        result = client.runner_registration_token(:repo, 'owner', 'repo')

        expect(result[:token]).to eq('registration_token_abc123')
      end
    end

    context 'with org scope' do
      before do
        stub_request(:post, "#{base_url}/orgs/myorg/actions/runners/registration-token")
          .to_return(
            status: 201,
            body: { token: 'org_token_123' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns organization registration token' do
        result = client.runner_registration_token(:org, 'myorg')

        expect(result[:token]).to eq('org_token_123')
      end
    end

    context 'with admin scope' do
      before do
        stub_request(:post, "#{base_url}/admin/actions/runners/registration-token")
          .to_return(
            status: 201,
            body: { token: 'admin_token_456' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns admin registration token' do
        result = client.runner_registration_token(:admin)

        expect(result[:token]).to eq('admin_token_456')
      end
    end

    context 'when unauthorized' do
      before do
        stub_request(:post, "#{base_url}/repos/owner/repo/actions/runners/registration-token")
          .to_return(status: 403, body: { message: 'Forbidden' }.to_json)
      end

      it 'returns error hash and logs error' do
        expect(Rails.logger).to receive(:error).with(/Failed to get runner registration token/)

        result = client.runner_registration_token(:repo, 'owner', 'repo')
        expect(result[:success]).to be false
        expect(result[:error]).to be_present
      end
    end

    context 'with invalid scope' do
      it 'raises ArgumentError' do
        expect { client.runner_registration_token(:invalid) }
          .to raise_error(ArgumentError, /Invalid scope/)
      end
    end
  end

  # =============================================================================
  # STATUS NORMALIZATION
  # =============================================================================

  describe 'status normalization' do
    let(:runs_with_varied_statuses) do
      {
        workflow_runs: [
          { id: 1, status: 'queued', conclusion: nil },
          { id: 2, status: 'waiting', conclusion: nil },
          { id: 3, status: 'pending', conclusion: nil },
          { id: 4, status: 'running', conclusion: nil },
          { id: 5, status: 'COMPLETED', conclusion: 'success' },
          { id: 6, status: 'failed', conclusion: 'failure' },
          { id: 7, status: 'cancelled', conclusion: 'cancelled' },
          { id: 8, status: 'canceled', conclusion: 'cancelled' },
          { id: 9, status: 'skipped', conclusion: 'skipped' },
          { id: 10, status: nil, conclusion: nil }
        ]
      }
    end

    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/actions/runs")
        .with(query: { page: 1, limit: 30 })
        .to_return(
          status: 200,
          body: runs_with_varied_statuses.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'normalizes all status variations correctly' do
      runs = client.list_workflow_runs('owner', 'repo')

      expect(runs.map { |r| r['status'] }).to eq([
        'queued',      # queued -> queued
        'queued',      # waiting -> queued
        'pending',     # pending -> pending
        'in_progress', # running -> in_progress
        'completed',   # COMPLETED -> completed
        'failed',      # failed -> failed
        'cancelled',   # cancelled -> cancelled
        'cancelled',   # canceled -> cancelled
        'skipped',     # skipped -> skipped
        'pending'      # nil -> pending
      ])
    end
  end

  # =============================================================================
  # COMMIT STATUSES
  # =============================================================================

  describe '#get_commit_statuses' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/statuses/abc123")
        .to_return(
          status: 200,
          body: [
            { id: 1, status: 'success', context: 'ci/build', description: 'Build passed' },
            { id: 2, status: 'pending', context: 'ci/test', description: 'Tests running' }
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

  describe '#get_combined_status' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/commits/abc123/status")
        .to_return(
          status: 200,
          body: {
            state: 'success',
            statuses: [
              { status: 'success', context: 'ci/build' },
              { status: 'success', context: 'ci/test' }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns combined status' do
      result = client.get_combined_status('owner', 'repo', 'abc123')

      expect(result['state']).to eq('success')
    end
  end

  describe '#create_commit_status' do
    before do
      stub_request(:post, "#{base_url}/repos/owner/repo/statuses/abc123")
        .with(
          body: hash_including(state: 'success', context: 'ci/build')
        )
        .to_return(
          status: 201,
          body: { id: 1, status: 'success', context: 'ci/build' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'creates a commit status' do
      result = client.create_commit_status('owner', 'repo', 'abc123', 'success',
                                           context: 'ci/build',
                                           description: 'Build passed',
                                           target_url: 'https://ci.example.com/build/123')

      expect(result[:success]).to be true
    end
  end

  # =============================================================================
  # BRANCH PROTECTION
  # =============================================================================

  describe '#get_branch_protection' do
    context 'when branch is protected' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/branch_protections/main")
          .to_return(
            status: 200,
            body: {
              branch_name: 'main',
              enable_push: true,
              enable_push_whitelist: false,
              enable_merge_whitelist: false,
              enable_status_check: true,
              status_check_contexts: [ 'ci/build' ],
              required_approvals: 2,
              block_on_rejected_reviews: true,
              dismiss_stale_approvals: true,
              require_signed_commits: false
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns branch protection settings' do
        protection = client.get_branch_protection('owner', 'repo', 'main')

        expect(protection['branch_name']).to eq('main')
        expect(protection['enable_status_check']).to be true
        expect(protection['required_approvals']).to eq(2)
        expect(protection['block_on_rejected_reviews']).to be true
      end
    end

    context 'when branch is not protected' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/branch_protections/develop")
          .to_return(
            status: 404,
            body: { message: 'Not found' }.to_json,
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
    context 'when updating existing protection' do
      before do
        stub_request(:patch, "#{base_url}/repos/owner/repo/branch_protections/main")
          .with(
            body: hash_including(
              branch_name: 'main',
              enable_status_check: true,
              required_approvals: 2
            )
          )
          .to_return(
            status: 200,
            body: {
              branch_name: 'main',
              enable_status_check: true,
              required_approvals: 2
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'updates branch protection and returns success' do
        result = client.update_branch_protection('owner', 'repo', 'main',
                                                 enable_status_check: true,
                                                 required_approvals: 2)

        expect(result[:success]).to be true
        expect(result[:protection]).to be_present
        expect(result[:protection]['required_approvals']).to eq(2)
      end
    end

    context 'when creating new protection (branch not protected)' do
      before do
        stub_request(:patch, "#{base_url}/repos/owner/repo/branch_protections/develop")
          .to_return(status: 404, body: { message: 'Not found' }.to_json)

        stub_request(:post, "#{base_url}/repos/owner/repo/branch_protections")
          .with(
            body: hash_including(branch_name: 'develop')
          )
          .to_return(
            status: 201,
            body: { branch_name: 'develop', enable_push: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'creates new protection and returns success' do
        result = client.update_branch_protection('owner', 'repo', 'develop', {})

        expect(result[:success]).to be true
        expect(result[:protection]['branch_name']).to eq('develop')
      end
    end
  end

  describe '#delete_branch_protection' do
    context 'when successful' do
      before do
        stub_request(:delete, "#{base_url}/repos/owner/repo/branch_protections/main")
          .to_return(status: 204)
      end

      it 'deletes protection and returns success' do
        result = client.delete_branch_protection('owner', 'repo', 'main')

        expect(result[:success]).to be true
      end
    end

    context 'when branch is not protected' do
      before do
        stub_request(:delete, "#{base_url}/repos/owner/repo/branch_protections/develop")
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
      stub_request(:get, "#{base_url}/repos/owner/repo/branch_protections")
        .to_return(
          status: 200,
          body: [
            { branch_name: 'main', required_approvals: 2 },
            { branch_name: 'release', required_approvals: 1 }
          ].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns list of protected branches' do
      branches = client.list_protected_branches('owner', 'repo')

      expect(branches.length).to eq(2)
      expect(branches.first['branch_name']).to eq('main')
      expect(branches.first['required_approvals']).to eq(2)
    end
  end

  # =============================================================================
  # DEPLOY KEYS
  # =============================================================================

  describe '#list_deploy_keys' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/keys")
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
      expect(keys.first['id']).to eq(1)
      expect(keys.first['title']).to eq('Deploy key 1')
      expect(keys.first['read_only']).to be true
    end
  end

  describe '#get_deploy_key' do
    before do
      stub_request(:get, "#{base_url}/repos/owner/repo/keys/1")
        .to_return(
          status: 200,
          body: { id: 1, title: 'Deploy key 1', key: 'ssh-rsa AAAA...', read_only: true }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'returns deploy key details' do
      key = client.get_deploy_key('owner', 'repo', 1)

      expect(key['id']).to eq(1)
      expect(key['title']).to eq('Deploy key 1')
      expect(key['read_only']).to be true
    end
  end

  describe '#create_deploy_key' do
    before do
      stub_request(:post, "#{base_url}/repos/owner/repo/keys")
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
      expect(result[:key]['id']).to eq(3)
      expect(result[:key]['title']).to eq('CI Deploy')
    end
  end

  describe '#delete_deploy_key' do
    context 'when successful' do
      before do
        stub_request(:delete, "#{base_url}/repos/owner/repo/keys/1")
          .to_return(status: 204)
      end

      it 'deletes the key and returns success' do
        result = client.delete_deploy_key('owner', 'repo', 1)

        expect(result[:success]).to be true
      end
    end

    context 'when key already deleted' do
      before do
        stub_request(:delete, "#{base_url}/repos/owner/repo/keys/999")
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'returns success (idempotent)' do
        result = client.delete_deploy_key('owner', 'repo', 999)

        expect(result[:success]).to be true
      end
    end
  end

  # =============================================================================
  # FILE CONTENT (WITH SLASHED REF RESOLUTION)
  # =============================================================================

  describe '#get_file_content' do
    context 'with simple ref (no slashes)' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/contents/src/app.js")
          .with(query: { ref: 'main' })
          .to_return(
            status: 200,
            body: {
              name: 'app.js',
              path: 'src/app.js',
              sha: 'abc123',
              size: 42,
              type: 'file',
              encoding: 'base64',
              content: Base64.strict_encode64('console.log("hello")')
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'passes the ref directly without resolution' do
        result = client.get_file_content('owner', 'repo', 'src/app.js', 'main')

        expect(result[:path]).to eq('src/app.js')
        expect(result[:sha]).to eq('abc123')
        expect(result[:content]).to eq('console.log("hello")')
      end
    end

    context 'with slashed ref (e.g. mission/abc-feature)' do
      before do
        # Resolve slashed branch name to commit SHA
        stub_request(:get, "#{base_url}/repos/owner/repo/branches/mission/abc-feature")
          .to_return(
            status: 200,
            body: { name: 'mission/abc-feature', commit: { id: 'resolved_sha_123' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Contents API called with resolved SHA instead of slashed branch name
        stub_request(:get, "#{base_url}/repos/owner/repo/contents/src/index.css")
          .with(query: { ref: 'resolved_sha_123' })
          .to_return(
            status: 200,
            body: {
              name: 'index.css',
              path: 'src/index.css',
              sha: 'file_sha_456',
              size: 20,
              type: 'file',
              encoding: 'base64',
              content: Base64.strict_encode64('body { color: red; }')
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'resolves the branch to a commit SHA before calling contents API' do
        result = client.get_file_content('owner', 'repo', 'src/index.css', 'mission/abc-feature')

        expect(result).not_to be_nil
        expect(result[:path]).to eq('src/index.css')
        expect(result[:sha]).to eq('file_sha_456')
        expect(result[:content]).to eq('body { color: red; }')
      end
    end

    context 'with slashed ref where file does not exist' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/branches/mission/xyz")
          .to_return(
            status: 200,
            body: { name: 'mission/xyz', commit: { id: 'commit_abc' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_request(:get, "#{base_url}/repos/owner/repo/contents/nonexistent.txt")
          .with(query: { ref: 'commit_abc' })
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'returns nil' do
        result = client.get_file_content('owner', 'repo', 'nonexistent.txt', 'mission/xyz')

        expect(result).to be_nil
      end
    end

    context 'with slashed ref where branch lookup fails' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/branches/feature/unknown")
          .to_return(status: 404, body: { message: 'Not found' }.to_json)

        # Falls through with original ref
        stub_request(:get, "#{base_url}/repos/owner/repo/contents/README.md")
          .with(query: { ref: 'feature/unknown' })
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'passes original ref through and returns nil' do
        result = client.get_file_content('owner', 'repo', 'README.md', 'feature/unknown')

        expect(result).to be_nil
      end
    end

    context 'with non-slashed ref that returns 404' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/contents/missing.txt")
          .with(query: { ref: 'main' })
          .to_return(status: 404, body: { message: 'Not found' }.to_json)
      end

      it 'returns nil without branch resolution' do
        result = client.get_file_content('owner', 'repo', 'missing.txt', 'main')

        expect(result).to be_nil
      end
    end

    context 'without ref parameter' do
      before do
        stub_request(:get, "#{base_url}/repos/owner/repo/contents/README.md")
          .to_return(
            status: 200,
            body: {
              name: 'README.md',
              path: 'README.md',
              sha: 'readme_sha',
              size: 5,
              type: 'file',
              encoding: 'base64',
              content: Base64.strict_encode64('hello')
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'works without ref' do
        result = client.get_file_content('owner', 'repo', 'README.md')

        expect(result[:content]).to eq('hello')
      end
    end
  end
end
