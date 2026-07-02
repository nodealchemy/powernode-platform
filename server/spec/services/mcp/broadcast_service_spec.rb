# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::BroadcastService do
  subject(:service) { described_class.instance }

  let(:message) do
    {
      type: "tool_event",
      event_type: "registered",
      account_id: "acct-1",
      timestamp: Time.current.iso8601
    }
  end

  describe "#send_to_webhook" do
    let(:webhook_url) { "https://hooks.example.com/mcp" }

    before do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:monitoring, :webhook_url).and_return(webhook_url)
    end

    it "dispatches delivery to the standalone worker via WorkerJobService (server runs no Sidekiq)" do
      expect(WorkerJobService).to receive(:enqueue_mcp_monitoring_webhook)
        .with(webhook_url, message.to_json)

      service.send(:send_to_webhook, message)
    end

    it "does not reference an in-process (undefined) webhook job constant" do
      allow(WorkerJobService).to receive(:enqueue_mcp_monitoring_webhook)

      expect { service.send(:send_to_webhook, message) }.not_to raise_error
    end

    context "when no monitoring webhook is configured" do
      before do
        allow(Rails.application.credentials).to receive(:dig)
          .with(:monitoring, :webhook_url).and_return(nil)
      end

      it "enqueues nothing" do
        expect(WorkerJobService).not_to receive(:enqueue_mcp_monitoring_webhook)

        service.send(:send_to_webhook, message)
      end
    end
  end
end
