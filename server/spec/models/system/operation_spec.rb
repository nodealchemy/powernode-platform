# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::Operation, type: :model do
  let(:account) { create(:account) }
  let(:node) { create(:system_node) }

  describe 'constants' do
    it 'defines valid statuses' do
      expect(described_class::STATUSES).to eq(%w[pending scheduled running complete failed aborted cancelled])
    end

    it 'defines valid commands' do
      expect(described_class::COMMANDS).to include(
        'start', 'stop', 'restart', 'terminate', 'reboot',
        'provision', 'deprovision',
        'create_volume', 'delete_volume', 'attach_volume', 'detach_volume',
        'sync_modules', 'apply_config',
        'backup', 'restore', 'custom'
      )
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:operable).optional }
    it { is_expected.to belong_to(:initiated_by).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:system_operation, account: account) }

    it { is_expected.to validate_presence_of(:command) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
    it { is_expected.to validate_numericality_of(:progress).only_integer.is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
  end

  describe 'scopes' do
    let!(:pending_op) { create(:system_operation, account: account, status: 'pending') }
    let!(:scheduled_op) { create(:system_operation, account: account, status: 'scheduled') }
    let!(:running_op) { create(:system_operation, account: account, status: 'running') }
    let!(:complete_op) { create(:system_operation, account: account, status: 'complete') }
    let!(:failed_op) { create(:system_operation, account: account, status: 'failed') }
    let!(:aborted_op) { create(:system_operation, account: account, status: 'aborted') }
    let!(:cancelled_op) { create(:system_operation, account: account, status: 'cancelled') }

    describe 'status scopes' do
      it '.pending returns only pending operations' do
        expect(described_class.pending).to include(pending_op)
        expect(described_class.pending).not_to include(running_op)
      end

      it '.scheduled returns only scheduled operations' do
        expect(described_class.scheduled).to include(scheduled_op)
      end

      it '.running returns only running operations' do
        expect(described_class.running).to include(running_op)
      end

      it '.complete returns only complete operations' do
        expect(described_class.complete).to include(complete_op)
      end

      it '.failed returns only failed operations' do
        expect(described_class.failed).to include(failed_op)
      end
    end

    describe '.active' do
      it 'returns pending, scheduled, and running operations' do
        expect(described_class.active).to include(pending_op, scheduled_op, running_op)
        expect(described_class.active).not_to include(complete_op, failed_op, aborted_op, cancelled_op)
      end
    end

    describe '.finished' do
      it 'returns complete, failed, aborted, and cancelled operations' do
        expect(described_class.finished).to include(complete_op, failed_op, aborted_op, cancelled_op)
        expect(described_class.finished).not_to include(pending_op, scheduled_op, running_op)
      end
    end
  end

  describe 'status predicates' do
    let(:operation) { build(:system_operation, account: account) }

    described_class::STATUSES.each do |status|
      describe "##{status}?" do
        it "returns true when status is #{status}" do
          operation.status = status
          expect(operation.public_send("#{status}?")).to be true
        end
      end
    end
  end

  describe 'state transition predicates' do
    let(:operation) { build(:system_operation, account: account) }

    describe '#can_start?' do
      it 'returns true for pending operations' do
        operation.status = 'pending'
        expect(operation.can_start?).to be true
      end

      it 'returns true for scheduled operations' do
        operation.status = 'scheduled'
        expect(operation.can_start?).to be true
      end

      it 'returns false for running operations' do
        operation.status = 'running'
        expect(operation.can_start?).to be false
      end
    end

    describe '#can_complete?' do
      it 'returns true for running operations' do
        operation.status = 'running'
        expect(operation.can_complete?).to be true
      end

      it 'returns false for pending operations' do
        operation.status = 'pending'
        expect(operation.can_complete?).to be false
      end
    end

    describe '#can_fail?' do
      it 'returns true for running operations' do
        operation.status = 'running'
        expect(operation.can_fail?).to be true
      end
    end

    describe '#can_abort?' do
      it 'returns true for running operations' do
        operation.status = 'running'
        expect(operation.can_abort?).to be true
      end
    end

    describe '#can_cancel?' do
      it 'returns true for pending operations' do
        operation.status = 'pending'
        expect(operation.can_cancel?).to be true
      end

      it 'returns true for scheduled operations' do
        operation.status = 'scheduled'
        expect(operation.can_cancel?).to be true
      end

      it 'returns false for running operations' do
        operation.status = 'running'
        expect(operation.can_cancel?).to be false
      end
    end
  end

  describe 'state transitions' do
    let(:operation) { create(:system_operation, account: account, status: 'pending') }

    describe '#start!' do
      it 'transitions from pending to running' do
        expect(operation.start!).to be true
        expect(operation.status).to eq('running')
        expect(operation.started_at).to be_present
        expect(operation.progress).to eq(0)
      end

      it 'returns false for non-pending operations' do
        operation.update!(status: 'running')
        expect(operation.start!).to be false
      end

      it 'adds a started event' do
        operation.start!
        expect(operation.events.last['type']).to eq('started')
      end
    end

    describe '#complete!' do
      before { operation.update!(status: 'running', started_at: 1.minute.ago) }

      it 'transitions from running to complete' do
        expect(operation.complete!).to be true
        expect(operation.status).to eq('complete')
        expect(operation.completed_at).to be_present
        expect(operation.progress).to eq(100)
      end

      it 'returns false for non-running operations' do
        operation.update!(status: 'pending')
        expect(operation.complete!).to be false
      end
    end

    describe '#fail!' do
      before { operation.update!(status: 'running', started_at: 1.minute.ago) }

      it 'transitions from running to failed' do
        expect(operation.fail!('Something went wrong')).to be true
        expect(operation.status).to eq('failed')
        expect(operation.error_message).to eq('Something went wrong')
        expect(operation.completed_at).to be_present
      end

      it 'adds a failed event' do
        operation.fail!('Error message')
        expect(operation.events.last['type']).to eq('failed')
        expect(operation.events.last['message']).to eq('Error message')
      end
    end

    describe '#abort!' do
      before { operation.update!(status: 'running', started_at: 1.minute.ago) }

      it 'transitions from running to aborted' do
        expect(operation.abort!('User aborted')).to be true
        expect(operation.status).to eq('aborted')
        expect(operation.error_message).to eq('User aborted')
      end
    end

    describe '#cancel!' do
      it 'transitions from pending to cancelled' do
        expect(operation.cancel!('No longer needed')).to be true
        expect(operation.status).to eq('cancelled')
        expect(operation.error_message).to eq('No longer needed')
      end

      it 'returns false for running operations' do
        operation.update!(status: 'running')
        expect(operation.cancel!).to be false
      end
    end

    describe '#update_progress!' do
      before { operation.update!(status: 'running', started_at: 1.minute.ago) }

      it 'updates progress for running operations' do
        expect(operation.update_progress!(50, 'Halfway done')).to be true
        expect(operation.progress).to eq(50)
      end

      it 'clamps progress to valid range' do
        operation.update_progress!(150)
        expect(operation.progress).to eq(100)

        operation.update_progress!(-10)
        expect(operation.progress).to eq(0)
      end

      it 'returns false for non-running operations' do
        operation.update!(status: 'pending')
        expect(operation.update_progress!(50)).to be false
      end
    end
  end

  describe 'event management' do
    let(:operation) { create(:system_operation, account: account) }

    describe '#add_event' do
      it 'adds an event to the events array' do
        operation.add_event('info', 'Something happened', { key: 'value' })

        expect(operation.events.length).to eq(1)
        expect(operation.events.first['type']).to eq('info')
        expect(operation.events.first['message']).to eq('Something happened')
        expect(operation.events.first['data']).to eq({ 'key' => 'value' })
        expect(operation.events.first['timestamp']).to be_present
      end

      it 'appends to existing events' do
        operation.add_event('event1', 'First')
        operation.add_event('event2', 'Second')

        expect(operation.events.length).to eq(2)
      end
    end

    describe '#last_event' do
      it 'returns the last event' do
        operation.add_event('event1', 'First')
        operation.add_event('event2', 'Second')

        expect(operation.last_event['type']).to eq('event2')
      end

      it 'returns nil when no events' do
        expect(operation.last_event).to be_nil
      end
    end
  end

  describe 'duration methods' do
    let(:operation) { create(:system_operation, account: account) }

    describe '#duration' do
      it 'returns nil when not started' do
        expect(operation.duration).to be_nil
      end

      it 'returns duration in seconds for completed operations' do
        operation.update!(started_at: 5.minutes.ago, completed_at: 1.minute.ago)
        expect(operation.duration).to be_within(1).of(240)
      end

      it 'returns duration to current time for running operations' do
        operation.update!(status: 'running', started_at: 1.minute.ago)
        expect(operation.duration).to be_within(1).of(60)
      end
    end

    describe '#duration_formatted' do
      it 'returns nil when not started' do
        expect(operation.duration_formatted).to be_nil
      end

      it 'formats duration with hours, minutes, seconds' do
        # Set explicit times for predictable duration
        start_time = Time.current - 2.hours - 30.minutes - 45.seconds
        end_time = Time.current
        operation.update!(started_at: start_time, completed_at: end_time)
        # Duration should be approximately 2h 30m 45s
        expect(operation.duration_formatted).to match(/\d+h \d+m \d+s/)
      end

      it 'formats short durations without hours' do
        operation.update!(started_at: 45.seconds.ago, completed_at: Time.current)
        expect(operation.duration_formatted).to match(/^\d+s$/)
      end
    end
  end

  describe '#active? and #finished?' do
    let(:operation) { build(:system_operation, account: account) }

    it 'active? returns true for pending, scheduled, running' do
      %w[pending scheduled running].each do |status|
        operation.status = status
        expect(operation.active?).to be true
      end
    end

    it 'active? returns false for finished statuses' do
      %w[complete failed aborted cancelled].each do |status|
        operation.status = status
        expect(operation.active?).to be false
      end
    end

    it 'finished? returns true for complete, failed, aborted, cancelled' do
      %w[complete failed aborted cancelled].each do |status|
        operation.status = status
        expect(operation.finished?).to be true
      end
    end
  end

  describe 'polymorphic operable' do
    it 'can be associated with a Node' do
      operation = create(:system_operation, account: account, operable: node)
      expect(operation.operable).to eq(node)
      expect(operation.operable_type).to eq('System::Node')
    end

    it 'can be associated with a NodeInstance' do
      instance = create(:system_node_instance, node: node)
      operation = create(:system_operation, account: account, operable: instance)
      expect(operation.operable).to eq(instance)
      expect(operation.operable_type).to eq('System::NodeInstance')
    end
  end
end
