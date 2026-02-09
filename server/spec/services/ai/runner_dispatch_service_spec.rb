# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::RunnerDispatchService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
  let(:worktree) { create(:ai_worktree, worktree_session: session, status: "ready") }
  let(:credential) do
    create(:git_provider_credential,
           account: account,
           user: user,
           provider: create(:git_provider, provider_type: "gitea"))
  end
  let(:repository) do
    create(:git_repository, account: account, credential: credential, full_name: "testuser/test-repo")
  end
  let(:runner) do
    create(:git_runner,
           account: account,
           credential: credential,
           status: "online",
           busy: false,
           labels: ["self-hosted", "linux", "x64"],
           total_jobs_run: 5)
  end

  let(:client) { instance_double(Devops::Git::ApiClient) }

  subject(:service) { described_class.new(account: account, session: session) }

  before do
    allow(Devops::Git::ApiClient).to receive(:for).and_return(client)
    # Stub credential lookup
    allow(account).to receive_message_chain(:git_provider_credentials, :joins, :where, :where, :order).and_return([credential])
  end

  describe '#select_runner' do
    let!(:runner1) { create(:git_runner, account: account, credential: credential, status: "online", busy: false, labels: ["self-hosted", "linux"], total_jobs_run: 10) }
    let!(:runner2) { create(:git_runner, account: account, credential: credential, status: "online", busy: false, labels: ["self-hosted", "linux", "gpu"], total_jobs_run: 3) }
    let!(:busy_runner) { create(:git_runner, account: account, credential: credential, status: "busy", busy: true, labels: ["self-hosted"], total_jobs_run: 1) }

    it 'returns the least-loaded available runner' do
      result = service.select_runner(required_labels: [])
      expect(result).to eq(runner2)
    end

    it 'filters by required labels' do
      result = service.select_runner(required_labels: ["gpu"])
      expect(result).to eq(runner2)
    end

    it 'excludes busy runners' do
      result = service.select_runner(required_labels: [])
      expect(result).not_to eq(busy_runner)
    end

    it 'returns nil when no runners match labels' do
      result = service.select_runner(required_labels: ["nonexistent"])
      expect(result).to be_nil
    end
  end

  describe '#dispatch' do
    before do
      allow(client).to receive(:trigger_workflow).and_return({ run_id: 12345 })
      allow(service).to receive(:resolve_repository).and_return(repository)
      allow(worktree).to receive(:mark_in_use!)
      allow(runner).to receive(:mark_busy!)
    end

    it 'creates a RunnerDispatch record' do
      expect {
        service.dispatch(worktree: worktree, task_input: { task: "test" }, runner: runner)
      }.to change(Ai::RunnerDispatch, :count).by(1)
    end

    it 'returns success with dispatch' do
      result = service.dispatch(worktree: worktree, task_input: {}, runner: runner)
      expect(result[:success]).to be true
      expect(result[:dispatch]).to be_a(Ai::RunnerDispatch)
    end

    it 'sets dispatch status to dispatched' do
      result = service.dispatch(worktree: worktree, task_input: {}, runner: runner)
      expect(result[:dispatch].status).to eq("dispatched")
    end

    it 'triggers the workflow via Gitea API' do
      service.dispatch(worktree: worktree, task_input: {}, runner: runner)
      expect(client).to have_received(:trigger_workflow)
    end

    it 'marks the worktree in use' do
      service.dispatch(worktree: worktree, task_input: {}, runner: runner)
      expect(worktree).to have_received(:mark_in_use!)
    end

    it 'marks the runner busy' do
      service.dispatch(worktree: worktree, task_input: {}, runner: runner)
      expect(runner).to have_received(:mark_busy!)
    end

    context 'when no repository is found' do
      before { allow(service).to receive(:resolve_repository).and_return(nil) }

      it 'returns failure' do
        result = service.dispatch(worktree: worktree, task_input: {}, runner: runner)
        expect(result[:success]).to be false
        expect(result[:error]).to include("No repository")
      end
    end
  end

  describe '#sync_status' do
    let(:dispatch) do
      Ai::RunnerDispatch.create!(
        account: account,
        worktree_session: session,
        worktree: worktree,
        git_runner: runner,
        git_repository: repository,
        workflow_run_id: "999",
        status: "dispatched",
        dispatched_at: 5.minutes.ago
      )
    end

    before do
      allow(client).to receive(:list_workflow_runs).and_return([
        { "id" => 999, "status" => "completed", "conclusion" => "success" }
      ])
      allow(client).to receive(:get_workflow_run_jobs).and_return([])
    end

    it 'updates dispatch status from Gitea' do
      service.sync_status(dispatch)
      dispatch.reload
      expect(dispatch.status).to eq("completed")
    end

    it 'marks runner available on completion' do
      allow(runner).to receive(:mark_available!)
      allow(runner).to receive(:record_job_completion!)
      service.sync_status(dispatch)
      expect(runner).to have_received(:mark_available!)
    end

    context 'when run is in progress' do
      before do
        allow(client).to receive(:list_workflow_runs).and_return([
          { "id" => 999, "status" => "in_progress", "conclusion" => nil }
        ])
      end

      it 'updates to running status' do
        service.sync_status(dispatch)
        dispatch.reload
        expect(dispatch.status).to eq("running")
      end
    end

    context 'when run fails' do
      before do
        allow(client).to receive(:list_workflow_runs).and_return([
          { "id" => 999, "status" => "completed", "conclusion" => "failure" }
        ])
        allow(client).to receive(:get_workflow_run_jobs).and_return([])
      end

      it 'updates to failed status' do
        service.sync_status(dispatch)
        dispatch.reload
        expect(dispatch.status).to eq("failed")
      end
    end
  end

  describe '#collect_results' do
    let(:dispatch) do
      Ai::RunnerDispatch.create!(
        account: account,
        worktree_session: session,
        worktree: worktree,
        git_runner: runner,
        git_repository: repository,
        workflow_run_id: "999",
        status: "completed",
        dispatched_at: 10.minutes.ago
      )
    end

    before do
      allow(client).to receive(:get_workflow_run_jobs).and_return([{ "id" => 1 }])
      allow(client).to receive(:get_job_logs).and_return("Job completed successfully")
      manager = instance_double(Ai::Git::WorktreeManager)
      allow(Ai::Git::WorktreeManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:diff_stats).and_return({ head_sha: "abc123", files_changed: 3 })
      allow(worktree).to receive(:complete!)
    end

    it 'stores logs on the dispatch' do
      service.collect_results(dispatch, repository)
      dispatch.reload
      expect(dispatch.logs).to include("Job completed")
    end

    it 'stores output_result with job count' do
      service.collect_results(dispatch, repository)
      dispatch.reload
      expect(dispatch.output_result).to include("job_count" => 1)
    end

    it 'sets completed_at' do
      service.collect_results(dispatch, repository)
      dispatch.reload
      expect(dispatch.completed_at).to be_present
    end

    it 'calculates duration_ms' do
      service.collect_results(dispatch, repository)
      dispatch.reload
      expect(dispatch.duration_ms).to be_positive
    end
  end
end
