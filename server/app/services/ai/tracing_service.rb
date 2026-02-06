# frozen_string_literal: true

# Ai::TracingService - LangSmith-style execution tracing for AI operations
#
# Provides span-based tracing for debugging and monitoring complex
# agent/workflow executions. Each operation is recorded as a span
# with timing, input/output, tokens, costs, and error details.
#
# Usage:
#   tracer = Ai::TracingService.new(account: current_account)
#   trace = tracer.start_trace(name: "Agent Execution", type: :agent)
#
#   tracer.start_span(name: "Build Messages", parent_span_id: trace.root_span_id)
#   # ... do work ...
#   tracer.end_span(output: result)
#
#   tracer.complete_trace(status: :completed)
#
class Ai::TracingService
  # Span status values
  SPAN_STATUS = %w[pending running completed failed cancelled].freeze

  # Trace types
  TRACE_TYPES = %w[agent workflow conversation tool mcp batch].freeze

  attr_reader :account, :current_trace, :spans

  def initialize(account:)
    @account = account
    @current_trace = nil
    @spans = {}
    @span_stack = []
  end

  # Start a new trace for an operation
  #
  # @param name [String] Human-readable trace name
  # @param type [Symbol] Type of operation (:agent, :workflow, :conversation, etc.)
  # @param metadata [Hash] Additional trace metadata
  # @return [Hash] Trace data with trace_id and root_span_id
  def start_trace(name:, type:, metadata: {})
    trace_id = generate_trace_id
    root_span_id = generate_span_id

    @current_trace = {
      trace_id: trace_id,
      name: name,
      type: type.to_s,
      status: "running",
      root_span_id: root_span_id,
      started_at: Time.current,
      completed_at: nil,
      metadata: metadata,
      account_id: account.id
    }

    # Create root span
    create_span(
      span_id: root_span_id,
      name: name,
      type: "root",
      parent_span_id: nil
    )

    persist_trace(@current_trace)

    @current_trace
  end

  # Start a new span within the current trace
  #
  # @param name [String] Span name
  # @param type [String] Span type (e.g., "llm_call", "tool_execution", "retrieval")
  # @param parent_span_id [String] Parent span ID (defaults to current span)
  # @param input [Hash] Input data for this span
  # @param metadata [Hash] Additional span metadata
  # @return [Hash] Span data
  def start_span(name:, type: "generic", parent_span_id: nil, input: nil, metadata: {})
    raise "No active trace" unless @current_trace

    span_id = generate_span_id
    parent = parent_span_id || @span_stack.last || @current_trace[:root_span_id]

    span = create_span(
      span_id: span_id,
      name: name,
      type: type,
      parent_span_id: parent,
      input: input,
      metadata: metadata
    )

    @span_stack.push(span_id)
    persist_span(span)

    span
  end

  # End the current span
  #
  # @param output [Hash] Output data from the span
  # @param status [Symbol] Span status (:completed, :failed)
  # @param error [String] Error message if failed
  # @param tokens [Hash] Token usage { prompt: N, completion: N }
  # @param cost [Float] Cost in USD
  # @return [Hash] Updated span data
  def end_span(output: nil, status: :completed, error: nil, tokens: nil, cost: nil)
    raise "No spans to end" if @span_stack.empty?

    span_id = @span_stack.pop
    span = @spans[span_id]
    return nil unless span

    span[:completed_at] = Time.current
    span[:duration_ms] = ((span[:completed_at] - span[:started_at]) * 1000).round
    span[:status] = status.to_s
    span[:output] = output
    span[:error] = error if error
    span[:tokens] = tokens if tokens
    span[:cost] = cost if cost

    persist_span(span)

    span
  end

  # Add an event to the current span (for logging intermediate steps)
  #
  # @param name [String] Event name
  # @param data [Hash] Event data
  def add_event(name:, data: {})
    return unless @span_stack.any?

    span_id = @span_stack.last
    span = @spans[span_id]
    return unless span

    span[:events] ||= []
    span[:events] << {
      name: name,
      data: data,
      timestamp: Time.current.iso8601
    }

    persist_span(span)
  end

  # Record an LLM call within the current span
  #
  # @param provider [String] Provider name (e.g., "openai", "anthropic")
  # @param model [String] Model name
  # @param messages [Array] Input messages
  # @param response [Hash] LLM response
  # @param tokens [Hash] Token usage
  # @param cost [Float] Cost in USD
  # @param latency_ms [Integer] Response time in milliseconds
  def record_llm_call(provider:, model:, messages:, response:, tokens: nil, cost: nil, latency_ms: nil)
    span = start_span(
      name: "LLM Call: #{provider}/#{model}",
      type: "llm_call",
      input: {
        provider: provider,
        model: model,
        messages: sanitize_messages(messages)
      },
      metadata: { provider: provider, model: model }
    )

    end_span(
      output: sanitize_response(response),
      tokens: tokens,
      cost: cost
    )

    span
  end

  # Record a tool execution
  #
  # @param tool_name [String] Tool name
  # @param input [Hash] Tool input
  # @param output [Hash] Tool output
  # @param duration_ms [Integer] Execution time
  def record_tool_execution(tool_name:, input:, output:, duration_ms: nil, error: nil)
    span = start_span(
      name: "Tool: #{tool_name}",
      type: "tool_execution",
      input: input,
      metadata: { tool_name: tool_name }
    )

    end_span(
      output: output,
      status: error ? :failed : :completed,
      error: error
    )

    span
  end

  # Record a retrieval operation
  #
  # @param source [String] Retrieval source (e.g., "vector_store", "database")
  # @param query [String] Search query
  # @param results [Array] Retrieved documents/chunks
  # @param relevance_scores [Array] Relevance scores
  def record_retrieval(source:, query:, results:, relevance_scores: nil)
    span = start_span(
      name: "Retrieval: #{source}",
      type: "retrieval",
      input: { source: source, query: query },
      metadata: { source: source, result_count: results&.size || 0 }
    )

    end_span(
      output: {
        results: results&.first(5), # Limit stored results
        total_results: results&.size || 0,
        relevance_scores: relevance_scores&.first(5)
      }
    )

    span
  end

  # Complete the trace
  #
  # @param status [Symbol] Final status (:completed, :failed, :cancelled)
  # @param error [String] Error message if failed
  # @param output [Hash] Final output data
  # @return [Hash] Complete trace data with all spans
  def complete_trace(status: :completed, error: nil, output: nil)
    return nil unless @current_trace

    # End any remaining spans
    while @span_stack.any?
      end_span(status: :cancelled)
    end

    # Update root span
    root_span = @spans[@current_trace[:root_span_id]]
    if root_span
      root_span[:completed_at] = Time.current
      root_span[:duration_ms] = ((root_span[:completed_at] - root_span[:started_at]) * 1000).round
      root_span[:status] = status.to_s
      root_span[:output] = output if output
      root_span[:error] = error if error
      persist_span(root_span)
    end

    # Update trace
    @current_trace[:status] = status.to_s
    @current_trace[:completed_at] = Time.current
    @current_trace[:error] = error if error
    @current_trace[:output] = output if output

    persist_trace(@current_trace)

    # Build complete trace response
    trace_response = build_trace_response

    # Export to OpenTelemetry if configured
    export_to_otel(trace_response)

    trace_response
  end

  # Get the current span ID
  #
  # @return [String] Current span ID or root span ID
  def current_span_id
    @span_stack.last || @current_trace&.dig(:root_span_id)
  end

  # Get trace data for visualization
  #
  # @param trace_id [String] Trace ID
  # @return [Hash] Complete trace with spans
  def self.get_trace(trace_id, account:)
    trace = Ai::ExecutionTrace.find_by(trace_id: trace_id, account_id: account.id)
    return nil unless trace

    spans = trace.execution_trace_spans.order(:started_at).map(&:as_json)

    {
      trace_id: trace.trace_id,
      name: trace.name,
      type: trace.trace_type,
      status: trace.status,
      started_at: trace.started_at,
      completed_at: trace.completed_at,
      duration_ms: trace.duration_ms,
      metadata: trace.metadata,
      error: trace.error,
      spans: spans,
      summary: build_summary(spans)
    }
  end

  # List recent traces
  #
  # @param account [Account] Account to list traces for
  # @param limit [Integer] Number of traces to return
  # @param type [String] Filter by trace type
  # @return [Array] Array of trace summaries
  def self.list_traces(account:, limit: 50, type: nil, status: nil)
    scope = Ai::ExecutionTrace.where(account_id: account.id)
    scope = scope.where(trace_type: type) if type.present?
    scope = scope.where(status: status) if status.present?

    scope.order(started_at: :desc).limit(limit).map do |trace|
      {
        trace_id: trace.trace_id,
        name: trace.name,
        type: trace.trace_type,
        status: trace.status,
        started_at: trace.started_at,
        completed_at: trace.completed_at,
        duration_ms: trace.duration_ms,
        span_count: trace.execution_trace_spans.count,
        total_tokens: trace.total_tokens,
        total_cost: trace.total_cost,
        error: trace.error.present?
      }
    end
  end

  private

  def generate_trace_id
    "trace_#{SecureRandom.uuid}"
  end

  def generate_span_id
    "span_#{SecureRandom.uuid}"
  end

  def create_span(span_id:, name:, type:, parent_span_id:, input: nil, metadata: {})
    span = {
      span_id: span_id,
      trace_id: @current_trace[:trace_id],
      name: name,
      type: type,
      parent_span_id: parent_span_id,
      status: "running",
      started_at: Time.current,
      completed_at: nil,
      duration_ms: nil,
      input: input,
      output: nil,
      error: nil,
      tokens: nil,
      cost: nil,
      events: [],
      metadata: metadata
    }

    @spans[span_id] = span
    span
  end

  def persist_trace(trace)
    return if Rails.env.test? # Skip persistence in tests unless configured

    Ai::ExecutionTrace.upsert(
      {
        trace_id: trace[:trace_id],
        account_id: account.id,
        name: trace[:name],
        trace_type: trace[:type],
        status: trace[:status],
        root_span_id: trace[:root_span_id],
        started_at: trace[:started_at],
        completed_at: trace[:completed_at],
        duration_ms: trace[:completed_at] ? ((trace[:completed_at] - trace[:started_at]) * 1000).round : nil,
        metadata: trace[:metadata],
        error: trace[:error],
        created_at: Time.current,
        updated_at: Time.current
      },
      unique_by: :trace_id
    )
  rescue StandardError => e
    Rails.logger.warn "[TracingService] Failed to persist trace: #{e.message}"
  end

  def persist_span(span)
    return if Rails.env.test?

    trace = Ai::ExecutionTrace.find_by(trace_id: span[:trace_id])
    return unless trace

    Ai::ExecutionTraceSpan.upsert(
      {
        span_id: span[:span_id],
        execution_trace_id: trace.id,
        name: span[:name],
        span_type: span[:type],
        parent_span_id: span[:parent_span_id],
        status: span[:status],
        started_at: span[:started_at],
        completed_at: span[:completed_at],
        duration_ms: span[:duration_ms],
        input_data: span[:input],
        output_data: span[:output],
        error: span[:error],
        tokens: span[:tokens],
        cost: span[:cost],
        events: span[:events],
        metadata: span[:metadata],
        created_at: Time.current,
        updated_at: Time.current
      },
      unique_by: :span_id
    )
  rescue StandardError => e
    Rails.logger.warn "[TracingService] Failed to persist span: #{e.message}"
  end

  def build_trace_response
    spans_list = @spans.values.sort_by { |s| s[:started_at] }

    {
      trace: @current_trace,
      spans: spans_list,
      summary: self.class.build_summary(spans_list)
    }
  end

  def self.build_summary(spans)
    return {} if spans.empty?

    llm_spans = spans.select { |s| s[:type] == "llm_call" || s["span_type"] == "llm_call" }
    tool_spans = spans.select { |s| s[:type] == "tool_execution" || s["span_type"] == "tool_execution" }

    total_tokens = spans.sum { |s| (s[:tokens] || s["tokens"])&.values&.sum || 0 }
    total_cost = spans.sum { |s| (s[:cost] || s["cost"]) || 0 }

    {
      total_spans: spans.size,
      llm_calls: llm_spans.size,
      tool_executions: tool_spans.size,
      total_tokens: total_tokens,
      total_cost: total_cost.round(6),
      failed_spans: spans.count { |s| (s[:status] || s["status"]) == "failed" }
    }
  end

  def sanitize_messages(messages)
    # Limit message size to prevent huge traces
    messages&.map do |msg|
      content = msg[:content] || msg["content"]
      {
        role: msg[:role] || msg["role"],
        content: content&.length.to_i > 2000 ? "#{content[0..2000]}... [truncated]" : content
      }
    end
  end

  def sanitize_response(response)
    # Limit response size
    return response unless response.is_a?(Hash)

    response.transform_values do |v|
      if v.is_a?(String) && v.length > 5000
        "#{v[0..5000]}... [truncated]"
      else
        v
      end
    end
  end

  def export_to_otel(trace_response)
    return unless ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?

    Thread.new do
      Ai::Observability::OtelExporter.new(account: account).export_trace(trace_response)
    rescue StandardError => e
      Rails.logger.warn "[TracingService] OTel export failed: #{e.message}"
    end
  end
end
