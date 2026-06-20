# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::BaseExecutor, type: :service do
  # A minimal concrete executor that drives the full template-method lifecycle
  # (execute -> perform_execution -> record_success/record_failure ->
  # IntegrationExecution#complete!/#fail! -> instance.record_execution!) through
  # the real machinery and a live DB record.
  let(:executor_class) do
    Class.new(described_class) do
      def perform_execution(input)
        raise Devops::BaseExecutor::ExecutionError, input[:boom] if input[:boom]

        { status_code: 200, echo: input[:echo] }
      end

      def validate_configuration!
        true
      end

      def validate_credentials!
        true
      end
    end
  end

  let(:instance) { create(:devops_integration_instance) } # active, counters at 0
  let(:execution) do
    create(:devops_integration_execution, :running, instance: instance, account: instance.account)
  end
  let(:executor) { executor_class.new(instance: instance, execution: execution) }

  describe "#execute on success" do
    it "completes the execution into the real columns" do
      result = executor.execute(echo: "hi")

      expect(result).to eq({ status_code: 200, echo: "hi" })

      execution.reload
      expect(execution.status).to eq("completed")
      expect(execution.duration_ms).to be_a(Integer)
      expect(execution.output_data).to include("status_code" => 200, "echo" => "hi")
    end

    it "counts the instance exactly once (no double-count) and records health telemetry" do
      executor.execute(echo: "hi")

      instance.reload
      expect(instance.execution_count).to eq(1) # was 2 when executor + callback both counted
      expect(instance.success_count).to eq(1)
      expect(instance.failure_count).to eq(0)
      expect(instance.average_duration_ms.to_f).to be >= 0 # no Infinity overflow
      expect(instance.health_metrics["last_execution_success"]).to be(true)
      expect(instance.health_metrics).to have_key("last_execution_time_ms")
    end
  end

  describe "#execute on failure" do
    it "fails the execution into error_details and counts a single failure" do
      expect do
        executor.execute(boom: "kaboom")
      end.to raise_error(Devops::BaseExecutor::ExecutionError, "kaboom")

      execution.reload
      expect(execution.status).to eq("failed")
      expect(execution.error_details).to include("message" => "kaboom")

      instance.reload
      expect(instance.execution_count).to eq(1)
      expect(instance.failure_count).to eq(1)
      expect(instance.consecutive_failures).to eq(1)
      expect(instance.health_metrics["last_execution_success"]).to be(false)
    end
  end
end
