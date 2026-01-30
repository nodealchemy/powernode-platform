# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GatewayConnectionJob, type: :model do
  describe 'validations' do
    subject { build(:gateway_connection_job) }

    it { should validate_presence_of(:gateway) }
    it { should validate_inclusion_of(:gateway).in_array(%w[stripe paypal]) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending processing completed failed]) }
    it { should validate_presence_of(:operation) }
  end

  describe 'attribute aliases' do
    let(:job) { build(:gateway_connection_job, payload: { 'key' => 'value' }, response: { 'result' => 'ok' }) }

    describe '#config_data' do
      it 'returns payload' do
        expect(job.config_data).to eq({ 'key' => 'value' })
      end
    end

    describe '#result' do
      it 'returns response' do
        expect(job.result).to eq({ 'result' => 'ok' })
      end
    end
  end

  describe 'scopes' do
    let!(:pending_job) { create(:gateway_connection_job, :pending) }
    let!(:processing_job) { create(:gateway_connection_job, :processing) }
    let!(:completed_job) { create(:gateway_connection_job, :completed) }
    let!(:failed_job) { create(:gateway_connection_job, :failed) }

    describe '.pending' do
      it 'returns only pending jobs' do
        expect(GatewayConnectionJob.pending).to include(pending_job)
        expect(GatewayConnectionJob.pending).not_to include(processing_job, completed_job, failed_job)
      end
    end

    describe '.processing' do
      it 'returns only processing jobs' do
        expect(GatewayConnectionJob.processing).to include(processing_job)
        expect(GatewayConnectionJob.processing).not_to include(pending_job, completed_job, failed_job)
      end
    end

    describe '.completed' do
      it 'returns only completed jobs' do
        expect(GatewayConnectionJob.completed).to include(completed_job)
        expect(GatewayConnectionJob.completed).not_to include(pending_job, processing_job, failed_job)
      end
    end

    describe '.failed' do
      it 'returns only failed jobs' do
        expect(GatewayConnectionJob.failed).to include(failed_job)
        expect(GatewayConnectionJob.failed).not_to include(pending_job, processing_job, completed_job)
      end
    end

    describe '.finished' do
      it 'returns completed and failed jobs' do
        expect(GatewayConnectionJob.finished).to include(completed_job, failed_job)
        expect(GatewayConnectionJob.finished).not_to include(pending_job, processing_job)
      end
    end
  end

  describe 'instance methods' do
    describe '#finished?' do
      it 'returns true for completed jobs' do
        job = build(:gateway_connection_job, :completed)
        expect(job.finished?).to be true
      end

      it 'returns true for failed jobs' do
        job = build(:gateway_connection_job, :failed)
        expect(job.finished?).to be true
      end

      it 'returns false for pending jobs' do
        job = build(:gateway_connection_job, :pending)
        expect(job.finished?).to be false
      end

      it 'returns false for processing jobs' do
        job = build(:gateway_connection_job, :processing)
        expect(job.finished?).to be false
      end
    end

    describe '#success?' do
      it 'returns true when completed with success response' do
        job = build(:gateway_connection_job, status: 'completed', response: { 'success' => true })
        expect(job.success?).to be true
      end

      it 'returns false when completed with failed response' do
        job = build(:gateway_connection_job, status: 'completed', response: { 'success' => false })
        expect(job.success?).to be false
      end

      it 'returns false when status is not completed' do
        job = build(:gateway_connection_job, status: 'failed', response: { 'success' => true })
        expect(job.success?).to be false
      end

      it 'returns false when response is nil' do
        job = build(:gateway_connection_job, status: 'completed', response: nil)
        expect(job.success?).to be false
      end
    end

    describe '#duration' do
      it 'returns nil if completed_at is missing' do
        job = build(:gateway_connection_job, completed_at: nil)
        expect(job.duration).to be_nil
      end

      it 'calculates duration from created_at to completed_at' do
        job = create(:gateway_connection_job)
        job.update!(completed_at: 5.minutes.from_now)
        expect(job.duration).to be_within(1).of(300)
      end
    end
  end

  describe 'gateway types' do
    it 'accepts stripe gateway' do
      job = build(:gateway_connection_job, :stripe)
      expect(job).to be_valid
      expect(job.gateway).to eq('stripe')
    end

    it 'accepts paypal gateway' do
      job = build(:gateway_connection_job, :paypal)
      expect(job).to be_valid
      expect(job.gateway).to eq('paypal')
    end

    it 'rejects invalid gateway' do
      job = build(:gateway_connection_job, gateway: 'invalid')
      expect(job).not_to be_valid
      expect(job.errors[:gateway]).to be_present
    end
  end
end
