# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Agui::AdapterService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  describe "#convert_stream_chunk" do
    it "converts text_content to TEXT_MESSAGE_CONTENT" do
      result = service.convert_stream_chunk({
        type: "text_content",
        content: "Hello world",
        message_id: "msg_1"
      })

      expect(result[:type]).to eq("TEXT_MESSAGE_CONTENT")
      expect(result[:content]).to eq("Hello world")
      expect(result[:message_id]).to eq("msg_1")
    end

    it "converts text_start to TEXT_MESSAGE_START" do
      result = service.convert_stream_chunk({ type: "text_start", role: "assistant" })

      expect(result[:type]).to eq("TEXT_MESSAGE_START")
      expect(result[:role]).to eq("assistant")
    end

    it "converts tool_start to TOOL_CALL_START" do
      result = service.convert_stream_chunk({ type: "tool_start", tool_call_id: "tc_1" })

      expect(result[:type]).to eq("TOOL_CALL_START")
      expect(result[:tool_call_id]).to eq("tc_1")
    end

    it "converts run_start to RUN_STARTED" do
      result = service.convert_stream_chunk({ type: "run_start", run_id: "run_1" })

      expect(result[:type]).to eq("RUN_STARTED")
      expect(result[:run_id]).to eq("run_1")
    end

    it "converts run_error to RUN_ERROR" do
      result = service.convert_stream_chunk({ type: "run_error", content: "Error occurred" })

      expect(result[:type]).to eq("RUN_ERROR")
      expect(result[:content]).to eq("Error occurred")
    end

    it "defaults unknown types to CUSTOM" do
      result = service.convert_stream_chunk({ type: "unknown_type", content: "data" })

      expect(result[:type]).to eq("CUSTOM")
    end

    it "includes timestamp" do
      result = service.convert_stream_chunk({ type: "text_content" })

      expect(result[:timestamp]).to be_present
    end

    it "defaults role to assistant" do
      result = service.convert_stream_chunk({ type: "text_content" })

      expect(result[:role]).to eq("assistant")
    end

    it "handles string input (JSON)" do
      json_str = '{"type":"text_content","content":"from json"}'
      result = service.convert_stream_chunk(json_str)

      expect(result[:type]).to eq("TEXT_MESSAGE_CONTENT")
      expect(result[:content]).to eq("from json")
    end

    it "handles invalid JSON string gracefully" do
      result = service.convert_stream_chunk("not valid json")

      expect(result[:type]).to eq("CUSTOM")
    end
  end

  describe "#convert_tool_call" do
    it "generates a sequence of tool call events" do
      events = service.convert_tool_call({
        tool_name: "calculator",
        arguments: { x: 1, y: 2 },
        result: "3"
      })

      types = events.map { |e| e[:type] }
      expect(types).to eq(%w[TOOL_CALL_START TOOL_CALL_ARGS TOOL_CALL_END TOOL_CALL_RESULT])
    end

    it "includes tool_call_id in all events" do
      events = service.convert_tool_call({ tool_name: "test" })
      ids = events.map { |e| e[:tool_call_id] }.compact
      expect(ids.uniq.length).to eq(1) # all same id
    end

    it "serializes arguments to JSON" do
      events = service.convert_tool_call({
        tool_name: "test",
        arguments: { param: "value" }
      })

      args_event = events.find { |e| e[:type] == "TOOL_CALL_ARGS" }
      expect(args_event[:content]).to eq('{"param":"value"}')
    end

    it "omits TOOL_CALL_ARGS when no arguments" do
      events = service.convert_tool_call({ tool_name: "test" })
      types = events.map { |e| e[:type] }

      expect(types).not_to include("TOOL_CALL_ARGS")
    end

    it "omits TOOL_CALL_RESULT when no result" do
      events = service.convert_tool_call({ tool_name: "test" })
      types = events.map { |e| e[:type] }

      expect(types).not_to include("TOOL_CALL_RESULT")
    end

    it "includes tool_name in START metadata" do
      events = service.convert_tool_call({ tool_name: "my_tool" })
      start_event = events.find { |e| e[:type] == "TOOL_CALL_START" }

      expect(start_event[:metadata][:tool_name]).to eq("my_tool")
    end
  end

  describe "#convert_state_update" do
    it "converts operations to STATE_DELTA" do
      result = service.convert_state_update({
        operations: [{ "op" => "add", "path" => "/key", "value" => "val" }]
      })

      expect(result[:type]).to eq("STATE_DELTA")
      expect(result[:delta]).to be_an(Array)
    end

    it "converts full state to STATE_SNAPSHOT" do
      result = service.convert_state_update({
        state: { counter: 5, name: "test" }
      })

      expect(result[:type]).to eq("STATE_SNAPSHOT")
      expect(result[:delta]).to eq({ counter: 5, name: "test" })
    end

    it "defaults to STATE_SNAPSHOT when no operations" do
      result = service.convert_state_update({ key: "value" })

      expect(result[:type]).to eq("STATE_SNAPSHOT")
    end
  end

  describe "STREAM_EVENT_MAP" do
    it "covers all common stream event types" do
      expected_mappings = {
        "text_start" => "TEXT_MESSAGE_START",
        "text_content" => "TEXT_MESSAGE_CONTENT",
        "text_end" => "TEXT_MESSAGE_END",
        "tool_start" => "TOOL_CALL_START",
        "tool_args" => "TOOL_CALL_ARGS",
        "tool_end" => "TOOL_CALL_END",
        "tool_result" => "TOOL_CALL_RESULT",
        "run_start" => "RUN_STARTED",
        "run_end" => "RUN_FINISHED",
        "run_error" => "RUN_ERROR",
        "step_start" => "STEP_STARTED",
        "step_end" => "STEP_FINISHED",
        "state_update" => "STATE_DELTA",
        "state_snapshot" => "STATE_SNAPSHOT"
      }

      expected_mappings.each do |internal, agui|
        expect(described_class::STREAM_EVENT_MAP[internal]).to eq(agui)
      end
    end
  end
end
