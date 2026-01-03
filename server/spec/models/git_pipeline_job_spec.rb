# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GitPipelineJob, type: :model do
  subject(:job) { build(:git_pipeline_job) }

  describe 'associations' do
    it { is_expected.to belong_to(:git_pipeline) }
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates status inclusion' do
      valid_statuses = %w[queued pending in_progress completed failed cancelled skipped]
      valid_statuses.each do |status|
        job = build(:git_pipeline_job, status: status)
        expect(job).to be_valid
      end
    end

    it 'validates conclusion inclusion' do
      valid_conclusions = %w[success failure cancelled skipped]
      valid_conclusions.each do |conclusion|
        job = build(:git_pipeline_job, :success, conclusion: conclusion)
        expect(job).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, git_provider: provider, account: account) }
    let(:repo) { create(:git_repository, git_provider_credential: credential, account: account) }
    let(:pipeline) { create(:git_pipeline, git_repository: repo, account: account) }

    let!(:pending_job) { create(:git_pipeline_job, :pending, git_pipeline: pipeline, account: account) }
    let!(:running_job) { create(:git_pipeline_job, :running, git_pipeline: pipeline, account: account) }
    let!(:success_job) { create(:git_pipeline_job, :success, git_pipeline: pipeline, account: account) }
    let!(:failure_job) { create(:git_pipeline_job, :failure, git_pipeline: pipeline, account: account) }

    describe '.running' do
      it 'returns in_progress jobs' do
        expect(described_class.running).to include(running_job)
        expect(described_class.running).not_to include(pending_job, success_job)
      end
    end

    describe '.in_progress' do
      it 'returns in_progress jobs' do
        expect(described_class.in_progress).to include(running_job)
      end
    end

    describe '.completed' do
      it 'returns completed jobs' do
        expect(described_class.completed).to include(success_job, failure_job)
        expect(described_class.completed).not_to include(running_job)
      end
    end

    describe '.successful' do
      it 'returns only successful jobs' do
        expect(described_class.successful).to include(success_job)
        expect(described_class.successful).not_to include(failure_job)
      end
    end

    describe '.failed' do
      it 'returns failed status jobs' do
        failed = create(:git_pipeline_job, status: 'failed', git_pipeline: pipeline, account: account)
        expect(described_class.failed).to include(failed)
      end
    end
  end

  describe 'instance methods' do
    describe '#in_progress?' do
      it 'returns true for in_progress jobs' do
        job = build(:git_pipeline_job, :running)
        expect(job.in_progress?).to be true
      end

      it 'returns false for completed jobs' do
        job = build(:git_pipeline_job, :success)
        expect(job.in_progress?).to be false
      end
    end

    describe '#successful?' do
      it 'returns true for successful jobs' do
        job = build(:git_pipeline_job, :success)
        expect(job.successful?).to be true
      end
    end

    describe '#failed?' do
      it 'returns true for failed jobs' do
        job = build(:git_pipeline_job, :failure)
        expect(job.failed?).to be true
      end
    end

    describe '#duration_formatted' do
      it 'formats duration' do
        job = build(:git_pipeline_job, duration_seconds: 95)
        expect(job.duration_formatted).to eq('1m 35s')
      end

      it 'returns nil when duration is nil' do
        job = build(:git_pipeline_job, duration_seconds: nil)
        expect(job.duration_formatted).to be_nil
      end
    end

    describe '#logs_available?' do
      it 'returns true when logs_content is present' do
        job = build(:git_pipeline_job, :with_logs)
        expect(job.logs_available?).to be true
      end

      it 'returns true when logs_url is present' do
        job = build(:git_pipeline_job, logs_url: 'https://example.com/logs')
        expect(job.logs_available?).to be true
      end

      it 'returns false when no logs' do
        job = build(:git_pipeline_job, logs_content: nil, logs_url: nil)
        expect(job.logs_available?).to be false
      end
    end

    describe '#has_logs? (alias)' do
      it 'works like logs_available?' do
        job = build(:git_pipeline_job, :with_logs)
        expect(job.has_logs?).to be true
      end
    end

    describe '#total_steps_count' do
      it 'returns number of steps' do
        job = build(:git_pipeline_job, :with_steps)
        expect(job.total_steps_count).to eq(3)
      end

      it 'returns 0 when no steps' do
        job = build(:git_pipeline_job, steps: [])
        expect(job.total_steps_count).to eq(0)
      end
    end

    describe '#step_count (alias)' do
      it 'works like total_steps_count' do
        job = build(:git_pipeline_job, :with_steps)
        expect(job.step_count).to eq(3)
      end
    end

    describe '#completed_steps_count' do
      it 'returns count of completed steps' do
        job = build(:git_pipeline_job, :with_steps)
        expect(job.completed_steps_count).to eq(2)
      end
    end

    describe '#completed_steps (alias)' do
      it 'works like completed_steps_count' do
        job = build(:git_pipeline_job, :with_steps)
        expect(job.completed_steps).to eq(2)
      end
    end

    describe '#runner_info' do
      it 'returns runner information' do
        job = build(:git_pipeline_job, runner_name: 'ubuntu-latest', runner_id: '123', runner_os: 'Linux')
        expect(job.runner_info).to eq({ name: 'ubuntu-latest', id: '123', os: 'Linux' })
      end
    end
  end

  describe 'status transitions' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, git_provider: provider, account: account) }
    let(:repo) { create(:git_repository, git_provider_credential: credential, account: account) }
    let(:pipeline) { create(:git_pipeline, git_repository: repo, account: account) }

    describe '#start!' do
      let(:job) { create(:git_pipeline_job, :pending, git_pipeline: pipeline, account: account) }

      it 'transitions to in_progress status' do
        job.start!('ubuntu-latest', 'runner-1', 'Linux')

        expect(job.status).to eq('in_progress')
        expect(job.started_at).to be_present
        expect(job.runner_name).to eq('ubuntu-latest')
        expect(job.runner_id).to eq('runner-1')
        expect(job.runner_os).to eq('Linux')
      end
    end

    describe '#complete!' do
      let(:job) { create(:git_pipeline_job, :running, git_pipeline: pipeline, account: account) }

      it 'transitions to completed with conclusion' do
        job.complete!('success')

        expect(job.status).to eq('completed')
        expect(job.conclusion).to eq('success')
        expect(job.completed_at).to be_present
      end
    end
  end
end
