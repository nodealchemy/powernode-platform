# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the manual "run now" path.
#
# The job is enqueued by the server's ScheduledTaskService#execute_task with
# [task.id, execution.id] when an operator triggers an ad-hoc run. Such a task's
# next_run_at is normally in the future (or nil), so it is NOT in the due-window
# list. The job must therefore resolve the task by its explicit id rather than
# only from the due scan — otherwise every manual run silently fails on the
# worker with "Task not found". All backend calls go through the mocked API
# client; nothing real runs.
RSpec.describe Maintenance::ScheduledTaskExecutorJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  let(:task_id) { 'task-abc123' }
  let(:execution_id) { 'exec-xyz789' }
  let(:scheduled_tasks_path) { '/api/v1/internal/maintenance/scheduled_tasks' }
  let(:task_fixture) do
    { 'id' => task_id, 'name' => 'Nightly Health Check', 'task_type' => 'system_health_check' }
  end

  before do
    mock_powernode_worker_config
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow(api_client).to receive(:patch).and_return('data' => {})
  end

  describe '#execute with an explicit task_id (manual run of a non-due task)' do
    before do
      # The task is NOT in the due list — an ad-hoc run targets a task whose
      # next_run_at is in the future or nil.
      allow(api_client).to receive(:get)
        .with(scheduled_tasks_path, hash_including(:due_before))
        .and_return('data' => { 'tasks' => [] })
      # ...but it is resolvable by its explicit id.
      allow(api_client).to receive(:get)
        .with(scheduled_tasks_path, { task_id: task_id })
        .and_return('data' => { 'tasks' => [task_fixture] })
      allow(api_client).to receive(:get)
        .with('/api/v1/admin/maintenance/health')
        .and_return('data' => { 'overall_status' => 'healthy' })
    end

    it 'resolves the task by id and executes it instead of failing "Task not found"' do
      expect { job.execute(task_id, execution_id) }.not_to raise_error

      expect(api_client).to have_received(:get).with(scheduled_tasks_path, { task_id: task_id })
      expect(api_client).to have_received(:patch).with(
        "/api/v1/internal/maintenance/task_executions/#{execution_id}",
        hash_including(status: 'completed')
      )
      expect(api_client).not_to have_received(:patch).with(
        anything,
        hash_including(error_message: a_string_matching(/Task not found/))
      )
    end
  end

  describe '#fetch_due_tasks with no explicit id (scheduler due-window sweep)' do
    it 'requests only tasks due within the next minute' do
      freeze_time_at(Time.utc(2026, 7, 1, 12, 0, 0))
      expected_due_before = 1.minute.from_now.iso8601

      expect(api_client).to receive(:get)
        .with(scheduled_tasks_path, { due_before: expected_due_before })
        .and_return('data' => { 'tasks' => [] })

      expect(job.send(:fetch_due_tasks)).to eq({ 'tasks' => [] })
    end
  end
end
