# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Connectors::SentryAdapter do
  subject(:adapter) { described_class.new }

  let(:public_key) { "abc123def" }
  let(:project_id) { "4509" }
  let(:dsn) { "https://#{public_key}@o123.ingest.sentry.io/#{project_id}" }
  let(:store_url) { "https://o123.ingest.sentry.io/api/#{project_id}/store/" }

  before do
    allow(Ai::Connectors::TrackerConfig).to receive(:sentry_dsn).and_return(dsn)
  end

  it "captures an event to the Sentry store endpoint derived from the DSN" do
    stub = stub_request(:post, store_url)
      .with(headers: { "Content-Type" => "application/json" }) do |req|
        auth = req.headers["X-Sentry-Auth"].to_s
        body = JSON.parse(req.body)
        message = body["message"].is_a?(Hash) ? body["message"]["formatted"] : body["message"]
        auth.include?("sentry_key=#{public_key}") &&
          auth.include?("sentry_version=7") &&
          body["level"] == "error" &&
          body["event_id"].is_a?(String) && body["event_id"].length == 32 &&
          message.to_s.include?("Boom")
      end
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { id: "evt-1" }.to_json
      )

    result = adapter.report_error(error: "Boom", severity: "error", context: { trace: "..." })

    expect(result[:ok]).to be(true)
    expect(result[:external_id]).to eq("evt-1")
    expect(stub).to have_been_requested
  end

  it "create_issue delegates to an event capture" do
    stub = stub_request(:post, store_url).to_return(status: 200, body: { id: "evt-2" }.to_json)

    result = adapter.create_issue(title: "Disk full", body: "details", severity: "critical")

    expect(result[:ok]).to be(true)
    expect(result[:external_id]).to eq("evt-2")
    expect(stub).to have_been_requested
  end

  it "returns ok:false on a non-2xx response without leaking the DSN" do
    stub_request(:post, store_url).to_return(status: 429, body: "rate limited")

    result = adapter.report_error(error: "Boom")

    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(dsn)
  end

  it "returns ok:false (no raise) when the DSN is missing, without leaking it" do
    allow(Ai::Connectors::TrackerConfig).to receive(:sentry_dsn).and_return(nil)

    result = nil
    expect { result = adapter.report_error(error: "Boom") }.not_to raise_error
    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(dsn)
  end

  it "returns ok:false on a transport error without leaking the DSN" do
    stub_request(:post, store_url).to_raise(Faraday::ConnectionFailed.new("refused"))

    result = adapter.report_error(error: "Boom")

    expect(result[:ok]).to be(false)
    expect(result[:error].to_s).not_to include(dsn)
  end
end
