# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaskExecution, type: :model do
  describe 'associations' do
    it { should belong_to(:scheduled_task) }
  end

  describe 'validations' do
    subject { build(:task_execution) }

    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[running completed failed timeout]) }
  end

  describe 'scopes' do
    let(:scheduled_task) { create(:scheduled_task) }
    let!(:running_exec) { create(:task_execution, :running, scheduled_task: scheduled_task) }
    let!(:completed_exec) { create(:task_execution, :completed, scheduled_task: scheduled_task) }
    let!(:failed_exec) { create(:task_execution, :failed, scheduled_task: scheduled_task) }

    describe '.completed' do
      it 'returns only completed executions' do
        expect(TaskExecution.completed).to include(completed_exec)
        expect(TaskExecution.completed).not_to include(running_exec, failed_exec)
      end
    end

    describe '.failed' do
      it 'returns only failed executions' do
        expect(TaskExecution.failed).to include(failed_exec)
        expect(TaskExecution.failed).not_to include(running_exec, completed_exec)
      end
    end

    describe '.running' do
      it 'returns only running executions' do
        expect(TaskExecution.running).to include(running_exec)
        expect(TaskExecution.running).not_to include(completed_exec, failed_exec)
      end
    end

    describe '.recent' do
      it 'orders by created_at descending' do
        executions = TaskExecution.recent
        expect(executions.first.created_at).to be >= executions.last.created_at
      end
    end
  end

  describe 'instance methods' do
    let(:scheduled_task) { create(:scheduled_task) }
    let(:execution) { create(:task_execution, scheduled_task: scheduled_task) }

    describe '#completed?' do
      it 'returns true when status is completed' do
        execution.status = 'completed'
        expect(execution.completed?).to be true
      end

      it 'returns false otherwise' do
        execution.status = 'running'
        expect(execution.completed?).to be false
      end
    end

    describe '#failed?' do
      it 'returns true when status is failed' do
        execution.status = 'failed'
        expect(execution.failed?).to be true
      end

      it 'returns false otherwise' do
        execution.status = 'running'
        expect(execution.failed?).to be false
      end
    end

    describe '#running?' do
      it 'returns true when status is running' do
        execution.status = 'running'
        expect(execution.running?).to be true
      end

      it 'returns false otherwise' do
        execution.status = 'completed'
        expect(execution.running?).to be false
      end
    end

    describe '#timeout?' do
      it 'returns true when status is timeout' do
        execution.status = 'timeout'
        expect(execution.timeout?).to be true
      end

      it 'returns false otherwise' do
        execution.status = 'running'
        expect(execution.timeout?).to be false
      end
    end

    describe '#success?' do
      it 'returns true when completed' do
        execution.status = 'completed'
        expect(execution.success?).to be true
      end

      it 'returns false when not completed' do
        execution.status = 'failed'
        expect(execution.success?).to be false
      end
    end

    describe '#duration' do
      it 'returns nil if started_at is missing' do
        execution.started_at = nil
        expect(execution.duration).to be_nil
      end

      it 'returns nil if completed_at is missing' do
        execution.started_at = Time.current
        execution.completed_at = nil
        expect(execution.duration).to be_nil
      end

      it 'calculates duration when both timestamps present' do
        execution.started_at = 10.minutes.ago
        execution.completed_at = 5.minutes.ago
        expect(execution.duration).to be_within(1).of(300) # 5 minutes
      end
    end

    describe '#duration_human' do
      it 'returns "N/A" when duration is nil' do
        execution.started_at = nil
        expect(execution.duration_human).to eq('N/A')
      end

      it 'formats seconds' do
        execution.started_at = 30.seconds.ago
        execution.completed_at = Time.current
        expect(execution.duration_human).to match(/\d+s/)
      end

      it 'formats minutes and seconds' do
        execution.started_at = (2.minutes + 30.seconds).ago
        execution.completed_at = Time.current
        result = execution.duration_human
        expect(result).to match(/\d+m \d+s/)
      end

      it 'formats hours and minutes' do
        execution.started_at = 2.hours.ago
        execution.completed_at = Time.current
        expect(execution.duration_human).to match(/\d+h \d+m/)
      end
    end
  end

  describe 'callbacks' do
    let(:scheduled_task) do
      # Allow any log messages during scheduled_task creation
      allow(Rails.logger).to receive(:info)
      create(:scheduled_task)
    end

    it 'logs execution creation' do
      scheduled_task # trigger creation with logging allowed
      expect(Rails.logger).to receive(:info).with(/Task execution created for/)
      create(:task_execution, scheduled_task: scheduled_task)
    end

    it 'logs status changes' do
      scheduled_task # trigger creation with logging allowed
      allow(Rails.logger).to receive(:info) # allow creation log
      execution = create(:task_execution, :running, scheduled_task: scheduled_task)
      expect(Rails.logger).to receive(:info).with(/Task execution status changed for/)
      execution.update!(status: 'completed')
    end
  end
end
