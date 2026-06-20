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
end
