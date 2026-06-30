# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Connectors::GenericWebhookTrackerAdapter do
  let(:url) { "https://hooks.example.test/tracker" }
  subject(:adapter) { described_class.new(url: url) }

  describe "#create_issue" do
    it "POSTs the issue payload to the configured URL and returns ok + external id/url" do
      stub = stub_request(:post, url)
        .with(headers: { "Content-Type" => "application/json" }) do |req|
          body = JSON.parse(req.body)
          body["event"] == "issue" &&
            body["title"] == "Disk full" &&
            body["severity"] == "critical" &&
            body["source"] == "powernode" &&
            body["connector"] == "generic_webhook"
        end
        .to_return(
          status: 201,
          body: { id: "ISS-1", url: "https://tracker.example.test/ISS-1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = adapter.create_issue(title: "Disk full", body: "details", severity: "critical", metadata: { host: "n1" })

      expect(result[:ok]).to be(true)
      expect(result[:external_id]).to eq("ISS-1")
      expect(result[:url]).to eq("https://tracker.example.test/ISS-1")
      expect(stub).to have_been_requested
    end

    it "returns ok:false on a non-2xx response (handled gracefully, no raise)" do
      stub_request(:post, url).to_return(status: 500, body: "boom")

      result = adapter.create_issue(title: "x", body: "y")

      expect(result[:ok]).to be(false)
      expect(result[:status]).to eq(500)
    end

    it "returns ok:false on a transport error" do
      stub_request(:post, url).to_raise(Faraday::ConnectionFailed.new("refused"))

      result = adapter.create_issue(title: "x", body: "y")

      expect(result[:ok]).to be(false)
      expect(result[:error]).to be_present
    end

    it "raises when no URL is configured (no explicit url, none in config)" do
      allow(Ai::Connectors::TrackerConfig).to receive(:endpoint).and_return(nil)

      expect { described_class.new.create_issue(title: "x", body: "y") }
        .to raise_error(ArgumentError, /no webhook URL configured/)
    end

    it "falls back to TrackerConfig.endpoint when no explicit url is given" do
      allow(Ai::Connectors::TrackerConfig).to receive(:endpoint).and_return(url)
      stub = stub_request(:post, url).to_return(status: 200, body: {}.to_json)

      result = described_class.new.create_issue(title: "x", body: "y")

      expect(result[:ok]).to be(true)
      expect(stub).to have_been_requested
    end
  end

  describe "#report_error" do
    it "POSTs an error payload and returns ok" do
      stub = stub_request(:post, url)
        .with { |req| JSON.parse(req.body)["event"] == "error" }
        .to_return(status: 200, body: {}.to_json)

      result = adapter.report_error(error: "NullPointer", severity: "error", context: { trace: "..." })

      expect(result[:ok]).to be(true)
      expect(stub).to have_been_requested
    end
  end
end
