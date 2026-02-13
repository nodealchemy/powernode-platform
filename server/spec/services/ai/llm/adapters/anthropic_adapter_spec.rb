# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::Adapters::AnthropicAdapter do
  let(:adapter) do
    described_class.new(api_key: "sk-ant-test-key")
  end

  describe "#initialize" do
    it "defaults base_url to Anthropic API" do
      expect(adapter.base_url).to eq("https://api.anthropic.com/v1")
    end

    it "defaults provider_name to anthropic" do
      expect(adapter.provider_name).to eq("anthropic")
    end

    it "sets x-api-key header" do
      expect(adapter.headers["x-api-key"]).to eq("sk-ant-test-key")
    end

    it "sets anthropic-version header" do
      expect(adapter.headers["anthropic-version"]).to eq("2023-06-01")
    end

    it "allows custom base_url" do
      a = described_class.new(api_key: "k", base_url: "https://custom.api.com/v1")
      expect(a.base_url).to eq("https://custom.api.com/v1")
    end

    it "merges extra_headers" do
      a = described_class.new(api_key: "k", extra_headers: { "X-Custom" => "val" })
      expect(a.headers["X-Custom"]).to eq("val")
      expect(a.headers["x-api-key"]).to eq("k")
    end
  end

  describe "#complete" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "claude-3-5-sonnet-20241022" }

    context "when API returns 200" do
      let(:api_response) do
        {
          "id" => "msg_123",
          "content" => [
            { "type" => "text", "text" => "Hello! How can I help?" }
          ],
          "model" => model,
          "stop_reason" => "end_turn",
          "usage" => {
            "input_tokens" => 10,
            "output_tokens" => 25,
            "cache_read_input_tokens" => 0
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

      it "extracts text content" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.content).to eq("Hello! How can I help?")
      end

      it "extracts usage data" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.usage[:prompt_tokens]).to eq(10)
        expect(result.usage[:completion_tokens]).to eq(25)
        expect(result.usage[:cached_tokens]).to eq(0)
      end

      it "extracts finish_reason from stop_reason" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("end_turn")
      end

      it "sets provider to anthropic" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.provider).to eq("anthropic")
      end
    end

    context "when response contains tool_use blocks" do
      let(:api_response) do
        {
          "content" => [
            { "type" => "text", "text" => "Let me search that." },
            {
              "type" => "tool_use",
              "id" => "toolu_123",
              "name" => "search",
              "input" => { "query" => "test" }
            }
          ],
          "model" => model,
          "stop_reason" => "tool_use",
          "usage" => { "input_tokens" => 10, "output_tokens" => 30 }
        }
      end

      before do
        allow(adapter).to receive(:http_post).and_return([200, api_response, {}])
      end

      it "extracts tool calls" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.tool_calls.size).to eq(1)
        expect(result.tool_calls.first[:name]).to eq("search")
        expect(result.tool_calls.first[:arguments]).to eq({ "query" => "test" })
      end

      it "reports has_tool_calls?" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.has_tool_calls?).to be true
      end
    end

    context "when response contains thinking blocks" do
      let(:api_response) do
        {
          "content" => [
            { "type" => "thinking", "thinking" => "Let me reason about this..." },
            { "type" => "text", "text" => "The answer is 42." }
          ],
          "model" => model,
          "stop_reason" => "end_turn",
          "usage" => { "input_tokens" => 10, "output_tokens" => 50 }
        }
      end

      before do
        allow(adapter).to receive(:http_post).and_return([200, api_response, {}])
      end

      it "extracts thinking content" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.thinking_content).to eq("Let me reason about this...")
      end
    end

    context "when API returns an error" do
      before do
        error_body = { "error" => { "message" => "Invalid API key" } }
        allow(adapter).to receive(:http_post).and_return([401, error_body, {}])
      end

      it "returns an error response" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("error")
      end

      it "includes error message and status code" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.raw_response[:error]).to include("Invalid API key")
        expect(result.raw_response[:error]).to include("HTTP 401")
      end
    end

    context "when API returns rate limit error" do
      before do
        error_body = { "error" => { "message" => "Rate limit exceeded" } }
        allow(adapter).to receive(:http_post).and_return([429, error_body, {}])
      end

      it "returns error response with rate limit info" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("error")
        expect(result.raw_response[:status_code]).to eq(429)
      end
    end

    context "with system messages" do
      it "separates system messages from user messages in the body" do
        msgs = [
          { role: "system", content: "You are helpful" },
          { role: "user", content: "Hello" }
        ]

        allow(adapter).to receive(:http_post) do |_path, body|
          # System should be a top-level param
          expect(body[:system]).to eq("You are helpful")
          # Messages should not include system role
          expect(body[:messages].none? { |m| m[:role] == "system" }).to be true
          [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: msgs, model: model)
      end
    end

    context "with system_prompt option" do
      it "appends system_prompt to system messages" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:system]).to include("Extra system instruction")
          [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
        end

        adapter.complete(
          messages: messages, model: model,
          system_prompt: "Extra system instruction"
        )
      end
    end

    context "with optional parameters" do
      it "includes temperature when provided" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:temperature]).to eq(0.5)
          [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model, temperature: 0.5)
      end

      it "includes top_p when provided" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:top_p]).to eq(0.9)
          [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model, top_p: 0.9)
      end

      it "includes stop_sequences when stop is provided" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:stop_sequences]).to eq(["END"])
          [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model, stop: ["END"])
      end

      it "defaults max_tokens to 4096" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:max_tokens]).to eq(4096)
          [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model)
      end

      it "includes thinking budget when provided" do
        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:thinking]).to eq({ type: "enabled", budget_tokens: 10000 })
          [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: messages, model: model, thinking_budget: 10000)
      end
    end

    context "with cache_system_prompt option" do
      it "adds cache_control to system param" do
        msgs = [{ role: "system", content: "Cached system" }, { role: "user", content: "Hi" }]

        allow(adapter).to receive(:http_post) do |_path, body|
          expect(body[:system]).to be_an(Array)
          expect(body[:system].first[:cache_control]).to eq({ type: "ephemeral" })
          [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
        end

        adapter.complete(messages: msgs, model: model, cache_system_prompt: true)
      end
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "claude-3-5-sonnet-20241022" }

    it "raises ArgumentError without a block" do
      expect {
        adapter.stream(messages: messages, model: model)
      }.to raise_error(ArgumentError, "Block required for streaming")
    end

    context "with successful streaming" do
      let(:stream_id) { "test-uuid" }

      before do
        allow(SecureRandom).to receive(:uuid).and_return(stream_id)
      end

      it "yields stream_start, content deltas, and stream_end chunks" do
        # Mock the streaming flow
        allow(adapter).to receive(:http_stream).and_yield(double("response"))
        allow(adapter).to receive(:parse_anthropic_sse_stream) do |_response, &block|
          block.call("message_start", {
            "message" => { "usage" => { "input_tokens" => 10, "cache_read_input_tokens" => 0 } }
          })
          block.call("content_block_delta", {
            "delta" => { "type" => "text_delta", "text" => "Hello " }
          })
          block.call("content_block_delta", {
            "delta" => { "type" => "text_delta", "text" => "world!" }
          })
          block.call("message_delta", {
            "delta" => { "stop_reason" => "end_turn" },
            "usage" => { "output_tokens" => 5 }
          })
        end

        chunks = []
        result = adapter.stream(messages: messages, model: model) { |chunk| chunks << chunk }

        expect(chunks.first.type).to eq(:stream_start)
        content_deltas = chunks.select { |c| c.type == :content_delta }
        expect(content_deltas.size).to eq(2)
        expect(content_deltas.map(&:content)).to eq(["Hello ", "world!"])
        expect(chunks.last.type).to eq(:stream_end)
        expect(chunks.last.done).to be true

        expect(result).to be_a(Ai::Llm::Response)
        expect(result.content).to eq("Hello world!")
        expect(result.finish_reason).to eq("end_turn")
      end

      it "handles tool call streaming" do
        allow(adapter).to receive(:http_stream).and_yield(double("response"))
        allow(adapter).to receive(:parse_anthropic_sse_stream) do |_response, &block|
          block.call("message_start", { "message" => { "usage" => { "input_tokens" => 5 } } })
          block.call("content_block_start", {
            "content_block" => { "type" => "tool_use", "id" => "toolu_1", "name" => "search" }
          })
          block.call("content_block_delta", {
            "delta" => { "type" => "input_json_delta", "partial_json" => '{"query":' }
          })
          block.call("content_block_delta", {
            "delta" => { "type" => "input_json_delta", "partial_json" => '"test"}' }
          })
          block.call("content_block_stop", {})
          block.call("message_delta", {
            "delta" => { "stop_reason" => "tool_use" },
            "usage" => { "output_tokens" => 20 }
          })
        end

        chunks = []
        result = adapter.stream(messages: messages, model: model) { |chunk| chunks << chunk }

        tool_start = chunks.find { |c| c.type == :tool_call_start }
        expect(tool_start.tool_call_name).to eq("search")
        expect(tool_start.tool_call_id).to eq("toolu_1")

        tool_end = chunks.find { |c| c.type == :tool_call_end }
        expect(tool_end.tool_call_id).to eq("toolu_1")

        expect(result.tool_calls.size).to eq(1)
        expect(result.tool_calls.first[:name]).to eq("search")
        expect(result.tool_calls.first[:arguments]).to eq({ "query" => "test" })
      end

      it "handles thinking deltas" do
        allow(adapter).to receive(:http_stream).and_yield(double("response"))
        allow(adapter).to receive(:parse_anthropic_sse_stream) do |_response, &block|
          block.call("message_start", { "message" => { "usage" => { "input_tokens" => 5 } } })
          block.call("content_block_delta", {
            "delta" => { "type" => "thinking_delta", "thinking" => "Thinking..." }
          })
          block.call("content_block_delta", {
            "delta" => { "type" => "text_delta", "text" => "Result" }
          })
          block.call("message_delta", { "delta" => { "stop_reason" => "end_turn" }, "usage" => { "output_tokens" => 5 } })
        end

        chunks = []
        result = adapter.stream(messages: messages, model: model) { |chunk| chunks << chunk }

        thinking_chunks = chunks.select { |c| c.type == :thinking_delta }
        expect(thinking_chunks.size).to eq(1)
        expect(result.thinking_content).to eq("Thinking...")
      end
    end

    context "when streaming encounters an error" do
      before do
        allow(SecureRandom).to receive(:uuid).and_return("err-stream-id")
        allow(adapter).to receive(:http_stream).and_raise(
          Ai::Llm::Adapters::RequestError.new("HTTP 500: Server error", status_code: 500)
        )
      end

      it "yields an error chunk and returns error response" do
        chunks = []
        result = adapter.stream(messages: messages, model: model) { |chunk| chunks << chunk }

        # stream_start is yielded before http_stream
        error_chunk = chunks.find { |c| c.type == :error }
        expect(error_chunk).to be_present
        expect(error_chunk.content).to include("500")

        expect(result.finish_reason).to eq("error")
      end
    end
  end

  describe "#complete_with_tools" do
    let(:messages) { [{ role: "user", content: "Search for weather" }] }
    let(:model) { "claude-3-5-sonnet-20241022" }
    let(:tools) do
      [{
        name: "get_weather",
        description: "Get current weather",
        parameters: {
          type: "object",
          properties: { location: { type: "string" } },
          required: ["location"]
        }
      }]
    end

    it "converts tools to Anthropic format with input_schema" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tools].first[:input_schema]).to be_present
        expect(body[:tools].first[:name]).to eq("get_weather")
        [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model)
    end

    it "defaults tool_choice to auto" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tool_choice]).to eq({ type: "auto" })
        [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model)
    end

    it "maps tool_choice 'required' to Anthropic 'any'" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tool_choice]).to eq({ type: "any" })
        [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model, tool_choice: "required")
    end

    it "maps tool_choice 'none' to Anthropic 'none'" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tool_choice]).to eq({ type: "none" })
        [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model, tool_choice: "none")
    end

    it "maps specific tool name to named tool_choice" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:tool_choice]).to eq({ type: "tool", name: "get_weather" })
        [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model, tool_choice: "get_weather")
    end
  end

  describe "#complete_structured" do
    let(:messages) { [{ role: "user", content: "Extract data" }] }
    let(:model) { "claude-3-5-sonnet-20241022" }
    let(:schema) do
      {
        schema: {
          type: "object",
          properties: { name: { type: "string" }, age: { type: "integer" } },
          required: ["name"]
        }
      }
    end

    it "sends output_config with JSON schema" do
      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:output_config]).to eq({
          format: { type: "json", schema: schema[:schema] }
        })
        [200, { "content" => [{ "type" => "text", "text" => '{"name":"Alice"}' }], "usage" => {} }, {}]
      end

      adapter.complete_structured(messages: messages, schema: schema, model: model)
    end

    it "uses schema directly if no :schema key" do
      flat_schema = { type: "object", properties: { x: { type: "string" } } }

      allow(adapter).to receive(:http_post) do |_path, body|
        expect(body[:output_config][:format][:schema]).to eq(flat_schema)
        [200, { "content" => [{ "type" => "text", "text" => '{"x":"y"}' }], "usage" => {} }, {}]
      end

      adapter.complete_structured(messages: messages, schema: flat_schema, model: model)
    end
  end

  describe "message normalization" do
    let(:model) { "claude-3-5-sonnet-20241022" }

    it "converts tool result messages from OpenAI format to Anthropic format" do
      msgs = [
        { role: "user", content: "Use the tool" },
        { role: "assistant", content: "OK", tool_calls: [{ id: "tc_1", name: "fn", arguments: {} }] },
        { role: "tool", tool_call_id: "tc_1", content: "result data" }
      ]

      allow(adapter).to receive(:http_post) do |_path, body|
        # Tool result should be converted to user role with tool_result type
        tool_msg = body[:messages].find { |m| m[:role] == "user" && m[:content].is_a?(Array) }
        expect(tool_msg).to be_present
        expect(tool_msg[:content].first[:type]).to eq("tool_result")
        expect(tool_msg[:content].first[:tool_use_id]).to eq("tc_1")
        [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
      end

      adapter.complete(messages: msgs, model: model)
    end

    it "converts assistant messages with tool_calls to tool_use content blocks" do
      msgs = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Using tool", tool_calls: [{ id: "tc_1", name: "fn", arguments: { a: 1 } }] }
      ]

      allow(adapter).to receive(:http_post) do |_path, body|
        assistant_msg = body[:messages].find { |m| m[:role] == "assistant" }
        expect(assistant_msg[:content]).to be_an(Array)
        tool_use = assistant_msg[:content].find { |b| b[:type] == "tool_use" }
        expect(tool_use[:name]).to eq("fn")
        [200, { "content" => [{ "type" => "text", "text" => "ok" }], "usage" => {} }, {}]
      end

      adapter.complete(messages: msgs, model: model)
    end
  end

  describe "error handling" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "claude-3-5-sonnet-20241022" }

    it "handles string error body" do
      allow(adapter).to receive(:http_post).and_return([500, "Internal Server Error", {}])

      result = adapter.complete(messages: messages, model: model)
      expect(result.finish_reason).to eq("error")
      expect(result.raw_response[:error]).to include("Internal Server Error")
    end

    it "handles hash error with nested message" do
      allow(adapter).to receive(:http_post).and_return([
        400, { "error" => { "message" => "Invalid request" } }, {}
      ])

      result = adapter.complete(messages: messages, model: model)
      expect(result.raw_response[:error]).to include("Invalid request")
    end

    it "handles hash error without nested message" do
      allow(adapter).to receive(:http_post).and_return([
        400, { "error" => "Bad request" }, {}
      ])

      result = adapter.complete(messages: messages, model: model)
      expect(result.raw_response[:error]).to include("Bad request")
    end
  end
end
