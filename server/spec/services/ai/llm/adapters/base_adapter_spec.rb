# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::Adapters::BaseAdapter do
  let(:adapter) do
    described_class.new(
      api_key: "test-key-123",
      base_url: "https://api.example.com/v1",
      provider_name: "test"
    )
  end

  describe "#initialize" do
    it "sets api_key" do
      expect(adapter.api_key).to eq("test-key-123")
    end

    it "sets base_url" do
      expect(adapter.base_url).to eq("https://api.example.com/v1")
    end

    it "sets provider_name" do
      expect(adapter.provider_name).to eq("test")
    end

    it "strips trailing slashes from base_url" do
      a = described_class.new(api_key: "k", base_url: "https://api.example.com/v1/", provider_name: "t")
      expect(a.base_url).to eq("https://api.example.com/v1")
    end

    it "strips multiple trailing slashes from base_url" do
      a = described_class.new(api_key: "k", base_url: "https://api.example.com/v1///", provider_name: "t")
      # chomp only removes one trailing "/"
      expect(a.base_url).not_to end_with("/")
    end

    it "builds default headers with Content-Type and User-Agent" do
      expect(adapter.headers).to include(
        "Content-Type" => "application/json",
        "User-Agent" => "Powernode-AI/2.0"
      )
    end

    it "merges extra_headers into default headers" do
      a = described_class.new(
        api_key: "k",
        base_url: "https://api.example.com",
        provider_name: "t",
        extra_headers: { "X-Custom" => "value" }
      )
      expect(a.headers["X-Custom"]).to eq("value")
      expect(a.headers["Content-Type"]).to eq("application/json")
    end
  end

  describe "#complete" do
    it "raises NotImplementedError" do
      expect {
        adapter.complete(messages: [], model: "test-model")
      }.to raise_error(NotImplementedError)
    end
  end

  describe "#stream" do
    it "raises NotImplementedError" do
      expect {
        adapter.stream(messages: [], model: "test-model") { |_chunk| }
      }.to raise_error(NotImplementedError)
    end
  end

  describe "#complete_with_tools" do
    it "raises NotImplementedError" do
      expect {
        adapter.complete_with_tools(messages: [], tools: [], model: "test-model")
      }.to raise_error(NotImplementedError)
    end
  end

  describe "#complete_structured" do
    it "raises NotImplementedError" do
      expect {
        adapter.complete_structured(messages: [], schema: {}, model: "test-model")
      }.to raise_error(NotImplementedError)
    end
  end

  describe "protected #http_post" do
    let(:url) { "https://api.example.com/v1/chat" }
    let(:body) { { model: "test", messages: [] } }

    it "makes a POST request via HTTParty and returns status, parsed, headers" do
      mock_response = double(
        code: 200,
        parsed_response: { "result" => "ok" },
        headers: { "content-type" => "application/json" }
      )

      allow(HTTParty).to receive(:post).and_return(mock_response)

      status, parsed, headers = adapter.send(:http_post, "/chat", body)

      expect(status).to eq(200)
      expect(parsed).to eq("result" => "ok")
      expect(headers).to include("content-type" => "application/json")
    end

    it "passes correct URL combining base_url and path" do
      mock_response = double(code: 200, parsed_response: {}, headers: {})

      allow(HTTParty).to receive(:post).and_return(mock_response)
      adapter.send(:http_post, "/chat", body)

      expect(HTTParty).to have_received(:post).with(
        "https://api.example.com/v1/chat",
        hash_including(timeout: 120)
      )
    end

    it "sends body as JSON with correct headers" do
      mock_response = double(code: 200, parsed_response: {}, headers: {})

      allow(HTTParty).to receive(:post).and_return(mock_response)
      adapter.send(:http_post, "/chat", body)

      expect(HTTParty).to have_received(:post).with(
        anything,
        hash_including(
          headers: adapter.headers,
          body: body.to_json
        )
      )
    end
  end

  describe "protected #http_stream" do
    it "raises RequestError on non-success HTTP response" do
      uri = URI.parse("https://api.example.com/v1/chat")
      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPInternalServerError, code: "500", body: "Server Error")

      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:request).and_yield(response)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)

      expect {
        adapter.send(:http_stream, "/chat", {}) { |_r| }
      }.to raise_error(Ai::Llm::Adapters::RequestError, /HTTP 500/)
    end
  end

  describe "protected #parse_sse_stream" do
    it "parses SSE data events and yields parsed JSON" do
      response = double("response")
      sse_data = "data: {\"text\":\"hello\"}\n\ndata: {\"text\":\"world\"}\n\n"

      allow(response).to receive(:read_body).and_yield(sse_data)

      results = []
      adapter.send(:parse_sse_stream, response) { |parsed| results << parsed }

      expect(results).to eq([{ "text" => "hello" }, { "text" => "world" }])
    end

    it "skips [DONE] sentinel" do
      response = double("response")
      sse_data = "data: {\"text\":\"hello\"}\n\ndata: [DONE]\n\n"

      allow(response).to receive(:read_body).and_yield(sse_data)

      results = []
      adapter.send(:parse_sse_stream, response) { |parsed| results << parsed }

      expect(results).to eq([{ "text" => "hello" }])
    end

    it "handles malformed JSON gracefully" do
      response = double("response")
      sse_data = "data: {invalid json}\n\n"

      allow(response).to receive(:read_body).and_yield(sse_data)

      results = []
      expect(Rails.logger).to receive(:warn).with(/Failed to parse SSE chunk/)
      adapter.send(:parse_sse_stream, response) { |parsed| results << parsed }

      expect(results).to be_empty
    end

    it "handles chunked delivery across multiple read_body yields" do
      response = double("response")
      allow(response).to receive(:read_body)
        .and_yield("data: {\"part\"")
        .and_yield(":1}\n\ndata: {\"part\":2}\n\n")

      results = []
      adapter.send(:parse_sse_stream, response) { |parsed| results << parsed }

      expect(results).to eq([{ "part" => 1 }, { "part" => 2 }])
    end
  end

  describe "protected #parse_ndjson_stream" do
    it "parses newline-delimited JSON and yields each object" do
      response = double("response")
      ndjson = "{\"a\":1}\n{\"b\":2}\n"

      allow(response).to receive(:read_body).and_yield(ndjson)

      results = []
      adapter.send(:parse_ndjson_stream, response) { |parsed| results << parsed }

      expect(results).to eq([{ "a" => 1 }, { "b" => 2 }])
    end

    it "skips empty lines" do
      response = double("response")
      ndjson = "{\"a\":1}\n\n{\"b\":2}\n"

      allow(response).to receive(:read_body).and_yield(ndjson)

      results = []
      adapter.send(:parse_ndjson_stream, response) { |parsed| results << parsed }

      expect(results).to eq([{ "a" => 1 }, { "b" => 2 }])
    end

    it "handles malformed NDJSON lines gracefully" do
      response = double("response")
      ndjson = "not-json\n"

      allow(response).to receive(:read_body).and_yield(ndjson)

      results = []
      expect(Rails.logger).to receive(:warn).with(/Failed to parse NDJSON/)
      adapter.send(:parse_ndjson_stream, response) { |parsed| results << parsed }

      expect(results).to be_empty
    end
  end

  describe "protected #build_response" do
    it "creates an Ai::Llm::Response with provider set" do
      response = adapter.send(:build_response, content: "hello", model: "test-model")

      expect(response).to be_a(Ai::Llm::Response)
      expect(response.content).to eq("hello")
      expect(response.provider).to eq("test")
      expect(response.model).to eq("test-model")
    end
  end

  describe "protected #build_error_response" do
    it "creates an error response with finish_reason error" do
      response = adapter.send(:build_error_response, "Something failed", status_code: 500)

      expect(response).to be_a(Ai::Llm::Response)
      expect(response.content).to be_nil
      expect(response.finish_reason).to eq("error")
      expect(response.provider).to eq("test")
      expect(response.raw_response).to include(error: "Something failed", status_code: 500)
    end
  end

  describe Ai::Llm::Adapters::RequestError do
    it "stores status_code" do
      error = described_class.new("HTTP 429: Rate limited", status_code: 429)

      expect(error.message).to eq("HTTP 429: Rate limited")
      expect(error.status_code).to eq(429)
    end

    it "defaults status_code to nil" do
      error = described_class.new("Unknown error")

      expect(error.status_code).to be_nil
    end

    it "inherits from StandardError" do
      expect(described_class.ancestors).to include(StandardError)
    end
  end
end
