# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WorkerActivity, type: :model do
  describe 'associations' do
    it { should belong_to(:worker) }
  end

  describe 'validations' do
    subject { build(:worker_activity) }

    it { should validate_presence_of(:activity_type) }
    it { should validate_presence_of(:occurred_at) }
  end

  describe 'enums' do
    it 'defines activity_type enum with expected keys' do
      expect(WorkerActivity.activity_types.keys).to include(
        'authentication',
        'job_enqueue',
        'api_request',
        'health_check'
      )
    end

    describe 'enum predicates' do
      let(:activity) { build(:worker_activity, activity_type: 'authentication') }

      it 'provides prefixed predicate methods' do
        expect(activity).to respond_to(:activity_type_authentication?)
        expect(activity.activity_type_authentication?).to be true
      end
    end
  end

  describe 'scopes' do
    let(:worker) { create(:worker) }
    let!(:recent_activity) { create(:worker_activity, :recent, worker: worker) }
    let!(:old_activity) { create(:worker_activity, :old, worker: worker) }
    let!(:successful_activity) { create(:worker_activity, :successful, worker: worker) }
    let!(:failed_activity) { create(:worker_activity, :failed, worker: worker) }
    let!(:auth_activity) { create(:worker_activity, :authentication, worker: worker) }
    let!(:job_activity) { create(:worker_activity, :job_enqueue, worker: worker) }

    describe '.recent' do
      it 'returns activities from last 24 hours' do
        expect(WorkerActivity.recent).to include(recent_activity)
        expect(WorkerActivity.recent).not_to include(old_activity)
      end
    end

    describe '.by_action' do
      it 'returns activities by activity_type' do
        expect(WorkerActivity.by_action('authentication')).to include(auth_activity)
        expect(WorkerActivity.by_action('authentication')).not_to include(job_activity)
      end
    end

    describe '.successful' do
      it 'returns only successful activities' do
        expect(WorkerActivity.successful).to include(successful_activity)
        expect(WorkerActivity.successful).not_to include(failed_activity)
      end
    end

    describe '.failed' do
      it 'returns only failed activities' do
        expect(WorkerActivity.failed).to include(failed_activity)
        expect(WorkerActivity.failed).not_to include(successful_activity)
      end
    end
  end

  describe 'instance methods' do
    describe '#successful?' do
      it 'returns true when details status is success' do
        activity = build(:worker_activity, :successful)
        expect(activity.successful?).to be true
      end

      it 'returns false when details status is error' do
        activity = build(:worker_activity, :failed)
        expect(activity.successful?).to be false
      end
    end

    describe '#failed?' do
      it 'returns true when details status is error' do
        activity = build(:worker_activity, :failed)
        expect(activity.failed?).to be true
      end

      it 'returns false when details status is success' do
        activity = build(:worker_activity, :successful)
        expect(activity.failed?).to be false
      end
    end

    describe '#duration' do
      it 'returns duration from details hash' do
        activity = build(:worker_activity, :api_request)
        expect(activity.duration).to eq(150.0)
      end

      it 'returns nil when duration not present' do
        activity = build(:worker_activity, :authentication)
        expect(activity.duration).to be_nil
      end
    end

    describe '#error_message' do
      it 'returns error message from details hash' do
        activity = build(:worker_activity, :error_occurred)
        expect(activity.error_message).to eq('Connection timeout')
      end

      it 'returns nil when error_message not present' do
        activity = build(:worker_activity, :successful)
        expect(activity.error_message).to be_nil
      end
    end

    describe '#request_path' do
      it 'returns request_path from details hash' do
        activity = build(:worker_activity, :api_request)
        expect(activity.request_path).to eq('/api/v1/test')
      end

      it 'returns nil when request_path not present' do
        activity = build(:worker_activity, :authentication)
        expect(activity.request_path).to be_nil
      end
    end

    describe '#response_status' do
      it 'returns response_status from details hash' do
        activity = build(:worker_activity, :api_request)
        expect(activity.response_status).to eq(200)
      end

      it 'returns nil when response_status not present' do
        activity = build(:worker_activity, :authentication)
        expect(activity.response_status).to be_nil
      end
    end
  end

  describe 'callbacks' do
    describe 'occurred_at handling' do
      it 'preserves occurred_at when provided' do
        specific_time = 2.hours.ago
        activity = create(:worker_activity, occurred_at: specific_time)
        expect(activity.occurred_at).to be_within(1.second).of(specific_time)
      end
    end
  end
end
