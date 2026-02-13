# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Llm::Adapters::OllamaAdapter do
  let(:adapter) do
    described_class.new(base_url: "http://localhost:11434")
  end

  describe "#initialize" do
    it "defaults provider_name to ollama" do
      expect(adapter.provider_name).to eq("ollama")
    end

    it "does not require api_key" do
      expect(adapter.api_key).to be_nil
    end

    it "sets Authorization header when api_key is provided" do
      a = described_class.new(api_key: "test-key", base_url: "http://localhost:11434")
      expect(a.headers["Authorization"]).to eq("Bearer test-key")
    end

    it "does not set Authorization header when api_key is nil" do
      expect(adapter.headers).not_to have_key("Authorization")
    end

    it "stores raw_base_url" do
      expect(adapter.base_url).to eq("http://localhost:11434")
    end

    it "strips trailing slashes" do
      a = described_class.new(base_url: "http://localhost:11434/")
      expect(a.base_url).to eq("http://localhost:11434")
    end
  end

  describe "URL building" do
    it "appends /api/chat for standard Ollama URLs" do
      a = described_class.new(base_url: "http://localhost:11434")
      url = a.send(:build_chat_url)
      expect(url).to eq("http://localhost:11434/api/chat")
    end

    it "appends /chat for URLs ending with /api" do
      a = described_class.new(base_url: "http://localhost:11434/api")
      url = a.send(:build_chat_url)
      expect(url).to eq("http://localhost:11434/api/chat")
    end

    it "appends /api/chat for Open WebUI URLs with /ollama" do
      a = described_class.new(base_url: "http://localhost:8080/ollama")
      url = a.send(:build_chat_url)
      expect(url).to eq("http://localhost:8080/ollama/api/chat")
    end
  end

  describe "#complete" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "llama3.1" }

    context "when API returns 200" do
      let(:api_response_body) do
        {
          "model" => "llama3.1",
          "message" => { "role" => "assistant", "content" => "Hello! How can I help?" },
          "done" => true,
          "prompt_eval_count" => 10,
          "eval_count" => 20
        }.to_json
      end

      before do
        mock_response = double(code: 200, body: api_response_body, parsed_response: nil)
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      it "returns an Ai::Llm::Response" do
        result = adapter.complete(messages: messages, model: model)
        expect(result).to be_a(Ai::Llm::Response)
      end

      it "extracts content" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.content).to eq("Hello! How can I help?")
      end

      it "extracts usage data with Ollama field names" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.usage[:prompt_tokens]).to eq(10)
        expect(result.usage[:completion_tokens]).to eq(20)
        expect(result.usage[:total_tokens]).to eq(30)
      end

      it "sets finish_reason to stop when done is true" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("stop")
      end

      it "sets finish_reason to length when done is false" do
        body = {
          "model" => "llama3.1",
          "message" => { "content" => "partial" },
          "done" => false
        }.to_json
        mock_response = double(code: 200, body: body)
        allow(HTTParty).to receive(:post).and_return(mock_response)

        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("length")
      end
    end

    context "when response contains tool calls" do
      let(:api_response_body) do
        {
          "model" => "llama3.1",
          "message" => {
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [{
              "function" => { "name" => "get_time", "arguments" => { "timezone" => "UTC" } }
            }]
          },
          "done" => true,
          "prompt_eval_count" => 10,
          "eval_count" => 15
        }.to_json
      end

      before do
        mock_response = double(code: 200, body: api_response_body)
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      it "extracts tool calls with generated IDs" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.tool_calls.size).to eq(1)
        expect(result.tool_calls.first[:name]).to eq("get_time")
        expect(result.tool_calls.first[:arguments]).to eq({ "timezone" => "UTC" })
        expect(result.tool_calls.first[:id]).to be_present
      end
    end

    context "when API returns error" do
      before do
        mock_response = double(code: 404, parsed_response: { "error" => "model not found" })
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      it "returns error response" do
        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("error")
        expect(result.raw_response[:error]).to include("model not found")
      end
    end

    context "when connection fails" do
      it "handles Errno::ECONNREFUSED" do
        allow(HTTParty).to receive(:post).and_raise(Errno::ECONNREFUSED, "Connection refused")

        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("error")
        expect(result.raw_response[:error]).to include("Ollama connection failed")
      end

      it "handles Errno::EHOSTUNREACH" do
        allow(HTTParty).to receive(:post).and_raise(Errno::EHOSTUNREACH, "Host unreachable")

        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("error")
        expect(result.raw_response[:error]).to include("Ollama connection failed")
      end

      it "handles Errno::ETIMEDOUT" do
        allow(HTTParty).to receive(:post).and_raise(Errno::ETIMEDOUT, "Timed out")

        result = adapter.complete(messages: messages, model: model)
        expect(result.finish_reason).to eq("error")
        expect(result.raw_response[:error]).to include("Ollama connection failed")
      end
    end

    context "with optional parameters" do
      it "sets stream to false" do
        allow(HTTParty).to receive(:post) do |_url, opts|
          body = JSON.parse(opts[:body])
          expect(body["stream"]).to be false
          double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
        end

        adapter.complete(messages: messages, model: model)
      end

      it "maps temperature to options" do
        allow(HTTParty).to receive(:post) do |_url, opts|
          body = JSON.parse(opts[:body])
          expect(body["options"]["temperature"]).to eq(0.5)
          double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
        end

        adapter.complete(messages: messages, model: model, temperature: 0.5)
      end

      it "maps max_tokens to options.num_predict" do
        allow(HTTParty).to receive(:post) do |_url, opts|
          body = JSON.parse(opts[:body])
          expect(body["options"]["num_predict"]).to eq(1000)
          double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
        end

        adapter.complete(messages: messages, model: model, max_tokens: 1000)
      end

      it "includes keep_alive when provided" do
        allow(HTTParty).to receive(:post) do |_url, opts|
          body = JSON.parse(opts[:body])
          expect(body["keep_alive"]).to eq("5m")
          double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
        end

        adapter.complete(messages: messages, model: model, keep_alive: "5m")
      end

      it "uses 300s timeout" do
        allow(HTTParty).to receive(:post) do |_url, opts|
          expect(opts[:timeout]).to eq(300)
          double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
        end

        adapter.complete(messages: messages, model: model)
      end
    end
  end

  describe "#stream" do
    let(:messages) { [{ role: "user", content: "Hello" }] }
    let(:model) { "llama3.1" }

    it "raises ArgumentError without a block" do
      expect {
        adapter.stream(messages: messages, model: model)
      }.to raise_error(ArgumentError, "Block required for streaming")
    end

    context "with successful streaming" do
      before do
        allow(SecureRandom).to receive(:uuid).and_return("stream-id")
      end

      it "yields NDJSON chunks and returns accumulated response" do
        response = double("response")
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:request).and_yield(response)

        allow(adapter).to receive(:parse_ndjson_stream).and_yield(
          { "message" => { "content" => "Hello " } }
        ).and_yield(
          { "message" => { "content" => "world!" }, "done" => true, "prompt_eval_count" => 5, "eval_count" => 3 }
        )

        chunks = []
        result = adapter.stream(messages: messages, model: model) { |c| chunks << c }

        expect(chunks.first.type).to eq(:stream_start)
        content_chunks = chunks.select { |c| c.type == :content_delta }
        expect(content_chunks.map(&:content)).to eq(["Hello ", "world!"])
        expect(chunks.last.type).to eq(:stream_end)

        expect(result.content).to eq("Hello world!")
        expect(result.finish_reason).to eq("stop")
      end

      it "yields error chunk on non-success HTTP response" do
        response = double("response", code: "500")
        allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)

        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:request).and_yield(response)

        chunks = []
        result = adapter.stream(messages: messages, model: model) { |c| chunks << c }

        error_chunk = chunks.find { |c| c.type == :error }
        expect(error_chunk).to be_present
        expect(result.finish_reason).to eq("error")
      end
    end

    context "when connection fails during streaming" do
      before do
        allow(SecureRandom).to receive(:uuid).and_return("err-stream")
      end

      it "handles Errno::ECONNREFUSED" do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED, "Connection refused")

        chunks = []
        result = adapter.stream(messages: messages, model: model) { |c| chunks << c }

        error_chunk = chunks.find { |c| c.type == :error }
        expect(error_chunk).to be_present
        expect(result.finish_reason).to eq("error")
        expect(result.raw_response[:error]).to include("Ollama connection failed")
      end
    end
  end

  describe "#complete_with_tools" do
    let(:messages) { [{ role: "user", content: "What time is it?" }] }
    let(:model) { "llama3.1" }
    let(:tools) do
      [{
        name: "get_time",
        description: "Get current time",
        parameters: { type: "object", properties: { tz: { type: "string" } } }
      }]
    end

    it "converts tools to function format" do
      allow(HTTParty).to receive(:post) do |_url, opts|
        body = JSON.parse(opts[:body])
        expect(body["tools"].first["type"]).to eq("function")
        expect(body["tools"].first["function"]["name"]).to eq("get_time")
        double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model)
    end

    it "sets stream to false" do
      allow(HTTParty).to receive(:post) do |_url, opts|
        body = JSON.parse(opts[:body])
        expect(body["stream"]).to be false
        double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
      end

      adapter.complete_with_tools(messages: messages, tools: tools, model: model)
    end

    it "handles connection errors" do
      allow(HTTParty).to receive(:post).and_raise(Errno::ECONNREFUSED, "Connection refused")

      result = adapter.complete_with_tools(messages: messages, tools: tools, model: model)
      expect(result.finish_reason).to eq("error")
      expect(result.raw_response[:error]).to include("Ollama connection failed")
    end
  end

  describe "#complete_structured" do
    let(:messages) { [{ role: "user", content: "Extract data" }] }
    let(:model) { "llama3.1" }
    let(:schema) do
      {
        schema: {
          type: "object",
          properties: { name: { type: "string" } }
        }
      }
    end

    it "sends format with the schema" do
      allow(HTTParty).to receive(:post) do |_url, opts|
        body = JSON.parse(opts[:body])
        expect(body["format"]).to be_present
        expect(body["format"]["type"]).to eq("object")
        double(code: 200, body: { "message" => { "content" => '{"name":"test"}' }, "done" => true }.to_json)
      end

      adapter.complete_structured(messages: messages, schema: schema, model: model)
    end

    it "uses schema directly if no :schema key" do
      flat_schema = { type: "object", properties: { x: { type: "string" } } }

      allow(HTTParty).to receive(:post) do |_url, opts|
        body = JSON.parse(opts[:body])
        expect(body["format"]["type"]).to eq("object")
        double(code: 200, body: { "message" => { "content" => '{"x":"y"}' }, "done" => true }.to_json)
      end

      adapter.complete_structured(messages: messages, schema: flat_schema, model: model)
    end

    it "handles connection errors" do
      allow(HTTParty).to receive(:post).and_raise(Errno::ETIMEDOUT, "Timed out")

      result = adapter.complete_structured(messages: messages, schema: schema, model: model)
      expect(result.finish_reason).to eq("error")
    end
  end

  describe "message normalization" do
    let(:model) { "llama3.1" }

    it "converts tool result messages" do
      msgs = [
        { role: "tool", content: "result data" }
      ]

      allow(HTTParty).to receive(:post) do |_url, opts|
        body = JSON.parse(opts[:body])
        tool_msg = body["messages"].find { |m| m["role"] == "tool" }
        expect(tool_msg["content"]).to eq("result data")
        double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
      end

      adapter.complete(messages: msgs, model: model)
    end

    it "converts non-string tool content to JSON" do
      msgs = [
        { role: "tool", content: { key: "value" } }
      ]

      allow(HTTParty).to receive(:post) do |_url, opts|
        body = JSON.parse(opts[:body])
        tool_msg = body["messages"].find { |m| m["role"] == "tool" }
        expect(tool_msg["content"]).to eq({ "key" => "value" }.to_json)
        double(code: 200, body: { "message" => { "content" => "ok" }, "done" => true }.to_json)
      end

      adapter.complete(messages: msgs, model: model)
    end
  end
end
