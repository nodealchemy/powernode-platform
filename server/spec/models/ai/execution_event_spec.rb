# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ExecutionEvent, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:account) }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_execution_event) }

    it { should validate_presence_of(:source_type) }
    it { should validate_presence_of(:source_id) }
    it { should validate_presence_of(:event_type) }
    it { should validate_presence_of(:status) }
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let(:account) { create(:account) }

    describe '.by_source_type' do
      let!(:agent_event) { create(:ai_execution_event, account: account, source_type: 'Ai::Agent') }
      let!(:workflow_event) { create(:ai_execution_event, account: account, source_type: 'Ai::Workflow') }

      it 'returns events for the specified source type' do
        expect(described_class.by_source_type('Ai::Agent')).to include(agent_event)
        expect(described_class.by_source_type('Ai::Agent')).not_to include(workflow_event)
      end

      it 'returns all events when source type is nil' do
        expect(described_class.by_source_type(nil)).to include(agent_event, workflow_event)
      end

      it 'returns all events when source type is blank' do
        expect(described_class.by_source_type('')).to include(agent_event, workflow_event)
      end
    end

    describe '.by_status' do
      let!(:completed_event) { create(:ai_execution_event, account: account, status: 'completed') }
      let!(:failed_event) { create(:ai_execution_event, account: account, status: 'failed') }

      it 'returns events with the specified status' do
        expect(described_class.by_status('completed')).to include(completed_event)
        expect(described_class.by_status('completed')).not_to include(failed_event)
      end

      it 'returns all events when status is nil' do
        expect(described_class.by_status(nil)).to include(completed_event, failed_event)
      end
    end

    describe '.by_event_type' do
      let!(:start_event) { create(:ai_execution_event, account: account, event_type: 'execution_start') }
      let!(:end_event) { create(:ai_execution_event, account: account, event_type: 'execution_end') }

      it 'returns events of the specified event type' do
        expect(described_class.by_event_type('execution_start')).to include(start_event)
        expect(described_class.by_event_type('execution_start')).not_to include(end_event)
      end

      it 'returns all events when event type is nil' do
        expect(described_class.by_event_type(nil)).to include(start_event, end_event)
      end
    end

    describe '.recent' do
      let!(:old_event) { create(:ai_execution_event, account: account, created_at: 2.days.ago) }
      let!(:new_event) { create(:ai_execution_event, account: account, created_at: 1.minute.ago) }

      it 'returns events ordered by created_at desc' do
        results = described_class.recent
        expect(results.first).to eq(new_event)
      end

      it 'defaults to 50 records' do
        expect(described_class.recent.limit_value).to eq(50)
      end

      it 'accepts a custom limit' do
        expect(described_class.recent(10).limit_value).to eq(10)
      end
    end

    describe '.in_time_range' do
      let!(:old_event) { create(:ai_execution_event, account: account, created_at: 3.hours.ago) }
      let!(:recent_event) { create(:ai_execution_event, account: account, created_at: 30.minutes.ago) }

      it 'returns events within the specified time range' do
        results = described_class.in_time_range(1.hour.ago)
        expect(results).to include(recent_event)
        expect(results).not_to include(old_event)
      end

      it 'accepts a custom end time' do
        results = described_class.in_time_range(4.hours.ago, 2.hours.ago)
        expect(results).to include(old_event)
        expect(results).not_to include(recent_event)
      end
    end

    describe '.with_errors' do
      let!(:error_event) { create(:ai_execution_event, account: account, error_class: 'RuntimeError') }
      let!(:clean_event) { create(:ai_execution_event, account: account, error_class: nil) }

      it 'returns only events with error_class present' do
        expect(described_class.with_errors).to include(error_event)
        expect(described_class.with_errors).not_to include(clean_event)
      end
    end

    describe '.by_account' do
      let(:other_account) { create(:account) }
      let!(:event_a) { create(:ai_execution_event, account: account) }
      let!(:event_b) { create(:ai_execution_event, account: other_account) }

      it 'returns events for the specified account' do
        expect(described_class.by_account(account.id)).to include(event_a)
        expect(described_class.by_account(account.id)).not_to include(event_b)
      end
    end
  end

  # ==========================================
  # Instance Methods
  # ==========================================
  describe '#source' do
    let(:account) { create(:account) }
    let(:agent) { create(:ai_agent, account: account) }

    it 'returns the source object when it exists' do
      event = create(:ai_execution_event,
                     account: account,
                     source_type: 'Ai::Agent',
                     source_id: agent.id)

      expect(event.source).to eq(agent)
    end

    it 'returns nil when the source does not exist' do
      event = create(:ai_execution_event,
                     account: account,
                     source_type: 'Ai::Agent',
                     source_id: SecureRandom.uuid)

      expect(event.source).to be_nil
    end

    it 'returns nil when the source_type is an invalid class' do
      event = create(:ai_execution_event,
                     account: account,
                     source_type: 'NonExistentClass',
                     source_id: SecureRandom.uuid)

      expect(event.source).to be_nil
    end
  end

  describe '#error?' do
    let(:account) { create(:account) }

    it 'returns true when error_class is present' do
      event = build(:ai_execution_event, account: account, error_class: 'RuntimeError', error_message: nil)
      expect(event.error?).to be true
    end

    it 'returns true when error_message is present' do
      event = build(:ai_execution_event, account: account, error_class: nil, error_message: 'Something went wrong')
      expect(event.error?).to be true
    end

    it 'returns true when both error_class and error_message are present' do
      event = build(:ai_execution_event, account: account, error_class: 'RuntimeError', error_message: 'fail')
      expect(event.error?).to be true
    end

    it 'returns false when neither error_class nor error_message is present' do
      event = build(:ai_execution_event, account: account, error_class: nil, error_message: nil)
      expect(event.error?).to be false
    end
  end

  # ==========================================
  # Factories
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_execution_event)).to be_valid
    end
  end
end
