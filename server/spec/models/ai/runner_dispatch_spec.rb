# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::RunnerDispatch, type: :model do
  let(:account) { create(:account) }
  let(:worktree_session) { create(:ai_worktree_session, account: account) }
  let(:worktree) { create(:ai_worktree, worktree_session: worktree_session, account: account) }

  subject(:dispatch) do
    described_class.new(
      account: account,
      worktree_session: worktree_session,
      worktree: worktree,
      status: "pending"
    )
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:worktree_session).class_name("Ai::WorktreeSession") }
    it { is_expected.to belong_to(:worktree).class_name("Ai::Worktree") }
    it { is_expected.to belong_to(:git_runner).class_name("Devops::GitRunner").optional }
    it { is_expected.to belong_to(:git_repository).class_name("Devops::GitRepository").optional }
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(dispatch).to be_valid
    end

    it 'validates status inclusion' do
      dispatch.status = "invalid_status"
      expect(dispatch).not_to be_valid
      expect(dispatch.errors[:status]).to be_present
    end

    Ai::RunnerDispatch::STATUSES.each do |valid_status|
      it "allows status '#{valid_status}'" do
        dispatch.status = valid_status
        expect(dispatch).to be_valid
      end
    end
  end

  describe 'scopes' do
    before do
      dispatch.save!
    end

    describe '.pending' do
      it 'returns pending dispatches' do
        expect(described_class.pending).to include(dispatch)
      end
    end

    describe '.active' do
      it 'returns active dispatches' do
        expect(described_class.active).to include(dispatch)
      end

      it 'excludes completed dispatches' do
        dispatch.update!(status: "completed")
        expect(described_class.active).not_to include(dispatch)
      end

      it 'excludes failed dispatches' do
        dispatch.update!(status: "failed")
        expect(described_class.active).not_to include(dispatch)
      end
    end

    describe '.for_session' do
      it 'returns dispatches for a session' do
        expect(described_class.for_session(worktree_session.id)).to include(dispatch)
      end

      it 'excludes dispatches for other sessions' do
        other_session = create(:ai_worktree_session, account: account)
        expect(described_class.for_session(other_session.id)).not_to include(dispatch)
      end
    end

    describe '.recent' do
      it 'orders by created_at desc' do
        described_class.create!(
          account: account, worktree_session: worktree_session,
          worktree: worktree, status: "completed", created_at: 1.day.ago
        )
        expect(described_class.recent.first).to eq(dispatch)
      end
    end
  end

  describe '#dispatch_summary' do
    before { dispatch.save! }

    it 'returns a hash with expected keys' do
      summary = dispatch.dispatch_summary
      expect(summary).to include(
        :id, :account_id, :worktree_session_id, :worktree_id,
        :status, :created_at
      )
      expect(summary[:status]).to eq("pending")
    end
  end

  describe 'constants' do
    it 'defines STATUSES' do
      expect(described_class::STATUSES).to eq(%w[pending dispatched running completed failed])
    end
  end
end
