# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::GitPipeline, type: :model do
  subject(:pipeline) { build(:git_pipeline) }

  describe 'associations' do
    it { is_expected.to belong_to(:repository) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:jobs).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates status inclusion' do
      valid_statuses = %w[queued pending in_progress completed failed cancelled skipped]
      valid_statuses.each do |status|
        pipeline = build(:git_pipeline, status: status)
        expect(pipeline).to be_valid
      end
    end

    it 'validates conclusion inclusion' do
      valid_conclusions = %w[success failure cancelled skipped timed_out action_required neutral stale]
      valid_conclusions.each do |conclusion|
        pipeline = build(:git_pipeline, :completed, conclusion: conclusion)
        expect(pipeline).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }

    let!(:pending_pipeline) { create(:git_pipeline, :pending, repository: repo, account: account) }
    let!(:running_pipeline) { create(:git_pipeline, :running, repository: repo, account: account) }
    let!(:success_pipeline) { create(:git_pipeline, :success, repository: repo, account: account) }
    let!(:failure_pipeline) { create(:git_pipeline, :failure, repository: repo, account: account) }

    describe '.active' do
      it 'returns running and pending pipelines' do
        expect(described_class.active).to include(pending_pipeline, running_pipeline)
        expect(described_class.active).not_to include(success_pipeline, failure_pipeline)
      end
    end

    describe '.completed' do
      it 'returns completed pipelines' do
        expect(described_class.completed).to include(success_pipeline, failure_pipeline)
        expect(described_class.completed).not_to include(pending_pipeline, running_pipeline)
      end
    end

    describe '.running (alias)' do
      it 'returns in_progress pipelines' do
        expect(described_class.running).to include(running_pipeline)
        expect(described_class.running).not_to include(pending_pipeline)
      end
    end

    describe '.successful' do
      it 'returns only successful pipelines' do
        expect(described_class.successful).to include(success_pipeline)
        expect(described_class.successful).not_to include(failure_pipeline)
      end
    end

    describe '.failed' do
      it 'returns failed status pipelines' do
        failed = create(:git_pipeline, status: 'failed', repository: repo, account: account)
        expect(described_class.failed).to include(failed)
      end
    end

    describe '.recent' do
      it 'returns pipelines ordered by created_at desc with limit' do
        result = described_class.recent(2)
        expect(result.count).to eq(2)
      end
    end
  end

  describe 'instance methods' do
    describe '#in_progress?' do
      it 'returns true for in_progress pipelines' do
        pipeline = build(:git_pipeline, :running)
        expect(pipeline.in_progress?).to be true
      end

      it 'returns false for completed pipelines' do
        pipeline = build(:git_pipeline, :completed)
        expect(pipeline.in_progress?).to be false
      end
    end

    describe '#active?' do
      it 'returns true for queued, pending, and in_progress pipelines' do
        expect(build(:git_pipeline, status: 'queued').active?).to be true
        expect(build(:git_pipeline, status: 'pending').active?).to be true
        expect(build(:git_pipeline, status: 'in_progress').active?).to be true
      end

      it 'returns false for completed pipelines' do
        expect(build(:git_pipeline, status: 'completed').active?).to be false
      end
    end

    describe '#successful?' do
      it 'returns true for success conclusion' do
        pipeline = build(:git_pipeline, :success)
        expect(pipeline.successful?).to be true
      end

      it 'returns false for failure conclusion' do
        pipeline = build(:git_pipeline, :failure)
        expect(pipeline.successful?).to be false
      end
    end

    describe '#failed?' do
      it 'returns true for failure conclusion' do
        pipeline = build(:git_pipeline, :failure)
        expect(pipeline.failed?).to be true
      end
    end

    describe '#short_sha' do
      it 'returns first 7 characters of SHA' do
        pipeline = build(:git_pipeline, sha: '1234567890abcdef')
        expect(pipeline.short_sha).to eq('1234567')
      end

      it 'returns nil when sha is nil' do
        pipeline = build(:git_pipeline, sha: nil)
        expect(pipeline.short_sha).to be_nil
      end
    end

    describe '#branch_name' do
      it 'extracts branch name from ref' do
        pipeline = build(:git_pipeline, ref: 'refs/heads/main')
        expect(pipeline.branch_name).to eq('main')
      end

      it 'returns ref without prefix if not refs/heads/' do
        pipeline = build(:git_pipeline, ref: 'refs/tags/v1.0.0')
        expect(pipeline.branch_name).to eq('refs/tags/v1.0.0')
      end

      it 'returns nil when ref is nil' do
        pipeline = build(:git_pipeline, ref: nil)
        expect(pipeline.branch_name).to be_nil
      end
    end

    describe '#progress_percentage' do
      it 'calculates completion percentage' do
        pipeline = build(:git_pipeline, total_jobs: 10, completed_jobs: 5)
        expect(pipeline.progress_percentage).to eq(50)
      end

      it 'returns 0 when no jobs' do
        pipeline = build(:git_pipeline, total_jobs: 0, completed_jobs: 0)
        expect(pipeline.progress_percentage).to eq(0)
      end

      it 'returns 100 when finished' do
        pipeline = build(:git_pipeline, :completed, total_jobs: 5, completed_jobs: 5)
        expect(pipeline.progress_percentage).to eq(100)
      end
    end

    describe '#duration_formatted' do
      it 'formats duration in minutes and seconds' do
        pipeline = build(:git_pipeline, duration_seconds: 125)
        expect(pipeline.duration_formatted).to eq('2m 5s')
      end

      it 'handles hours' do
        pipeline = build(:git_pipeline, duration_seconds: 3725)
        expect(pipeline.duration_formatted).to eq('1h 2m 5s')
      end

      it 'returns nil when duration is nil' do
        pipeline = build(:git_pipeline, duration_seconds: nil)
        expect(pipeline.duration_formatted).to be_nil
      end
    end
  end

  describe 'status transitions' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }

    describe '#start!' do
      let(:pipeline) { create(:git_pipeline, :pending, repository: repo, account: account) }

      it 'transitions to in_progress status' do
        pipeline.start!
        expect(pipeline.status).to eq('in_progress')
        expect(pipeline.started_at).to be_present
      end
    end

    describe '#complete!' do
      let(:pipeline) { create(:git_pipeline, :running, repository: repo, account: account) }

      it 'transitions to completed with success' do
        pipeline.complete!('success')
        expect(pipeline.status).to eq('completed')
        expect(pipeline.conclusion).to eq('success')
        expect(pipeline.completed_at).to be_present
      end

      it 'transitions to completed with failure' do
        pipeline.complete!('failure')
        expect(pipeline.status).to eq('completed')
        expect(pipeline.conclusion).to eq('failure')
      end
    end

    describe '#cancel!' do
      let(:pipeline) { create(:git_pipeline, :running, repository: repo, account: account) }

      it 'transitions to cancelled with cancelled conclusion' do
        pipeline.cancel!
        expect(pipeline.status).to eq('cancelled')
        expect(pipeline.conclusion).to eq('cancelled')
        expect(pipeline.completed_at).to be_present
      end
    end
  end
end
