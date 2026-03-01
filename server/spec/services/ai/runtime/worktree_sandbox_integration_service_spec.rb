# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Runtime::WorktreeSandboxIntegrationService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
  let(:worktree) do
    create(:ai_worktree, :ready, worktree_session: session, account: account)
  end

  let(:sandbox_manager) { instance_double(Ai::Runtime::SandboxManagerService) }

  subject(:service) { described_class.new(account: account, user: user) }

  before do
    allow(Ai::Runtime::SandboxManagerService).to receive(:new)
      .with(account: account)
      .and_return(sandbox_manager)
  end

  # ============================================================
  # provision_sandbox_for_worktree
  # ============================================================
  describe '#provision_sandbox_for_worktree' do
    let(:container_instance) do
      create(:devops_container_instance, :running, account: account)
    end

    before do
      allow(sandbox_manager).to receive(:create_sandbox).and_return(container_instance)
    end

    context 'when worktree is valid for provisioning' do
      it 'creates a sandbox and tracks the instance on the worktree' do
        result = service.provision_sandbox_for_worktree(worktree: worktree, agent: agent)

        expect(result[:success]).to be true
        expect(result[:sandbox]).to eq(container_instance.instance_summary)
        expect(result[:worktree_path]).to eq(worktree.worktree_path)
        expect(result[:execution_id]).to eq(container_instance.execution_id)
      end

      it 'delegates to sandbox manager with correct config' do
        service.provision_sandbox_for_worktree(worktree: worktree, agent: agent)

        expect(sandbox_manager).to have_received(:create_sandbox) do |args|
          expect(args[:agent]).to eq(agent)
          expect(args[:config][:volumes]).to include("#{worktree.worktree_path}:/workspace")
          expect(args[:config][:environment]).to include(
            "WORKSPACE_PATH" => "/workspace",
            "WORKTREE_ID" => worktree.id,
            "WORKTREE_BRANCH" => worktree.branch_name
          )
          expect(args[:config][:labels]).to include(
            "powernode.worktree_id" => worktree.id,
            "powernode.session_id" => worktree.worktree_session_id
          )
        end
      end

      it 'tracks container instance on the worktree' do
        service.provision_sandbox_for_worktree(worktree: worktree, agent: agent)

        worktree.reload
        expect(worktree.container_instance_id).to eq(container_instance.id)
      end
    end

    context 'when worktree is in terminal status' do
      let(:completed_worktree) do
        create(:ai_worktree, :completed, worktree_session: session, account: account)
      end

      it 'returns an error result' do
        result = service.provision_sandbox_for_worktree(worktree: completed_worktree, agent: agent)

        expect(result[:success]).to be false
        expect(result[:error]).to include("terminal status")
      end

      it 'does not call sandbox manager' do
        service.provision_sandbox_for_worktree(worktree: completed_worktree, agent: agent)

        expect(sandbox_manager).not_to have_received(:create_sandbox)
      end
    end

    context 'when worktree has a failed status' do
      let(:failed_worktree) do
        create(:ai_worktree, :failed, worktree_session: session, account: account)
      end

      it 'returns an error result' do
        result = service.provision_sandbox_for_worktree(worktree: failed_worktree, agent: agent)

        expect(result[:success]).to be false
        expect(result[:error]).to include("terminal status")
      end
    end

    context 'when worktree already has an active sandbox' do
      let(:existing_instance) do
        create(:devops_container_instance, :running, account: account)
      end

      before do
        worktree.track_container_instance!(existing_instance.id)
      end

      it 'returns an error result' do
        result = service.provision_sandbox_for_worktree(worktree: worktree, agent: agent)

        expect(result[:success]).to be false
        expect(result[:error]).to include("already has an active sandbox")
      end
    end

    context 'when worktree has no worktree_path' do
      let(:blank_path_worktree) do
        wt = create(:ai_worktree, :ready, worktree_session: session, account: account)
        # worktree_path has NOT NULL constraint, so stub it instead
        allow(wt).to receive(:worktree_path).and_return(nil)
        wt
      end

      it 'returns an error result' do
        result = service.provision_sandbox_for_worktree(worktree: blank_path_worktree, agent: agent)

        expect(result[:success]).to be false
        expect(result[:error]).to include("no worktree_path")
      end
    end

    context 'when sandbox manager raises an error' do
      before do
        allow(sandbox_manager).to receive(:create_sandbox)
          .and_raise(StandardError, "Docker daemon unavailable")
      end

      it 'returns an error result with the exception message' do
        result = service.provision_sandbox_for_worktree(worktree: worktree, agent: agent)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Docker daemon unavailable")
      end
    end
  end

  # ============================================================
  # teardown_sandbox_for_worktree
  # ============================================================
  describe '#teardown_sandbox_for_worktree' do
    context 'when worktree has an active sandbox' do
      let(:container_instance) do
        create(:devops_container_instance, :running, account: account)
      end

      before do
        worktree.track_container_instance!(container_instance.id)
        allow(sandbox_manager).to receive(:destroy_sandbox).and_return(true)
      end

      it 'destroys the sandbox and returns success' do
        result = service.teardown_sandbox_for_worktree(worktree: worktree)

        expect(result[:success]).to be true
        expect(result[:execution_id]).to eq(container_instance.execution_id)
        expect(result[:message]).to include("destroyed")
      end

      it 'delegates to sandbox manager with the correct instance' do
        service.teardown_sandbox_for_worktree(worktree: worktree, reason: "test_cleanup")

        expect(sandbox_manager).to have_received(:destroy_sandbox)
          .with(instance: container_instance, reason: "test_cleanup")
      end
    end

    context 'when worktree has no sandbox' do
      it 'returns success with a no-sandbox message' do
        result = service.teardown_sandbox_for_worktree(worktree: worktree)

        expect(result[:success]).to be true
        expect(result[:message]).to include("No sandbox associated")
      end
    end

    context 'when container instance is already inactive' do
      let(:completed_instance) do
        create(:devops_container_instance, :completed, account: account)
      end

      before do
        worktree.track_container_instance!(completed_instance.id)
      end

      it 'returns success with already inactive message' do
        result = service.teardown_sandbox_for_worktree(worktree: worktree)

        expect(result[:success]).to be true
        expect(result[:message]).to include("already inactive")
      end
    end

    context 'when container instance is not found' do
      before do
        worktree.track_container_instance!(SecureRandom.uuid)
      end

      it 'returns an error result' do
        result = service.teardown_sandbox_for_worktree(worktree: worktree)

        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end
    end

    context 'when sandbox manager fails to destroy' do
      let(:container_instance) do
        create(:devops_container_instance, :running, account: account)
      end

      before do
        worktree.track_container_instance!(container_instance.id)
        allow(sandbox_manager).to receive(:destroy_sandbox).and_return(false)
      end

      it 'returns an error result' do
        result = service.teardown_sandbox_for_worktree(worktree: worktree)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Failed to destroy")
      end
    end
  end

  # ============================================================
  # provision_session_sandboxes
  # ============================================================
  describe '#provision_session_sandboxes' do
    let(:container_instance1) { create(:devops_container_instance, :running, account: account) }
    let(:container_instance2) { create(:devops_container_instance, :running, account: account) }
    let(:agent2) { create(:ai_agent, account: account) }

    let!(:worktree1) { create(:ai_worktree, :ready, worktree_session: session, account: account) }
    let!(:worktree2) { create(:ai_worktree, worktree_session: session, account: account, status: "pending") }

    let(:agents_map) do
      { worktree1.id => agent, worktree2.id => agent2 }
    end

    before do
      allow(sandbox_manager).to receive(:create_sandbox)
        .and_return(container_instance1, container_instance2)
    end

    it 'provisions sandboxes for all eligible worktrees' do
      result = service.provision_session_sandboxes(session: session, agents_map: agents_map)

      expect(result[:success]).to be true
      expect(result[:succeeded]).to eq(2)
      expect(result[:failed]).to eq(0)
      expect(result[:results].size).to eq(2)
    end

    context 'when no worktrees are provisionable' do
      before do
        session.worktrees.update_all(status: "completed")
      end

      it 'returns success with empty results' do
        result = service.provision_session_sandboxes(session: session, agents_map: agents_map)

        expect(result[:success]).to be true
        expect(result[:results]).to be_empty
        expect(result[:message]).to include("No worktrees to provision")
      end
    end

    context 'when a worktree has no agent assigned' do
      it 'skips the worktree without an agent' do
        result = service.provision_session_sandboxes(session: session, agents_map: { worktree1.id => agent })

        skip_result = result[:results].find { |r| r[:worktree_id] == worktree2.id }
        expect(skip_result[:success]).to be false
        expect(skip_result[:error]).to include("No agent assigned")
      end
    end
  end

  # ============================================================
  # teardown_session_sandboxes
  # ============================================================
  describe '#teardown_session_sandboxes' do
    let(:container_instance1) { create(:devops_container_instance, :running, account: account) }
    let(:container_instance2) { create(:devops_container_instance, :running, account: account) }

    let!(:worktree1) do
      wt = create(:ai_worktree, :ready, worktree_session: session, account: account)
      wt.track_container_instance!(container_instance1.id)
      wt
    end

    let!(:worktree2) do
      wt = create(:ai_worktree, :ready, worktree_session: session, account: account)
      wt.track_container_instance!(container_instance2.id)
      wt
    end

    before do
      allow(sandbox_manager).to receive(:destroy_sandbox).and_return(true)
    end

    it 'tears down all sandboxes in the session' do
      result = service.teardown_session_sandboxes(session: session)

      expect(result[:success]).to be true
      expect(result[:succeeded]).to eq(2)
      expect(result[:total]).to eq(2)
    end

    it 'passes the reason to each teardown' do
      service.teardown_session_sandboxes(session: session, reason: "session_cancelled")

      expect(sandbox_manager).to have_received(:destroy_sandbox).twice
    end
  end

  # ============================================================
  # exec_in_worktree_sandbox
  # ============================================================
  describe '#exec_in_worktree_sandbox' do
    context 'when worktree has an active sandbox' do
      let(:container_instance) do
        create(:devops_container_instance, :running, account: account)
      end

      before do
        worktree.track_container_instance!(container_instance.id)
      end

      it 'delegates to sandbox manager' do
        expected_result = { success: true, output: "hello world" }
        allow(sandbox_manager).to receive(:exec_in_sandbox).and_return(expected_result)

        result = service.exec_in_worktree_sandbox(worktree: worktree, command: "echo hello")

        expect(result).to eq(expected_result)
        expect(sandbox_manager).to have_received(:exec_in_sandbox)
          .with(instance: container_instance, command: "echo hello")
      end
    end

    context 'when worktree has no sandbox' do
      it 'returns an error result' do
        result = service.exec_in_worktree_sandbox(worktree: worktree, command: "echo hello")

        expect(result[:success]).to be false
        expect(result[:error]).to include("No sandbox associated")
      end
    end

    context 'when container instance is not found' do
      before do
        worktree.track_container_instance!(SecureRandom.uuid)
      end

      it 'returns an error result' do
        result = service.exec_in_worktree_sandbox(worktree: worktree, command: "echo hello")

        expect(result[:success]).to be false
        expect(result[:error]).to include("not found")
      end
    end
  end

  # ============================================================
  # health_check
  # ============================================================
  describe '#health_check' do
    let(:container_instance) do
      create(:devops_container_instance, :running, account: account)
    end
    let(:worktree_manager) { instance_double(Ai::Git::WorktreeManager) }

    before do
      worktree.track_container_instance!(container_instance.id)
      allow(Ai::Git::WorktreeManager).to receive(:new).and_return(worktree_manager)
    end

    context 'when both git and sandbox are healthy' do
      before do
        allow(worktree_manager).to receive(:health_check).and_return({ healthy: true, head_sha: "abc123" })
        allow(sandbox_manager).to receive(:get_metrics).and_return({ cpu: 10, memory: 256 })
      end

      it 'returns combined healthy status' do
        result = service.health_check(worktree: worktree)

        expect(result[:success]).to be true
        expect(result[:healthy]).to be true
        expect(result[:worktree_id]).to eq(worktree.id)
        expect(result[:git]).to include(healthy: true)
        expect(result[:sandbox]).to include(healthy: true)
        expect(result[:checked_at]).to be_present
      end
    end

    context 'when git health check fails' do
      before do
        allow(worktree_manager).to receive(:health_check).and_return({ healthy: false, error: "Not a git dir" })
        allow(sandbox_manager).to receive(:get_metrics).and_return({ cpu: 10, memory: 256 })
      end

      it 'returns overall unhealthy status' do
        result = service.health_check(worktree: worktree)

        expect(result[:success]).to be true
        expect(result[:healthy]).to be false
        expect(result[:git][:healthy]).to be false
      end
    end

    context 'when sandbox is not running' do
      let(:stopped_instance) do
        create(:devops_container_instance, :completed, account: account)
      end

      before do
        worktree.track_container_instance!(stopped_instance.id)
        allow(worktree_manager).to receive(:health_check).and_return({ healthy: true })
        allow(sandbox_manager).to receive(:get_metrics).and_return({})
      end

      it 'reports sandbox as unhealthy' do
        result = service.health_check(worktree: worktree)

        expect(result[:sandbox][:healthy]).to be false
      end
    end

    context 'when no sandbox is associated' do
      let(:bare_worktree) do
        create(:ai_worktree, :ready, worktree_session: session, account: account)
      end

      before do
        allow(worktree_manager).to receive(:health_check).and_return({ healthy: true })
      end

      it 'reports sandbox as unhealthy with no-sandbox status' do
        result = service.health_check(worktree: bare_worktree)

        expect(result[:sandbox][:healthy]).to be false
        expect(result[:sandbox][:status]).to eq("none")
      end
    end

    context 'when git health check raises an error' do
      before do
        allow(worktree_manager).to receive(:health_check)
          .and_raise(StandardError, "git process crashed")
        allow(sandbox_manager).to receive(:get_metrics).and_return({})
      end

      it 'returns unhealthy git status with the error captured' do
        result = service.health_check(worktree: worktree)

        expect(result[:success]).to be true
        expect(result[:healthy]).to be false
        expect(result[:git][:healthy]).to be false
        expect(result[:git][:error]).to include("git process crashed")
      end
    end

    context 'when both checks fail' do
      before do
        allow(worktree_manager).to receive(:health_check)
          .and_return({ healthy: false, error: "Worktree dir missing" })
        allow(sandbox_manager).to receive(:get_metrics).and_return({})
      end

      let(:no_sandbox_worktree) do
        create(:ai_worktree, :ready, worktree_session: session, account: account)
      end

      it 'returns overall unhealthy when both subsystems are unhealthy' do
        result = service.health_check(worktree: no_sandbox_worktree)

        expect(result[:success]).to be true
        expect(result[:healthy]).to be false
        expect(result[:git][:healthy]).to be false
        expect(result[:sandbox][:healthy]).to be false
      end
    end
  end

  # ============================================================
  # pause_worktree_sandbox / resume_worktree_sandbox
  # ============================================================
  describe '#pause_worktree_sandbox' do
    let(:container_instance) do
      create(:devops_container_instance, :running, account: account)
    end

    before do
      worktree.track_container_instance!(container_instance.id)
    end

    context 'when pause succeeds' do
      before do
        allow(sandbox_manager).to receive(:pause_sandbox)
          .and_return({ success: true })
      end

      it 'returns success' do
        result = service.pause_worktree_sandbox(worktree: worktree)

        expect(result[:success]).to be true
        expect(sandbox_manager).to have_received(:pause_sandbox)
          .with(instance: container_instance)
      end
    end

    context 'when pause fails' do
      before do
        allow(sandbox_manager).to receive(:pause_sandbox)
          .and_return({ success: false, error: "Instance is not running" })
      end

      it 'returns the error from sandbox manager' do
        result = service.pause_worktree_sandbox(worktree: worktree)

        expect(result[:success]).to be false
        expect(result[:error]).to include("not running")
      end
    end

    context 'when worktree has no sandbox' do
      let(:bare_worktree) do
        create(:ai_worktree, :ready, worktree_session: session, account: account)
      end

      it 'returns an error result' do
        result = service.pause_worktree_sandbox(worktree: bare_worktree)

        expect(result[:success]).to be false
        expect(result[:error]).to include("No sandbox associated")
      end
    end
  end

  describe '#resume_worktree_sandbox' do
    let(:container_instance) do
      create(:devops_container_instance, :running, account: account)
    end

    before do
      worktree.track_container_instance!(container_instance.id)
    end

    context 'when resume succeeds' do
      before do
        allow(sandbox_manager).to receive(:resume_sandbox)
          .and_return({ success: true })
      end

      it 'returns success' do
        result = service.resume_worktree_sandbox(worktree: worktree)

        expect(result[:success]).to be true
        expect(sandbox_manager).to have_received(:resume_sandbox)
          .with(instance: container_instance)
      end
    end

    context 'when resume fails' do
      before do
        allow(sandbox_manager).to receive(:resume_sandbox)
          .and_return({ success: false, error: "No docker host found" })
      end

      it 'returns the error from sandbox manager' do
        result = service.resume_worktree_sandbox(worktree: worktree)

        expect(result[:success]).to be false
        expect(result[:error]).to include("No docker host found")
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(sandbox_manager).to receive(:resume_sandbox)
          .and_raise(StandardError, "Connection refused")
      end

      it 'returns an error result' do
        result = service.resume_worktree_sandbox(worktree: worktree)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Connection refused")
      end
    end
  end
end
