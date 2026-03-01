# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ExecutionResourceAggregatorService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  describe '#aggregate' do
    context 'with no data' do
      it 'returns an empty array' do
        result = service.aggregate
        expect(result).to eq([])
      end
    end

    context 'with git_branch resources (worktrees)' do
      let(:user) { create(:user, account: account) }
      let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
      let!(:worktree) { create(:ai_worktree, worktree_session: session, branch_name: "feature/test-branch", status: "ready") }

      it 'includes worktree as git_branch resource' do
        result = service.aggregate(type: "git_branch")
        expect(result.length).to eq(1)
        expect(result.first[:resource_type]).to eq("git_branch")
        expect(result.first[:name]).to eq("feature/test-branch")
        expect(result.first[:status]).to eq("ready")
      end
    end

    context 'with type filter' do
      it 'only returns resources of specified type' do
        result = service.aggregate(type: "artifact")
        expect(result).to all(satisfy { |r| r[:resource_type] == "artifact" })
      end
    end

    context 'with search filter' do
      let(:user) { create(:user, account: account) }
      let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
      let!(:worktree1) { create(:ai_worktree, worktree_session: session, branch_name: "feature/search-target", status: "ready") }
      let!(:worktree2) { create(:ai_worktree, worktree_session: session, branch_name: "feature/other-branch", status: "ready") }

      it 'filters by name match' do
        result = service.aggregate(type: "git_branch", search: "search-target")
        expect(result.length).to eq(1)
        expect(result.first[:name]).to eq("feature/search-target")
      end
    end

    context 'with status filter' do
      let(:user) { create(:user, account: account) }
      let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
      let!(:ready_wt) { create(:ai_worktree, worktree_session: session, status: "ready") }
      let!(:pending_wt) { create(:ai_worktree, worktree_session: session, status: "pending") }

      it 'returns only matching statuses' do
        result = service.aggregate(type: "git_branch", status: "ready")
        statuses = result.map { |r| r[:status] }
        expect(statuses).to all(eq("ready"))
      end
    end

    context 'sorting' do
      let(:user) { create(:user, account: account) }
      let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
      let!(:older_wt) { create(:ai_worktree, worktree_session: session, created_at: 2.hours.ago) }
      let!(:newer_wt) { create(:ai_worktree, worktree_session: session, created_at: 1.hour.ago) }

      it 'sorts by created_at descending (most recent first)' do
        result = service.aggregate(type: "git_branch")
        expect(result.first[:source_id]).to eq(newer_wt.id)
        expect(result.last[:source_id]).to eq(older_wt.id)
      end
    end
  end

  describe '#counts' do
    it 'returns a hash with all resource types' do
      result = service.counts
      expect(result).to include(:total)
      Ai::ExecutionResourceAggregatorService::RESOURCE_TYPES.each do |type|
        expect(result).to have_key(type.to_sym)
      end
    end

    it 'returns zero counts when no data exists' do
      result = service.counts
      expect(result[:total]).to eq(0)
    end

    context 'with worktrees present' do
      let(:user) { create(:user, account: account) }
      let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
      let!(:worktree) { create(:ai_worktree, worktree_session: session) }

      it 'counts git_branch resources' do
        result = service.counts
        expect(result[:git_branch]).to eq(1)
        expect(result[:total]).to be >= 1
      end
    end
  end
end
