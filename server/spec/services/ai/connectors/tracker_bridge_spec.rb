# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Connectors::TrackerBridge do
  # Snapshot/restore the registry so we can inject a stub adapter without
  # disturbing the boot-registered adapters.
  around do |example|
    saved = Ai::Connectors::TrackerRegistry.adapters.dup
    example.run
    Ai::Connectors::TrackerRegistry.reset!
    saved.each { |name, adapter| Ai::Connectors::TrackerRegistry.register(name, adapter) }
  end

  let(:adapter) { instance_double(Ai::Connectors::GenericWebhookTrackerAdapter) }

  context "when a tracker is configured" do
    before do
      # Stub so the verifying double reports respond_to?(:create_issue) at register time.
      allow(adapter).to receive(:create_issue)
      Ai::Connectors::TrackerRegistry.register(:generic_webhook, adapter)
      allow(Ai::Connectors::TrackerConfig).to receive(:enabled?).and_return(true)
      allow(Ai::Connectors::TrackerConfig).to receive(:adapter_name).and_return(:generic_webhook)
    end

    it "forwards to the configured adapter and returns its result" do
      expect(adapter).to receive(:create_issue)
        .with(hash_including(title: "Disk full", severity: "critical", metadata: hash_including(kind: "issue")))
        .and_return({ ok: true, external_id: "ISS-9", url: "https://t/ISS-9" })

      result = described_class.forward(kind: "issue", title: "Disk full", body: "d", severity: "critical")

      expect(result[:external_id]).to eq("ISS-9")
    end

    it "swallows adapter failures and returns nil (internal path never breaks)" do
      allow(adapter).to receive(:create_issue).and_raise(StandardError, "boom")

      result = nil
      expect { result = described_class.forward(kind: "issue", title: "t", body: "b") }.not_to raise_error
      expect(result).to be_nil
    end

    it "returns nil when the configured adapter is missing from the registry" do
      Ai::Connectors::TrackerRegistry.unregister(:generic_webhook)

      expect(described_class.forward(kind: "issue", title: "t", body: "b")).to be_nil
    end
  end

  context "end-to-end with a real native adapter (Linear) selected" do
    before do
      Ai::Connectors::TrackerRegistry.register(:linear, Ai::Connectors::LinearAdapter.new)
      allow(Ai::Connectors::TrackerConfig).to receive(:enabled?).and_return(true)
      allow(Ai::Connectors::TrackerConfig).to receive(:adapter_name).and_return(:linear)
      allow(Ai::Connectors::TrackerConfig).to receive(:linear_api_key).and_return("lin_xxx")
      allow(Ai::Connectors::TrackerConfig).to receive(:linear_team_id).and_return("team-1")
    end

    it "forwards through the real adapter to the Linear GraphQL API and returns the parsed result" do
      stub_request(:post, "https://api.linear.app/graphql").to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          data: { issueCreate: { success: true, issue: { id: "iss-9", url: "https://linear.app/i/iss-9" } } }
        }.to_json
      )

      result = described_class.forward(kind: "issue", title: "Disk full", body: "d", severity: "critical")

      expect(result[:ok]).to be(true)
      expect(result[:external_id]).to eq("iss-9")
    end
  end

  context "when no tracker is configured (default)" do
    before do
      allow(adapter).to receive(:create_issue)
      allow(Ai::Connectors::TrackerConfig).to receive(:enabled?).and_return(false)
    end

    it "does not forward and returns nil" do
      Ai::Connectors::TrackerRegistry.register(:generic_webhook, adapter)
      expect(adapter).not_to receive(:create_issue)

      expect(described_class.forward(kind: "issue", title: "t", body: "b")).to be_nil
    end
  end
end
