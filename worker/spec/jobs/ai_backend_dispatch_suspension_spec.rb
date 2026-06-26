# frozen_string_literal: true

require 'rails_helper'

# Backend-dispatch AI jobs must honor the per-account kill switch
# (AiSuspensionCheckConcern, worker/CLAUDE.md L11). These jobs delegate real
# LLM/agent/embedding execution to the server (or an external agent), so a
# missing concern means emergency_halt / per-account suspension silently fails
# to stop them. Regression spec for IMP-7f395d55d15b.
#
# Two scopes are excluded by design:
#   * ai_memory_consolidation_job / ai_memory_maintenance_job — global, cross-account
#     (handled separately; no single account to gate on).
#   * ai_goal_plan_execution_job / ai_self_challenge_job — the worker receives only a
#     step_id / challenge_id and there is NO worker-visible endpoint that returns the
#     owning account_id, so they cannot be gated worker-side without a server change
#     (pass account_id in the enqueue payload). Tracked in the task report.
RSpec.describe 'Backend-dispatch AI job kill-switch compliance' do
  let(:account_id) { 'account-202' }

  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  # ---- account_id directly available from params --------------------------

  describe AiMissionExecuteJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before fetching the mission when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:backend_api_get)

      job.execute('mission_id' => 'm-1', 'account_id' => account_id)
    end
  end

  describe AiMissionPlanJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before fetching the mission when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:backend_api_get)

      job.execute('mission_id' => 'm-1', 'account_id' => account_id)
    end
  end

  describe AiProvisioningCaptureIntentJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before invoking capture_intent when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:backend_api_post)

      job.execute('mission_id' => 'm-1', 'account_id' => account_id)
    end
  end

  describe AiProvisioningComposePlanJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before invoking compose_plan when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:backend_api_post)

      job.execute('mission_id' => 'm-1', 'account_id' => account_id)
    end
  end

  describe AiCodeFactoryRemediationJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before generating remediation patches when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:backend_api_post)

      job.execute(
        'review_state_id' => 'rs-1',
        'account_id' => account_id,
        'findings' => [{ 'file_path' => 'a.rb', 'message' => 'x' }]
      )
    end
  end

  describe AiCodebaseIndexJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before the indexing/embedding request when AI is suspended' do
      job = described_class.new
      api = instance_double('BackendApiClient')
      allow(job).to receive(:api_client).and_return(api)
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(api).not_to receive(:post_with_circuit_breaker)

      job.execute('account_id' => account_id, 'base_path' => '/repo')
    end
  end

  # ---- account_id resolved from a fetched backend record ------------------

  describe AiAgentTeamExecutionJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before orchestrating the team when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:fetch_team).and_return('account_id' => account_id, 'id' => 't-1')
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:execute_team_orchestration)

      job.execute('team_id' => 't-1', 'user_id' => 'u-1', 'input' => 'hi')
    end
  end

  describe AiRalphLoopRunAllJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before running any iteration when AI is suspended' do
      job = described_class.new
      api = instance_double('BackendApiClient')
      allow(job).to receive(:api_client).and_return(api)
      allow(api).to receive(:get)
        .with('/api/v1/ai/ralph_loops/loop-1')
        .and_return('data' => { 'ralph_loop' => { 'account_id' => account_id } })
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(api).not_to receive(:post)

      job.execute('loop-1', { 'stop_on_error' => false })
    end
  end

  describe AiA2aExternalTaskJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before calling the external A2A endpoint when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:fetch_a2a_task).and_return(
        'account_id' => account_id,
        'task_id' => 'tk-1',
        'is_external' => true,
        'external_endpoint_url' => 'https://example.com/a2a'
      )
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:execute_external_a2a_task)

      job.execute('a-1')
    end
  end

  describe AiReflexionJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before triggering reflexion when AI is suspended' do
      job = described_class.new
      api = instance_double('BackendApiClient')
      allow(job).to receive(:api_client).and_return(api)
      allow(api).to receive(:get)
        .with('/api/v1/internal/ai/executions/exec-1')
        .and_return('data' => { 'agent_execution' => { 'account_id' => account_id } })
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(api).not_to receive(:post)

      job.execute('exec-1')
    end
  end
end
