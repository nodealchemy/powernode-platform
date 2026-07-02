# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledTaskService do
  describe ".execute_task" do
    let(:user) { create(:user) }
    let(:task) { create(:scheduled_task) }

    before do
      allow(WorkerJobService).to receive(:enqueue_job).and_return("job_id" => "job-123")
    end

    it "dispatches the execution to the standalone worker via the HTTP seam (the API server runs no Sidekiq)" do
      result = described_class.execute_task(task.id, user)

      expect(result[:success]).to be(true)
      execution = TaskExecution.find(result[:execution][:id])
      expect(execution.scheduled_task).to eq(task)
      expect(WorkerJobService).to have_received(:enqueue_job).with(
        "Maintenance::ScheduledTaskExecutorJob",
        hash_including(args: [ task.id, execution.id ], queue: "maintenance")
      )
    end

    it "returns an error hash (never a raised NameError) when the worker seam is unavailable" do
      allow(WorkerJobService).to receive(:enqueue_job)
        .and_raise(WorkerJobService::WorkerServiceError.new("worker down"))

      result = described_class.execute_task(task.id, user)

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/worker down/)
    end
  end
end
