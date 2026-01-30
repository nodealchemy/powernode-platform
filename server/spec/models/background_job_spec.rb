# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BackgroundJob, type: :model do
  describe 'validations' do
    subject { build(:background_job) }

    it { should validate_presence_of(:job_id) }
    it { should validate_presence_of(:job_type) }

    it 'validates uniqueness of job_id' do
      create(:background_job, job_id: 'unique_job_123')
      job = build(:background_job, job_id: 'unique_job_123')
      expect(job).not_to be_valid
      expect(job.errors[:job_id]).to include('has already been taken')
    end
  end

  describe 'enum' do
    it 'defines status enum' do
      expect(BackgroundJob.statuses).to include(
        'pending' => 'pending',
        'processing' => 'processing',
        'completed' => 'completed',
        'failed' => 'failed',
        'cancelled' => 'cancelled'
      )
    end
  end

  describe 'scopes' do
    let!(:pending_job) { create(:background_job, :pending) }
    let!(:processing_job) { create(:background_job, status: 'processing') }
    let!(:completed_job) { create(:background_job, status: 'completed') }
    let!(:failed_job) { create(:background_job, status: 'failed') }
    let!(:cancelled_job) { create(:background_job, status: 'cancelled') }

    describe '.recent' do
      it 'orders by created_at descending' do
        jobs = BackgroundJob.recent
        expect(jobs.first.created_at).to be >= jobs.last.created_at
      end
    end

    describe '.active' do
      it 'returns pending and processing jobs' do
        expect(BackgroundJob.active).to include(pending_job, processing_job)
        expect(BackgroundJob.active).not_to include(completed_job, failed_job, cancelled_job)
      end
    end

    describe '.finished' do
      it 'returns completed, failed, and cancelled jobs' do
        expect(BackgroundJob.finished).to include(completed_job, failed_job, cancelled_job)
        expect(BackgroundJob.finished).not_to include(pending_job, processing_job)
      end
    end
  end

  describe 'callbacks' do
    describe 'set_default_status' do
      it 'sets status to pending on create if not provided' do
        job = BackgroundJob.new(job_id: 'test_123', job_type: 'TestJob')
        job.valid?
        expect(job.status).to eq('pending')
      end
    end

    describe 'update_timestamps' do
      it 'sets started_at when status changes to processing' do
        job = create(:background_job, :pending)
        job.update!(status: 'processing')
        expect(job.started_at).to be_present
      end

      it 'sets finished_at when status changes to completed' do
        job = create(:background_job, status: 'processing')
        job.update!(status: 'completed')
        expect(job.finished_at).to be_present
      end

      it 'sets failed_at and finished_at when status changes to failed' do
        job = create(:background_job, status: 'processing')
        job.update!(status: 'failed')
        expect(job.failed_at).to be_present
        expect(job.finished_at).to be_present
      end
    end
  end

  describe 'class methods' do
    describe '.create_for_sidekiq_job' do
      it 'creates a job with sidekiq jid' do
        job = BackgroundJob.create_for_sidekiq_job('jid_12345', 'MyWorker', { foo: 'bar' })
        expect(job).to be_persisted
        expect(job.job_id).to eq('jid_12345')
        expect(job.job_type).to eq('MyWorker')
        expect(job.arguments).to eq({ 'foo' => 'bar' })
        expect(job.status).to eq('pending')
      end
    end
  end

  describe 'instance methods' do
    let(:job) { create(:background_job) }

    describe '#mark_in_progress!' do
      it 'updates status to processing and sets started_at' do
        job.mark_in_progress!
        expect(job.status).to eq('processing')
        expect(job.started_at).to be_present
      end
    end

    describe '#mark_processing!' do
      it 'is an alias for mark_in_progress!' do
        job.mark_processing!
        expect(job.status).to eq('processing')
      end
    end

    describe '#mark_completed!' do
      it 'updates status to completed and sets finished_at' do
        job.mark_completed!
        expect(job.status).to eq('completed')
        expect(job.finished_at).to be_present
      end
    end

    describe '#mark_failed!' do
      it 'updates status to failed with error details' do
        job.mark_failed!('Something went wrong', 'backtrace here')
        expect(job.status).to eq('failed')
        expect(job.error_message).to eq('Something went wrong')
        expect(job.backtrace).to eq('backtrace here')
        expect(job.failed_at).to be_present
        expect(job.finished_at).to be_present
      end
    end

    describe '#duration' do
      it 'returns nil if finished_at or started_at is missing' do
        expect(job.duration).to be_nil
      end

      it 'calculates duration when both timestamps present' do
        job.update!(started_at: 10.minutes.ago, finished_at: 5.minutes.ago)
        expect(job.duration).to be_within(1).of(300) # 5 minutes in seconds
      end
    end

    describe '#progress_percentage' do
      it 'returns 100 for completed jobs' do
        job.update!(status: 'completed')
        expect(job.progress_percentage).to eq(100)
      end

      it 'returns 0 for failed jobs' do
        job.update!(status: 'failed')
        expect(job.progress_percentage).to eq(0)
      end

      it 'returns 50 for processing jobs' do
        job.update!(status: 'processing')
        expect(job.progress_percentage).to eq(50)
      end

      it 'returns 0 for pending jobs' do
        expect(job.progress_percentage).to eq(0)
      end
    end

    describe '#parameters' do
      it 'returns arguments (alias)' do
        job.update!(arguments: { 'key' => 'value' })
        expect(job.parameters).to eq({ 'key' => 'value' })
      end
    end

    describe '#result' do
      it 'returns nil' do
        expect(job.result).to be_nil
      end
    end

    describe '#error_details' do
      it 'returns backtrace (alias)' do
        job.update!(backtrace: 'error trace')
        expect(job.error_details).to eq('error trace')
      end
    end

    describe '#completed_at' do
      it 'returns finished_at (alias)' do
        timestamp = Time.current
        job.update!(finished_at: timestamp)
        expect(job.completed_at).to eq(timestamp)
      end
    end
  end
end
