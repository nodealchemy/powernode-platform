# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Introspection::ExecutionEventRecorder, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  # ===========================================================================
  # .record
  # ===========================================================================

  describe ".record" do
    it "creates an execution event" do
      expect {
        described_class.record(
          source: agent,
          event_type: "execution_started",
          status: "success"
        )
      }.to change(Ai::ExecutionEvent, :count).by(1)
    end

    it "saves all attributes correctly" do
      described_class.record(
        source: agent,
        event_type: "execution_completed",
        status: "success",
        metadata: { "model" => "gpt-4" },
        cost_usd: 0.05,
        duration_ms: 1500
      )

      event = Ai::ExecutionEvent.last
      expect(event.account_id).to eq(account.id)
      expect(event.source_type).to eq("Ai::Agent")
      expect(event.source_id).to eq(agent.id)
      expect(event.event_type).to eq("execution_completed")
      expect(event.status).to eq("success")
      expect(event.metadata).to eq({ "model" => "gpt-4" })
      expect(event.cost_usd).to eq(0.05)
      expect(event.duration_ms).to eq(1500)
    end

    it "records error information from an Exception" do
      error = RuntimeError.new("Something went wrong")

      described_class.record(
        source: agent,
        event_type: "execution_failed",
        status: "failure",
        error: error
      )

      event = Ai::ExecutionEvent.last
      expect(event.error_class).to eq("RuntimeError")
      expect(event.error_message).to eq("Something went wrong")
    end

    it "records error information from a string" do
      described_class.record(
        source: agent,
        event_type: "execution_failed",
        status: "failure",
        error: "ProviderTimeoutError"
      )

      event = Ai::ExecutionEvent.last
      expect(event.error_class).to eq("ProviderTimeoutError")
      expect(event.error_message).to be_nil
    end

    it "resolves account_id from source.account_id" do
      described_class.record(
        source: agent,
        event_type: "test",
        status: "success"
      )

      event = Ai::ExecutionEvent.last
      expect(event.account_id).to eq(agent.account_id)
    end

    it "does not raise on record failure" do
      allow(Ai::ExecutionEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Ai::ExecutionEvent.new))

      expect {
        described_class.record(
          source: agent,
          event_type: "test",
          status: "success"
        )
      }.not_to raise_error
    end

    it "returns nil when source has no account" do
      sourceless = double("sourceless", class: Class, id: SecureRandom.uuid)
      allow(sourceless).to receive(:respond_to?).and_return(false)

      result = described_class.record(
        source: sourceless,
        event_type: "test",
        status: "success"
      )

      expect(result).to be_nil
    end
  end

  # ===========================================================================
  # .record_async
  # ===========================================================================

  describe ".record_async" do
    it "creates an event in a background thread" do
      thread = described_class.record_async(
        source: agent,
        event_type: "execution_started",
        status: "success",
        metadata: { "async" => true }
      )

      # Wait for the thread to complete
      thread.join if thread.is_a?(Thread)

      event = Ai::ExecutionEvent.last
      expect(event).to be_present
      expect(event.event_type).to eq("execution_started")
      expect(event.metadata).to include("async" => true)
    end

    it "returns nil when source has no account" do
      sourceless = double("sourceless", class: Class, id: SecureRandom.uuid)
      allow(sourceless).to receive(:respond_to?).and_return(false)

      result = described_class.record_async(
        source: sourceless,
        event_type: "test",
        status: "success"
      )

      expect(result).to be_nil
    end
  end
end
