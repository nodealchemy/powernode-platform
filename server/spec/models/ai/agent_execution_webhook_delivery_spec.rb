# frozen_string_literal: true

require "rails_helper"

# Regression for IMP-cee9c190806e: the API server runs no Sidekiq and
# AiWebhookDeliveryJob is defined only in the worker, so both reachable webhook
# paths (#retry_webhook! and the trigger_webhook after_update callback) must
# route through the WorkerJobService HTTP seam rather than referencing the worker
# Sidekiq job constant directly (which NameErrors on the server autoload path).
module Ai
  RSpec.describe AgentExecution, type: :model do
    let(:execution) do
      create(:ai_agent_execution, :running, webhook_url: "https://hooks.example.com/agent")
    end

    describe "#retry_webhook!" do
      it "routes delivery through the WorkerJobService HTTP seam (server is Sidekiq-free)" do
        expect(WorkerJobService).to receive(:enqueue_ai_webhook_delivery).with(execution.id)

        expect(execution.retry_webhook!).to be(true)
      end
    end

    describe "trigger_webhook (after_update)" do
      it "enqueues delivery via the seam when a webhook-configured execution finishes" do
        expect(WorkerJobService).to receive(:enqueue_ai_webhook_delivery).with(execution.id)

        execution.complete_execution!({ "output" => "done" })
      end

      it "does not roll back the status transition when the worker enqueue fails" do
        allow(WorkerJobService).to receive(:enqueue_ai_webhook_delivery)
          .and_raise(WorkerJobService::WorkerServiceError, "worker down")

        expect { execution.complete_execution!({ "output" => "done" }) }.not_to raise_error
        expect(execution.reload.status).to eq("completed")
      end
    end
  end
end
