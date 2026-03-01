# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::TracingService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  describe "#start_trace" do
    it "creates a new trace with the given name and type" do
      trace = service.start_trace(name: "Test Agent Execution", type: :agent)

      expect(trace[:trace_id]).to start_with("trace_")
      expect(trace[:name]).to eq("Test Agent Execution")
      expect(trace[:type]).to eq("agent")
      expect(trace[:status]).to eq("running")
      expect(trace[:root_span_id]).to start_with("span_")
      expect(trace[:started_at]).to be_present
      expect(trace[:account_id]).to eq(account.id)
    end

    it "creates a root span for the trace" do
      trace = service.start_trace(name: "Test Trace", type: :workflow)

      root_span = service.spans[trace[:root_span_id]]
      expect(root_span).to be_present
      expect(root_span[:name]).to eq("Test Trace")
      expect(root_span[:type]).to eq("root")
      expect(root_span[:parent_span_id]).to be_nil
      expect(root_span[:status]).to eq("running")
    end

    it "accepts metadata" do
      metadata = { agent_id: "agent_123", model: "gpt-4" }
      trace = service.start_trace(name: "Test", type: :agent, metadata: metadata)

      expect(trace[:metadata]).to eq(metadata)
    end
  end

  describe "#start_span" do
    before { service.start_trace(name: "Test", type: :agent) }

    it "creates a new span with the given parameters" do
      span = service.start_span(
        name: "LLM Call",
        type: "llm_call",
        input: { messages: [ "Hello" ] }
      )

      expect(span[:span_id]).to start_with("span_")
      expect(span[:name]).to eq("LLM Call")
      expect(span[:type]).to eq("llm_call")
      expect(span[:status]).to eq("running")
      expect(span[:input]).to eq({ messages: [ "Hello" ] })
      expect(span[:parent_span_id]).to eq(service.current_trace[:root_span_id])
    end

    it "supports nested spans" do
      parent_span = service.start_span(name: "Parent", type: "generic")
      child_span = service.start_span(name: "Child", type: "generic")

      expect(child_span[:parent_span_id]).to eq(parent_span[:span_id])
    end

    it "raises error when no trace is active" do
      new_service = described_class.new(account: account)

      expect { new_service.start_span(name: "Test", type: "generic") }
        .to raise_error("No active trace")
    end
  end

  describe "#end_span" do
    before do
      service.start_trace(name: "Test", type: :agent)
      service.start_span(name: "Test Span", type: "generic")
    end

    it "completes the current span with output" do
      span = service.end_span(output: { result: "success" })

      expect(span[:status]).to eq("completed")
      expect(span[:completed_at]).to be_present
      expect(span[:duration_ms]).to be_present
      expect(span[:output]).to eq({ result: "success" })
    end

    it "marks span as failed with error" do
      span = service.end_span(status: :failed, error: "Something went wrong")

      expect(span[:status]).to eq("failed")
      expect(span[:error]).to eq("Something went wrong")
    end

    it "records token usage and cost" do
      span = service.end_span(
        output: {},
        tokens: { prompt: 100, completion: 50 },
        cost: 0.0015
      )

      expect(span[:tokens]).to eq({ prompt: 100, completion: 50 })
      expect(span[:cost]).to eq(0.0015)
    end

    it "raises error when no spans to end" do
      service.end_span # End the span we started

      expect { service.end_span }.to raise_error("No spans to end")
    end
  end

  describe "#add_event" do
    before do
      service.start_trace(name: "Test", type: :agent)
      service.start_span(name: "Test Span", type: "generic")
    end

    it "adds an event to the current span" do
      service.add_event(name: "checkpoint_reached", data: { step: 1 })

      span_id = service.current_span_id
      span = service.spans[span_id]

      expect(span[:events].length).to eq(1)
      expect(span[:events].first[:name]).to eq("checkpoint_reached")
      expect(span[:events].first[:data]).to eq({ step: 1 })
      expect(span[:events].first[:timestamp]).to be_present
    end
  end

  describe "#record_llm_call" do
    before { service.start_trace(name: "Test", type: :agent) }

    it "records an LLM call as a span" do
      service.record_llm_call(
        provider: "openai",
        model: "gpt-4",
        messages: [ { role: "user", content: "Hello" } ],
        response: { content: "Hi there!" },
        tokens: { prompt: 10, completion: 5 },
        cost: 0.0005
      )

      # Find the LLM call span
      llm_span = service.spans.values.find { |s| s[:type] == "llm_call" }

      expect(llm_span).to be_present
      expect(llm_span[:name]).to eq("LLM Call: openai/gpt-4")
      expect(llm_span[:status]).to eq("completed")
      expect(llm_span[:input][:provider]).to eq("openai")
      expect(llm_span[:input][:model]).to eq("gpt-4")
      expect(llm_span[:tokens]).to eq({ prompt: 10, completion: 5 })
      expect(llm_span[:cost]).to eq(0.0005)
    end
  end

  describe "#record_tool_execution" do
    before { service.start_trace(name: "Test", type: :agent) }

    it "records a successful tool execution" do
      service.record_tool_execution(
        tool_name: "calculator",
        input: { expression: "2 + 2" },
        output: { result: 4 }
      )

      tool_span = service.spans.values.find { |s| s[:type] == "tool_execution" }

      expect(tool_span).to be_present
      expect(tool_span[:name]).to eq("Tool: calculator")
      expect(tool_span[:status]).to eq("completed")
      expect(tool_span[:input]).to eq({ expression: "2 + 2" })
      expect(tool_span[:output]).to eq({ result: 4 })
    end

    it "records a failed tool execution" do
      service.record_tool_execution(
        tool_name: "api_call",
        input: { url: "https://api.example.com" },
        output: nil,
        error: "Connection timeout"
      )

      tool_span = service.spans.values.find { |s| s[:type] == "tool_execution" }

      expect(tool_span[:status]).to eq("failed")
      expect(tool_span[:error]).to eq("Connection timeout")
    end
  end

  describe "#complete_trace" do
    before do
      service.start_trace(name: "Test", type: :agent)
      service.start_span(name: "Span 1", type: "generic")
      service.end_span(output: { done: true })
    end

    it "completes the trace with success status" do
      result = service.complete_trace(status: :completed, output: { result: "success" })

      expect(result[:trace][:status]).to eq("completed")
      expect(result[:trace][:completed_at]).to be_present
      expect(result[:trace][:output]).to eq({ result: "success" })
    end

    it "completes the trace with failure status" do
      result = service.complete_trace(status: :failed, error: "Something went wrong")

      expect(result[:trace][:status]).to eq("failed")
      expect(result[:trace][:error]).to eq("Something went wrong")
    end

    it "ends any remaining open spans" do
      service.start_span(name: "Open Span", type: "generic")
      # Don't end it manually

      result = service.complete_trace(status: :completed)

      open_span = result[:spans].find { |s| s[:name] == "Open Span" }
      expect(open_span[:status]).to eq("cancelled")
    end

    it "returns summary statistics" do
      result = service.complete_trace(status: :completed)

      expect(result[:summary]).to be_present
      expect(result[:summary]).to have_key(:total_spans)
      expect(result[:summary]).to have_key(:llm_calls)
      expect(result[:summary]).to have_key(:tool_executions)
    end
  end

  describe "#current_span_id" do
    it "returns root span id when no child spans" do
      trace = service.start_trace(name: "Test", type: :agent)

      expect(service.current_span_id).to eq(trace[:root_span_id])
    end

    it "returns the most recent span id" do
      service.start_trace(name: "Test", type: :agent)
      span = service.start_span(name: "Child", type: "generic")

      expect(service.current_span_id).to eq(span[:span_id])
    end
  end

  describe ".get_trace" do
    it "returns nil for non-existent trace" do
      result = described_class.get_trace("non_existent", account: account)

      expect(result).to be_nil
    end
  end

  describe ".list_traces" do
    it "returns an empty array when no traces exist" do
      result = described_class.list_traces(account: account)

      expect(result).to eq([])
    end
  end

  describe ".build_summary" do
    it "builds correct summary from spans" do
      spans = [
        { type: "root", status: "completed", tokens: nil, cost: nil },
        { type: "llm_call", status: "completed", tokens: { prompt: 100, completion: 50 }, cost: 0.01 },
        { type: "llm_call", status: "completed", tokens: { prompt: 200, completion: 100 }, cost: 0.02 },
        { type: "tool_execution", status: "completed", tokens: nil, cost: nil },
        { type: "tool_execution", status: "failed", tokens: nil, cost: nil }
      ]

      summary = described_class.build_summary(spans)

      expect(summary[:total_spans]).to eq(5)
      expect(summary[:llm_calls]).to eq(2)
      expect(summary[:tool_executions]).to eq(2)
      expect(summary[:total_tokens]).to eq(450)
      expect(summary[:total_cost]).to eq(0.03)
      expect(summary[:failed_spans]).to eq(1)
    end

    it "returns empty hash for empty spans" do
      expect(described_class.build_summary([])).to eq({})
    end
  end
end
