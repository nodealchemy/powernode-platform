# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ConflictDetectionJob, type: :job do
  let(:account) { create(:account) }

  before do
    allow(AiOrchestrationChannel).to receive(:broadcast_worktree_session_event)
    allow(AiOrchestrationChannel).to receive(:broadcast_worktree_event)
  end

  describe 'job configuration' do
    it 'is queued in the ai_execution queue' do
      expect(described_class.new.queue_name).to eq('ai_execution')
    end
  end

  describe '#perform' do
    context 'with an active session' do
      let!(:session) do
        create(:ai_worktree_session, :active, account: account)
      end

      let(:service) { instance_double(Ai::Git::ConflictDetectionService) }

      before do
        allow(Ai::Git::ConflictDetectionService).to receive(:new)
          .with(session: session)
          .and_return(service)
        allow(service).to receive(:detect)
          .and_return({ conflicts: [], matrix: {} })
      end

      it 'creates a ConflictDetectionService with the session' do
        described_class.new.perform(session.id)

        expect(Ai::Git::ConflictDetectionService).to have_received(:new)
          .with(session: session)
      end

      it 'calls detect on the service' do
        described_class.new.perform(session.id)

        expect(service).to have_received(:detect)
      end
    end

    context 'with a pending session' do
      let!(:session) do
        create(:ai_worktree_session, account: account, status: 'pending')
      end

      let(:service) { instance_double(Ai::Git::ConflictDetectionService) }

      before do
        allow(Ai::Git::ConflictDetectionService).to receive(:new)
          .with(session: session)
          .and_return(service)
        allow(service).to receive(:detect)
          .and_return({ conflicts: [], matrix: {} })
      end

      it 'processes non-terminal sessions' do
        described_class.new.perform(session.id)

        expect(service).to have_received(:detect)
      end
    end

    context 'with a terminal session' do
      let!(:completed_session) do
        create(:ai_worktree_session, :completed, account: account)
      end

      it 'returns early without creating the service' do
        expect(Ai::Git::ConflictDetectionService).not_to receive(:new)

        described_class.new.perform(completed_session.id)
      end

      it 'does not change session status' do
        described_class.new.perform(completed_session.id)

        expect(completed_session.reload.status).to eq('completed')
      end
    end

    context 'with a failed session' do
      let!(:failed_session) do
        create(:ai_worktree_session, :failed, account: account)
      end

      it 'returns early for failed sessions' do
        expect(Ai::Git::ConflictDetectionService).not_to receive(:new)

        described_class.new.perform(failed_session.id)
      end
    end

    context 'with a cancelled session' do
      let!(:cancelled_session) do
        create(:ai_worktree_session, :cancelled, account: account)
      end

      it 'returns early for cancelled sessions' do
        expect(Ai::Git::ConflictDetectionService).not_to receive(:new)

        described_class.new.perform(cancelled_session.id)
      end
    end

    context 'when an error occurs' do
      let!(:session) do
        create(:ai_worktree_session, :active, account: account)
      end

      before do
        allow(Ai::Git::ConflictDetectionService).to receive(:new)
          .and_raise(StandardError, 'Unexpected failure')
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with(/ConflictDetection.*Job failed.*#{session.id}.*Unexpected failure/)

        described_class.new.perform(session.id)
      end

      it 'does not raise the error' do
        expect {
          described_class.new.perform(session.id)
        }.not_to raise_error
      end
    end

    context 'when session is not found' do
      it 'logs the error and does not raise' do
        expect(Rails.logger).to receive(:error).with(/ConflictDetection.*Job failed/)

        expect {
          described_class.new.perform(SecureRandom.uuid)
        }.not_to raise_error
      end
    end
  end
end
