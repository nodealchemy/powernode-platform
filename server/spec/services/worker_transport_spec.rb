# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkerTransport do
  let(:base_url) { "http://worker.example.test:4567" }
  subject(:transport) { described_class.new(base_url: base_url) }

  before do
    allow(WorkerJobService).to receive(:system_worker_jwt).and_return("test-jwt")
  end

  describe "base-URL resolution" do
    it "defaults to Rails.application.config.worker_url" do
      expect(described_class.new.base_url).to eq(Rails.application.config.worker_url.chomp("/"))
    end

    it "honours an explicit base_url override and strips a trailing slash" do
      expect(described_class.new(base_url: "http://x.example.test/").base_url).to eq("http://x.example.test")
    end
  end

  describe "#post" do
    it "sends JSON with the system-worker JWT bearer and returns the parsed body" do
      stub_request(:post, "#{base_url}/api/v1/echo")
        .to_return(status: 200, body: { "ok" => true }.to_json)

      expect(transport.post("/api/v1/echo", { a: 1 })).to eq({ "ok" => true })
      expect(WebMock).to have_requested(:post, "#{base_url}/api/v1/echo")
        .with(body: { a: 1 }.to_json,
              headers: { "Authorization" => "Bearer test-jwt",
                         "Content-Type" => "application/json",
                         "Accept" => "application/json" })
    end

    it "raises HttpError with status, raw body, and best-effort parsed body on non-2xx" do
      stub_request(:post, "#{base_url}/api/v1/echo")
        .to_return(status: 503, body: { "error" => "down" }.to_json)

      expect { transport.post("/api/v1/echo") }.to raise_error(described_class::HttpError) do |e|
        expect(e.status).to eq(503)
        expect(e.parsed).to eq({ "error" => "down" })
        expect(e.body).to include("down")
      end
    end

    it "raises HttpError with parsed=nil for a non-JSON error body" do
      stub_request(:post, "#{base_url}/api/v1/echo").to_return(status: 500, body: "<html>boom</html>")

      expect { transport.post("/api/v1/echo") }.to raise_error(described_class::HttpError) do |e|
        expect(e.parsed).to be_nil
        expect(e.body).to eq("<html>boom</html>")
      end
    end

    it "lets JSON::ParserError propagate for an invalid 2xx body" do
      stub_request(:post, "#{base_url}/api/v1/echo").to_return(status: 200, body: "not json")

      expect { transport.post("/api/v1/echo") }.to raise_error(JSON::ParserError)
    end

    it "raises TimeoutError on timeout" do
      stub_request(:post, "#{base_url}/api/v1/echo").to_timeout

      expect { transport.post("/api/v1/echo") }.to raise_error(described_class::TimeoutError)
    end

    it "raises ConnectionError when the worker is unreachable" do
      stub_request(:post, "#{base_url}/api/v1/echo").to_raise(Errno::ECONNREFUSED)

      expect { transport.post("/api/v1/echo") }.to raise_error(described_class::ConnectionError)
    end
  end

  describe "#get" do
    it "issues a GET with the JWT bearer and returns the parsed body" do
      stub_request(:get, "#{base_url}/health").to_return(status: 200, body: { "status" => "ok" }.to_json)

      expect(transport.get("/health")).to eq({ "status" => "ok" })
      expect(WebMock).to have_requested(:get, "#{base_url}/health")
        .with(headers: { "Authorization" => "Bearer test-jwt" })
    end
  end
end
