# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::ExecutionService, type: :service do
  describe ".run_queued" do
    let(:execution) { create(:devops_integration_execution, status: "queued") }
    let(:executor) { instance_double(Devops::BaseExecutor) }

    before do
      allow(described_class).to receive(:build_executor).and_return(executor)
    end

    it "transitions the queued execution to running, runs the executor, and returns its result" do
      # The executor itself drives running -> completed/failed (BaseExecutor specs
      # cover that); run_queued's job is to mark it running and invoke the executor.
      allow(executor).to receive(:execute).and_return({ status: "ok" })

      result = described_class.run_queued(execution: execution)

      expect(result).to include(success: true, execution_id: execution.id)
      expect(result[:result]).to eq({ status: "ok" })
      expect(execution.reload.status).to eq("running") # start! transitioned queued -> running
      expect(execution.started_at).to be_present
    end

    it "passes the execution's stored input_data to the executor (not re-fetched)" do
      execution.update!(status: "queued", input_data: { "method" => "POST", "path" => "/x" })
      received = nil
      allow(executor).to receive(:execute) { |input| received = input; { status: "ok" } }

      described_class.run_queued(execution: execution)
      expect(received).to eq({ "method" => "POST", "path" => "/x" })
    end

    it "returns a failure hash (does not raise) when the executor raises ExecutionError" do
      allow(executor).to receive(:execute).and_raise(Devops::BaseExecutor::ExecutionError, "boom")

      result = described_class.run_queued(execution: execution)

      expect(result).to include(success: false, execution_id: execution.id, error: "boom")
    end

    it "raises InvalidInstanceError when the execution has no integration instance" do
      allow(execution).to receive(:instance).and_return(nil)

      expect do
        described_class.run_queued(execution: execution)
      end.to raise_error(Devops::ExecutionService::InvalidInstanceError)
    end
  end

  describe ".execute_async" do
    let(:instance) { create(:devops_integration_instance) } # status "active"

    before do
      allow(WorkerJobService).to receive(:enqueue_job).and_return(true)
    end

    # Regression: create_execution_record wrote `devops_integration_instance_id`,
    # which is not a column (the real FK is `integration_instance_id`), so every
    # async dispatch raised UnknownAttributeError before this point.
    it "creates a queued execution wired to the real FK and enqueues the worker job" do
      result = described_class.execute_async(instance: instance, input: { "k" => "v" })

      expect(result).to include(success: true, status: "queued")

      execution = Devops::IntegrationExecution.find(result[:execution_id])
      expect(execution.status).to eq("queued")
      expect(execution.integration_instance_id).to eq(instance.id)
      expect(execution.instance).to eq(instance)

      expect(WorkerJobService).to have_received(:enqueue_job)
        .with("Devops::IntegrationExecutionJob", hash_including(queue: "integrations"))
    end
  end

  describe ".retry_execution" do
    let(:instance) { create(:devops_integration_instance) }
    let(:user) { create(:user) }
    let(:failed_execution) do
      create(:devops_integration_execution, :failed, instance: instance, account: instance.account,
                                                      triggered_by_user: user, attempt_number: 1, max_attempts: 3)
    end
    let(:executor) { instance_double(Devops::BaseExecutor) }

    before do
      allow(described_class).to receive(:build_executor).and_return(executor)
      allow(executor).to receive(:execute).and_return({ ok: true })
    end

    # Regression: retry_execution read execution.triggered_by / execution.retry_count
    # and wrote retry_count: — none of which are columns (the real ones are
    # triggered_by_user_id / attempt_number), so retrying always raised.
    it "creates a child execution with an incremented attempt_number and the same trigger user" do
      result = described_class.retry_execution(execution: failed_execution)

      expect(result[:success]).to be(true)

      retry_exec = Devops::IntegrationExecution.find(result[:execution_id])
      expect(retry_exec.id).not_to eq(failed_execution.id)
      expect(retry_exec.attempt_number).to eq(2)
      expect(retry_exec.parent_execution_id).to eq(failed_execution.id)
      expect(retry_exec.triggered_by_user_id).to eq(user.id)
      expect(retry_exec.integration_instance_id).to eq(instance.id)
    end
  end
end
