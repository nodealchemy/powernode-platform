# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScheduledTask, type: :model do
  describe 'associations' do
    it { should have_many(:task_executions).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:scheduled_task) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_presence_of(:task_type) }
    it { should validate_inclusion_of(:task_type).in_array(%w[database_backup data_cleanup system_health_check report_generation custom_command]) }
    it { should validate_presence_of(:cron_expression) }
    it { should validate_inclusion_of(:is_active).in_array([ true, false ]) }

    it 'validates uniqueness of name' do
      create(:scheduled_task, name: 'Daily Backup')
      task = build(:scheduled_task, name: 'Daily Backup')
      expect(task).not_to be_valid
      expect(task.errors[:name]).to include('has already been taken')
    end
  end

  describe 'scopes' do
    let!(:active_task) { create(:scheduled_task, :active) }
    let!(:inactive_task) { create(:scheduled_task, :inactive) }
    let!(:backup_task) { create(:scheduled_task, :database_backup) }
    let!(:cleanup_task) { create(:scheduled_task, :data_cleanup) }

    describe '.enabled' do
      it 'returns only active tasks' do
        expect(ScheduledTask.enabled).to include(active_task)
        expect(ScheduledTask.enabled).not_to include(inactive_task)
      end
    end

    describe '.disabled' do
      it 'returns only inactive tasks' do
        expect(ScheduledTask.disabled).to include(inactive_task)
        expect(ScheduledTask.disabled).not_to include(active_task)
      end
    end

    describe '.by_type' do
      it 'returns tasks of specified type' do
        expect(ScheduledTask.by_type('database_backup')).to include(backup_task)
        expect(ScheduledTask.by_type('database_backup')).not_to include(cleanup_task)
      end
    end

    describe '.recent' do
      it 'orders by created_at descending' do
        tasks = ScheduledTask.recent
        expect(tasks.first.created_at).to be >= tasks.last.created_at
      end
    end
  end

  describe 'instance methods' do
    let(:task) { create(:scheduled_task) }

    describe '#enabled?' do
      it 'returns true when is_active is true' do
        task.is_active = true
        expect(task.enabled?).to be true
      end

      it 'returns false when is_active is false' do
        task.is_active = false
        expect(task.enabled?).to be false
      end
    end

    describe '#disabled?' do
      it 'returns true when is_active is false' do
        task.is_active = false
        expect(task.disabled?).to be true
      end

      it 'returns false when is_active is true' do
        task.is_active = true
        expect(task.disabled?).to be false
      end
    end

    describe '#last_execution' do
      it 'returns nil when no executions exist' do
        expect(task.last_execution).to be_nil
      end

      it 'returns the most recent execution' do
        old_exec = create(:task_execution, scheduled_task: task, created_at: 2.hours.ago)
        new_exec = create(:task_execution, scheduled_task: task, created_at: 1.hour.ago)
        expect(task.last_execution).to eq(new_exec)
      end
    end

    describe '#last_successful_execution' do
      it 'returns nil when no completed executions exist' do
        create(:task_execution, :failed, scheduled_task: task)
        expect(task.last_successful_execution).to be_nil
      end

      it 'returns the most recent completed execution' do
        create(:task_execution, :completed, scheduled_task: task, created_at: 2.hours.ago)
        recent = create(:task_execution, :completed, scheduled_task: task, created_at: 1.hour.ago)
        create(:task_execution, :failed, scheduled_task: task)
        expect(task.last_successful_execution).to eq(recent)
      end
    end

    describe '#success_rate' do
      it 'returns 0 when no executions exist' do
        expect(task.success_rate).to eq(0)
      end

      it 'calculates correct success rate' do
        3.times { create(:task_execution, :completed, scheduled_task: task) }
        1.times { create(:task_execution, :failed, scheduled_task: task) }
        expect(task.success_rate).to eq(75.0)
      end
    end

    describe '#next_run_time' do
      it 'returns a future time' do
        expect(task.next_run_time).to be > Time.current
      end
    end

    describe '#can_execute?' do
      it 'returns true when enabled and not running' do
        task.is_active = true
        expect(task.can_execute?).to be true
      end

      it 'returns false when disabled' do
        task.is_active = false
        expect(task.can_execute?).to be false
      end

      it 'returns false when already running' do
        task.is_active = true
        create(:task_execution, :running, scheduled_task: task)
        expect(task.can_execute?).to be false
      end
    end

    describe '#currently_running?' do
      it 'returns true when running execution exists' do
        create(:task_execution, :running, scheduled_task: task)
        expect(task.currently_running?).to be true
      end

      it 'returns false when no running execution exists' do
        create(:task_execution, :completed, scheduled_task: task)
        expect(task.currently_running?).to be false
      end
    end
  end

  describe 'callbacks' do
    it 'logs task creation' do
      expect(Rails.logger).to receive(:info).with(/Scheduled task created/)
      create(:scheduled_task)
    end

    it 'logs task update' do
      task = create(:scheduled_task)
      expect(Rails.logger).to receive(:info).with(/Scheduled task updated/)
      task.update!(name: 'Updated Task Name')
    end

    it 'logs task deletion' do
      task = create(:scheduled_task)
      expect(Rails.logger).to receive(:info).with(/Scheduled task deleted/)
      task.destroy
    end
  end
end
