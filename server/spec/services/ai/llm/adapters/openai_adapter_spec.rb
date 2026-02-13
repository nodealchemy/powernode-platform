# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::Adapters::OpenaiAdapter do
  let(:adapter) do
    described_class.new(
      api_key: "sk-test-key",
      base_url: "https://api.openai.com/v1"
    )
  end

  describe "#initialize" do
    it "defaults provider_name to openai" do
      expect(adapter.provider_name).to eq("openai")
    end

    it "sets Authorization header with Bearer token" do
      expect(adapter.headers["Authorization"]).to eq("Bearer sk-test-key")
    end

    it "preserves Content-Type header" do
      expect(adapter.headers["Content-Type"]).to eq("application/json")
    end

    it "allows custom provider_name" do
      a = described_class.new(api_key: "k", base_url: "https://api.groq.com/v1", provider_name: "groq")
      expect(a.provider_name).to eq("groq")
    end

    it "merges extra_headers" do
      a = described_class.new(api_key: "k", base_url: "https://api.openai.com/v1", extra_headers: { "X-Org" => "test" })
      expect(a.headers["X-Org"]).to eq("test")
    end
  end

  describe "#complete" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4o" }

    context "when API returns 200" do
      let(:api_response) do
        {
          "id" => "chatcmpl-123",
          "choices" => [{
            "index" => 0,
            "message" => { "role" => "assistant", "content" => "Hi there!" },
            "finish_reason" => "stop"
          }],
          "model" => "gpt-4o-2024-08-06",
          "usage" => {
            "prompt_tokens" => 10,
            "completion_tokens" => 5,
            "total_tokens" => 15
          }
        }
      end

      before do
        allow(adapter).to receive(:http_post).and_return([200, api_response, {}])
      end

      it "returns an Ai::Llm::Response" do
        result = adapter.complete(messages: messages, model: model)
        expect(result).to be_a(Ai::Llm::Response)
      end

      it "extracts content from choices" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.content).to eq("Hi there!")
      end

      it "extracts usage data" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.usage[:prompt_tokens]).to eq(10)
        expect(result.usage[:completion_tokens]).to eq(5)
        expect(result.usage[:total_tokens]).to eq(15)
      end

      it "extracts finish_reason" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("stop")
      end

      it "extracts model from response" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.model).to eq("gpt-4o-2024-08-06")
      end

      it "includes raw_response" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.raw_response).to eq(api_response)
      end
    end

    context "when response contains tool calls" do
      let(:api_response) do
        {
          "choices" => [{
            "message" => {
              "content" => nil,
              "tool_calls" => [{
                "id" => "call_123",
                "type" => "function",
                "function" => {
                  "name" => "get_weather",
                  "arguments" => '{"location":"NYC"}'
                }
              }]
            },
            "finish_reason" => "tool_calls"
          }],
          "model" => model,
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30 }
        }
      end

      before do
        allow(adapter).to receive(:http_post).and_return([200, api_response, {}])
      end

      it "extracts and parses tool calls" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.tool_calls.size).to eq(1)
        expect(result.tool_calls.first[:id]).to eq("call_123")
        expect(result.tool_calls.first[:name]).to eq("get_weather")
        expect(result.tool_calls.first[:arguments]).to eq({ "location" => "NYC" })
      end

      it "reports has_tool_calls?" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.has_tool_calls?).to be true
      end
    end

    context "when response has cached tokens" do
      let(:api_response) do
        {
          "choices" => [{
            "message" => { "content" => "ok" },
            "finish_reason" => "stop"
          }],
          "model" => model,
          "usage" => {
            "prompt_tokens" => 100,
            "completion_tokens" => 10,
            "total_tokens" => 110,
            "prompt_tokens_details" => { "cached_tokens" => 50 }
          }
        }
      end

      before do
        allow(adapter).to receive(:http_post).and_return([200, api_response, {}])
      end

      it "extracts cached_tokens from prompt_tokens_details" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.usage[:cached_tokens]).to eq(50)
      end
    end

    context "when API returns error" do
      before do
        allow(adapter).to receive(:http_post).and_return([
          429, { "error" => { "message" => "Rate limit exceeded" } }, {}
        ])
      end

      it "returns error response" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("error")
        expect(result.raw_response[:error]).to include("Rate limit exceeded")
        expect(result.raw_response[:status_code]).to eq(429)
      end
    end

    context "with system messages" do
      it "keeps system messages in messages array as first message" do
        msgs = [
          { role: "system", content: "You are helpful" },
          { role: "user", content: "Hello" }
        ]

        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:messages].first[:role]).to eq("system")
          expect(body[:messages].first[:content]).to eq("You are helpful")
          [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: msgs, model: model)
      end
    end

    context "with optional parameters" do
      it "defaults temperature to 0.7" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:temperature]).to eq(0.7)
          [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model)
      end

      it "includes presence_penalty when provided" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:presence_penalty]).to eq(0.5)
          [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model, presence_penalty: 0.5)
      end

      it "includes frequency_penalty when provided" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:frequency_penalty]).to eq(0.3)
          [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model, frequency_penalty: 0.3)
      end

      it "includes stop sequences when provided" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:stop]).to eq(["END"])
          [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model, stop: ["END"])
      end
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4o" }

    it "raises ArgumentError without a block" do
      expect {
        adapter.stream(messages: messages, model: model)
      }.to raise_error(ArgumentError, "Block required for streaming")
    end

    context "with successful streaming" do
      before do
        allow(SecureRandom).to receive(:uuid).and_return("stream-123")
      end

      it "yields stream chunks and returns accumulated response" do
        allow(adapter).to receive(:http_stream).and_yield(double("response"))
        allow(adapter).to receive(:parse_sse_stream) do |_response, &block|
          block.call({
            "choices" => [{ "delta" => { "content" => "Hello " } }]
          })
          block.call({
            "choices" => [{ "delta" => { "content" => "world!" } }]
          })
          block.call({
            "choices" => [{ "finish_reason" => "stop", "delta" => {} }],
            "usage" => { "prompt_tokens" => 5, "completion_tokens" => 3, "total_tokens" => 8 }
          })
        end

        chunks = []
        result = adapter.stream(messages: messages, model: model) { |c| chunks << c }

        expect(chunks.first.type).to eq(:stream_start)
        content_chunks = chunks.select { |c| c.type == :content_delta }
        expect(content_chunks.map(&:content)).to eq(["Hello ", "world!"])
        expect(chunks.last.type).to eq(:stream_end)

        expect(result.content).to eq("Hello world!")
        expect(result.finish_reason).to eq("stop")
      end

      it "handles tool call streaming" do
        allow(adapter).to receive(:http_stream).and_yield(double("response"))
        allow(adapter).to receive(:parse_sse_stream) do |_response, &block|
          block.call({
            "choices" => [{
              "delta" => {
                "tool_calls" => [{
                  "index" => 0, "id" => "call_1",
                  "function" => { "name" => "search", "arguments" => "" }
                }]
              }
            }]
          })
          block.call({
            "choices" => [{
              "delta" => {
                "tool_calls" => [{
                  "index" => 0,
                  "function" => { "arguments" => '{"q":"test"}' }
                }]
              }
            }]
          })
          block.call({
            "choices" => [{ "finish_reason" => "tool_calls", "delta" => {} }]
          })
        end

        chunks = []
        result = adapter.stream(messages: messages, model: model) { |c| chunks << c }

        tool_start = chunks.find { |c| c.type == :tool_call_start }
        expect(tool_start.tool_call_name).to eq("search")

        tool_end = chunks.find { |c| c.type == :tool_call_end }
        expect(tool_end.tool_call_id).to eq("call_1")

        expect(result.tool_calls.size).to eq(1)
        expect(result.tool_calls.first[:name]).to eq("search")
        expect(result.tool_calls.first[:arguments]).to eq({ "q" => "test" })
      end

      it "enables stream_options with include_usage" do
        allow(adapter).to receive(:http_stream) do |_path, body, &block|
          expect(body[:stream]).to be true
          expect(body[:stream_options]).to eq({ include_usage: true })
          block.call(double("response"))
        end
        allow(adapter).to receive(:parse_sse_stream)

        adapter.stream(messages: messages, model: model) { |_c| }
      end
    end

    context "when streaming encounters an error" do
      before do
        allow(SecureRandom).to receive(:uuid).and_return("err-stream")
        allow(adapter).to receive(:http_stream).and_raise(
          Ai::Llm::Adapters::RequestError.new("HTTP 500: Internal", status_code: 500)
        )
      end

      it "yields error chunk and returns error response" do
        chunks = []
        result = adapter.stream(messages: messages, model: model) { |c| chunks << c }

        error_chunk = chunks.find { |c| c.type == :error }
        expect(error_chunk).to be_present

        expect(result.finish_reason).to eq("error")
        expect(result.raw_response[:status_code]).to eq(500)
      end
    end
  end

  describe "#complete_with_tools" do
    let(:messages) { [{ role: "user", content: "Search" }] }
    let(:model) { "gpt-4o" }
    let(:tools) do
      [{
        name: "search",
        description: "Search the web",
        parameters: { type: "object", properties: { q: { type: "string" } } }
      }]
    end

    it "converts tools to OpenAI function format" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tools].first[:type]).to eq("function")
        expect(body[:tools].first[:function][:name]).to eq("search")
        expect(body[:tools].first[:function][:parameters]).to be_present
        [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model)
    end

    it "defaults tool_choice to auto" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tool_choice]).to eq("auto")
        [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model)
    end

    it "passes custom tool_choice" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tool_choice]).to eq("required")
        [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model, tool_choice: "required")
    end

    it "includes strict flag when provided" do
      strict_tools = [tools.first.merge(strict: true)]

      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tools].first[:function][:strict]).to be true
        [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: strict_tools, model: model)
    end
  end

  describe "#complete_structured" do
    let(:messages) { [{ role: "user", content: "Extract" }] }
    let(:model) { "gpt-4o" }
    let(:schema) do
      {
        name: "person",
        schema: {
          type: "object",
          properties: { name: { type: "string" } },
          required: ["name"]
        }
      }
    end

    it "sends response_format with json_schema" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:response_format][:type]).to eq("json_schema")
        expect(body[:response_format][:json_schema][:name]).to eq("person")
        expect(body[:response_format][:json_schema][:strict]).to be true
        [200, { "choices" => [{ "message" => { "content" => '{"name":"Alice"}' }, "finish_reason" => "stop" }], "usage" => {} }, {}]
      end

      adapter.complete_structured(messages: messages, schema: schema, model: model)
    end

    it "defaults name to 'response' when not provided" do
      flat_schema = { type: "object", properties: { x: { type: "string" } } }

      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:response_format][:json_schema][:name]).to eq("response")
        [200, { "choices" => [{ "message" => { "content" => '{"x":"y"}' }, "finish_reason" => "stop" }], "usage" => {} }, {}]
      end

      adapter.complete_structured(messages: messages, schema: flat_schema, model: model)
    end
  end

  describe "message normalization" do
    let(:model) { "gpt-4o" }

    it "passes tool result messages with tool_call_id" do
      msgs = [
        { role: "user", content: "Use tool" },
        { role: "tool", tool_call_id: "call_1", content: "result" }
      ]

      allow(adapter).to receive(:http_post) do |_path, body|
        tool_msg = body[:messages].find { |m| m[:role] == "tool" }
        expect(tool_msg[:tool_call_id]).to eq("call_1")
        [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
      end

      adapter.complete(messages: msgs, model: model)
    end

    it "passes assistant messages with tool_calls" do
      msgs = [
        { role: "assistant", content: "calling tool", tool_calls: [{ id: "c1", function: { name: "fn" } }] }
      ]

      allow(adapter).to receive(:http_post) do |_path, body|
        asst_msg = body[:messages].find { |m| m[:role] == "assistant" }
        expect(asst_msg[:tool_calls]).to be_present
        [200, { "choices" => [{ "message" => { "content" => "ok" }, "finish_reason" => "stop" }], "usage" => {} }, {}]
      end

      adapter.complete(messages: msgs, model: model)
    end
  end

  describe "error handling" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "gpt-4o" }

    it "handles string error body" do
      allow(adapter).to receive(:http_post).and_return([500, "Server Error", {}])

      result = adapter.complete(messages: messages, model: model)
      expect(result.finish_reason).to eq("error")
    end

    it "handles hash error with nested message" do
      allow(adapter).to receive(:http_post).and_return([
        400, { "error" => { "message" => "Invalid model" } }, {}
      ])

      result = adapter.complete(messages: messages, model: model)
      expect(result.raw_response[:error]).to include("Invalid model")
    end

    it "handles hash error body as JSON when error is a Hash" do
      allow(adapter).to receive(:http_post).and_return([
        400, { "error" => { "type" => "invalid_request", "code" => "bad_param" } }, {}
      ])

      result = adapter.complete(messages: messages, model: model)
      expect(result.finish_reason).to eq("error")
    end
  end
end
