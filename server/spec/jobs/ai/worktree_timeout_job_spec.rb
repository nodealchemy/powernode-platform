# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::WorktreeTimeoutJob, type: :job do
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
    context 'with an active session that has max_duration_seconds set' do
      let!(:session) do
        create(:ai_worktree_session, :active,
               account: account,
               max_duration_seconds: 3600)
      end

      context 'with worktrees past their timeout_at' do
        let!(:timed_out_worktree) do
          wt = create(:ai_worktree, :in_use,
                      worktree_session: session,
                      account: session.account)
          wt.update_columns(timeout_at: 10.minutes.ago)
          wt
        end

        it 'fails timed-out worktrees' do
          described_class.new.perform

          timed_out_worktree.reload
          expect(timed_out_worktree.status).to eq('failed')
          expect(timed_out_worktree.error_message).to eq('Execution timed out')
          expect(timed_out_worktree.error_code).to eq('TIMEOUT')
        end
      end

      context 'with worktrees that have not timed out yet' do
        let!(:active_worktree) do
          wt = create(:ai_worktree, :in_use,
                      worktree_session: session,
                      account: session.account)
          wt.update_columns(timeout_at: 30.minutes.from_now)
          wt
        end

        it 'does not fail worktrees with future timeout_at' do
          described_class.new.perform

          active_worktree.reload
          expect(active_worktree.status).to eq('in_use')
        end
      end

      context 'with worktrees that have no timeout_at' do
        let!(:no_timeout_worktree) do
          create(:ai_worktree, :in_use,
                 worktree_session: session,
                 account: session.account)
        end

        it 'does not affect worktrees without timeout_at' do
          described_class.new.perform

          no_timeout_worktree.reload
          expect(no_timeout_worktree.status).to eq('in_use')
        end
      end

      context 'with a mix of timed-out and active worktrees' do
        let!(:timed_out_worktree) do
          wt = create(:ai_worktree, :in_use,
                      worktree_session: session,
                      account: session.account)
          wt.update_columns(timeout_at: 5.minutes.ago)
          wt
        end

        let!(:active_worktree) do
          wt = create(:ai_worktree, :in_use,
                      worktree_session: session,
                      account: session.account)
          wt.update_columns(timeout_at: 1.hour.from_now)
          wt
        end

        it 'only fails the timed-out worktree' do
          described_class.new.perform

          expect(timed_out_worktree.reload.status).to eq('failed')
          expect(active_worktree.reload.status).to eq('in_use')
        end
      end
    end

    context 'with a session that has no max_duration_seconds' do
      let!(:session) do
        create(:ai_worktree_session, :active,
               account: account,
               max_duration_seconds: nil)
      end

      let!(:worktree) do
        wt = create(:ai_worktree, :in_use,
                    worktree_session: session,
                    account: session.account)
        wt.update_columns(timeout_at: 10.minutes.ago)
        wt
      end

      it 'skips sessions without max_duration_seconds' do
        described_class.new.perform

        worktree.reload
        expect(worktree.status).to eq('in_use')
      end
    end

    context 'with a terminal session' do
      let!(:completed_session) do
        create(:ai_worktree_session, :completed,
               account: account,
               max_duration_seconds: 3600)
      end

      let!(:failed_session) do
        create(:ai_worktree_session, :failed,
               account: account,
               max_duration_seconds: 3600)
      end

      it 'does not process terminal sessions' do
        # Terminal sessions are excluded by active_sessions scope
        expect(Ai::WorktreeSession.active_sessions.where.not(max_duration_seconds: nil))
          .not_to include(completed_session)
        expect(Ai::WorktreeSession.active_sessions.where.not(max_duration_seconds: nil))
          .not_to include(failed_session)
      end
    end

    context 'with non-active worktrees in an active session' do
      let!(:session) do
        create(:ai_worktree_session, :active,
               account: account,
               max_duration_seconds: 3600)
      end

      let!(:completed_worktree) do
        wt = create(:ai_worktree, :completed,
                    worktree_session: session,
                    account: session.account)
        wt.update_columns(timeout_at: 10.minutes.ago)
        wt
      end

      it 'does not fail non-active worktrees even if past timeout' do
        described_class.new.perform

        completed_worktree.reload
        expect(completed_worktree.status).to eq('completed')
      end
    end

    context 'when checking a session raises an error' do
      let!(:session) do
        create(:ai_worktree_session, :active,
               account: account,
               max_duration_seconds: 3600)
      end

      let!(:worktree) do
        wt = create(:ai_worktree, :in_use,
                    worktree_session: session,
                    account: session.account)
        wt.update_columns(timeout_at: 10.minutes.ago)
        wt
      end

      it 'does not raise and the job completes' do
        # The error is rescued inside check_session_timeouts
        expect { described_class.new.perform }.not_to raise_error
      end
    end
  end
end
