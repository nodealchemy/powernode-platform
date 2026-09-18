# frozen_string_literal: true

require 'rails_helper'

# IMP-f301fd6563d2: Api::V1::Ai::AgentTeamExecutionsController#retry_execution
# used to enqueue a fresh AiTeamExecutionJob on every POST with no idempotency
# guard, so a double-click (or a client retry after a failure past the
# enqueue) queued two full agent-team executions and paid for the LLM spend
# twice. These specs lock in that at most one worker enqueue happens per
# finished original execution, and that the claim is released ONLY when the
# enqueue is known NOT to have happened — never on an ambiguous outcome,
# where releasing would let a client retry queue a second execution on top
# of one that may already exist.
RSpec.describe 'Api::V1::Ai::AgentTeamExecutionsController retry idempotency', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.teams.execute']) }
  let!(:team) { create(:ai_agent_team, account: account) }
  let!(:execution) { create(:ai_team_execution, :failed, account: account, agent_team: team) }

  def post_retry
    post "/api/v1/ai/agent_teams/#{team.id}/executions/#{execution.id}/retry",
         params: {}.to_json,
         headers: auth_headers_for(user)
  end

  describe 'double POST for the same finished execution' do
    it 'enqueues the worker job exactly once' do
      expect(WorkerJobService).to receive(:enqueue_ai_team_execution).once

      post_retry
      post_retry
    end

    it 'returns retry_queued on the first call and retry_already_queued on the second, both naming the same original execution' do
      allow(WorkerJobService).to receive(:enqueue_ai_team_execution).and_return({ 'job_id' => 'sidekiq-jid-1' })

      post_retry
      expect(response).to have_http_status(:success)
      first_body = JSON.parse(response.body)
      expect(first_body['data']['status']).to eq('retry_queued')
      expect(first_body['data']['original_execution_id']).to eq(execution.execution_id)

      post_retry
      expect(response).to have_http_status(:success)
      second_body = JSON.parse(response.body)
      expect(second_body['data']['status']).to eq('retry_already_queued')
      expect(second_body['data']['original_execution_id']).to eq(execution.execution_id)
      expect(second_body['data']['retry_queued_at']).to be_present
      expect(second_body['data']['retry_job_id']).to eq('sidekiq-jid-1')
    end

    it 'writes only one audit log row across both requests' do
      allow(WorkerJobService).to receive(:enqueue_ai_team_execution)

      expect {
        post_retry
        post_retry
      }.to change(AuditLog, :count).by(1)
    end
  end

  describe 'the claim is taken before the worker is called, not after' do
    it 'has already recorded retry_queued_at by the time enqueue_ai_team_execution runs' do
      allow(WorkerJobService).to receive(:enqueue_ai_team_execution) do
        expect(execution.reload.retry_queued_at).to be_present
        expect(execution.retry_state).to eq('enqueuing')
        nil
      end

      post_retry
      expect(response).to have_http_status(:success)
    end
  end

  describe 'a DEFINITE non-enqueue releases the claim' do
    %w[WorkerNotSentError WorkerRejectedError].each do |error_class_name|
      it "releases the claim on #{error_class_name} so a subsequent retry can still be queued" do
        error_class = WorkerJobService.const_get(error_class_name)
        allow(WorkerJobService).to receive(:enqueue_ai_team_execution).and_raise(error_class, 'boom')

        post_retry
        expect(response).to have_http_status(:internal_server_error)
        expect(execution.reload.retry_state).to be_nil
        expect(execution.retry_queued_at).to be_nil

        allow(WorkerJobService).to receive(:enqueue_ai_team_execution).and_return({ 'job_id' => 'sidekiq-jid-2' })
        post_retry

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['data']['status']).to eq('retry_queued')
      end
    end
  end

  describe 'an AMBIGUOUS outcome keeps the claim' do
    it 'on WorkerOutcomeUnknownError, a second POST does not enqueue another job' do
      allow(WorkerJobService).to receive(:enqueue_ai_team_execution)
        .and_raise(WorkerJobService::WorkerOutcomeUnknownError, 'read timeout')

      post_retry
      expect(response).to have_http_status(:internal_server_error)
      expect(execution.reload.retry_state).to eq('unknown')
      expect(execution.retry_queued_at).to be_present

      expect(WorkerJobService).not_to receive(:enqueue_ai_team_execution)
      post_retry

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body['data']['status']).to eq('retry_outcome_unknown')
      expect(body['data']['original_execution_id']).to eq(execution.execution_id)
    end
  end

  describe 'a non-WorkerServiceError raised after the claim (unmapped failure)' do
    it 'marks the state unknown, propagates the original error, and a second POST does not enqueue' do
      allow(WorkerJobService).to receive(:enqueue_ai_team_execution).and_raise(RuntimeError, 'unexpected bug')

      post_retry
      expect(response).to have_http_status(:internal_server_error)
      expect(execution.reload.retry_state).to eq('unknown')
      expect(execution.retry_queued_at).to be_present

      expect(WorkerJobService).not_to receive(:enqueue_ai_team_execution)
      post_retry

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)['data']['status']).to eq('retry_outcome_unknown')
    end
  end

  describe 'mark_retry_unknown! itself failing does not mask the original error' do
    it 'still surfaces the original WorkerOutcomeUnknownError via the global handler, not the mark failure' do
      allow(WorkerJobService).to receive(:enqueue_ai_team_execution)
        .and_raise(WorkerJobService::WorkerOutcomeUnknownError, 'original: read timeout')
      allow_any_instance_of(Ai::TeamExecution).to receive(:mark_retry_unknown!)
        .and_raise(StandardError, 'mark_retry_unknown! blew up')

      logged = []
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      post_retry

      expect(response).to have_http_status(:internal_server_error)
      expect(logged.any? { |m| m.include?('mark_retry_unknown! blew up') }).to be true
      expect(logged.any? { |m| m.include?('WorkerOutcomeUnknownError') && m.include?('original: read timeout') }).to be true
    end
  end

  describe 'release_retry_claim! itself failing does not mask the original error' do
    it 'still surfaces the original WorkerNotSentError via the global handler, not the release failure' do
      allow(WorkerJobService).to receive(:enqueue_ai_team_execution)
        .and_raise(WorkerJobService::WorkerNotSentError, 'original: worker unreachable')
      allow_any_instance_of(Ai::TeamExecution).to receive(:release_retry_claim!)
        .and_raise(StandardError, 'release_retry_claim! blew up')

      logged = []
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      post_retry

      expect(response).to have_http_status(:internal_server_error)
      expect(logged.any? { |m| m.include?('release_retry_claim! blew up') }).to be true
      expect(logged.any? { |m| m.include?('WorkerNotSentError') && m.include?('original: worker unreachable') }).to be true
    end
  end

  describe 'an UNPARSEABLE 2xx body counts as queued, not as a failure' do
    it 'renders retry_queued and marks the claim queued' do
      allow(WorkerJobService).to receive(:enqueue_ai_team_execution)
        .and_raise(WorkerJobService::WorkerResponseUnparseableError, 'bad json')

      post_retry

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)['data']['status']).to eq('retry_queued')
      expect(execution.reload.retry_state).to eq('queued')
    end
  end

  describe 'a losing request mid-flight (retry_state still "enqueuing")' do
    it 'returns 409 without touching the worker, and leaves the claim untouched' do
      execution.claim_retry!

      expect(WorkerJobService).not_to receive(:enqueue_ai_team_execution)
      post_retry

      expect(response).to have_http_status(:conflict)
      body = JSON.parse(response.body)
      expect(body['success']).to be false
      expect(body['error']).to eq('A retry is already in progress for this execution')
      expect(execution.reload.retry_state).to eq('enqueuing')
    end
  end

  describe 'a STALE "enqueuing" claim (the claiming process died before marking an outcome)' do
    it 'answers retry_outcome_unknown instead of 409, and does not enqueue' do
      execution.claim_retry!
      stale_at = (Ai::TeamExecution.retry_enqueuing_stale_after_seconds + 5).seconds.ago
      execution.update_column(:metadata, execution.metadata.merge('retry_queued_at' => stale_at.iso8601))

      expect(WorkerJobService).not_to receive(:enqueue_ai_team_execution)
      post_retry

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body['data']['status']).to eq('retry_outcome_unknown')
      expect(body['data']['original_execution_id']).to eq(execution.execution_id)
      # Staleness only changes what the response REPORTS — it must never
      # re-claim (that could create a duplicate on top of a request that is
      # in fact still live).
      expect(execution.reload.retry_state).to eq('enqueuing')
    end
  end
end
