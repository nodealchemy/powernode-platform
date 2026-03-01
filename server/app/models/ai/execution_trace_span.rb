# frozen_string_literal: true

# Ai::ExecutionTraceSpan - Individual span within an execution trace
#
# Represents a single operation or step within a larger trace.
# Spans can be nested to show parent-child relationships.
#
# == Schema Information
#
# Table name: ai_execution_trace_spans
#
#  id                 :uuid             not null, primary key
#  span_id            :string           not null, unique
#  execution_trace_id :uuid             not null
#  name               :string           not null
#  span_type          :string           not null
#  parent_span_id     :string
#  status             :string           default("running")
#  started_at         :datetime
#  completed_at       :datetime
#  duration_ms        :integer
#  input_data         :jsonb
#  output_data        :jsonb
#  error              :text
#  tokens             :jsonb            default({})
#  cost               :decimal(10,6)    default(0.0)
#  events             :jsonb            default([])
#  metadata           :jsonb            default({})
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class Ai::ExecutionTraceSpan < ApplicationRecord
  self.table_name = "ai_execution_trace_spans"

  # Associations
  belongs_to :execution_trace,
             class_name: "Ai::ExecutionTrace"
  belongs_to :parent_span,
             class_name: "Ai::ExecutionTraceSpan",
             foreign_key: :parent_span_id,
             primary_key: :span_id,
             optional: true
  has_many :child_spans,
           class_name: "Ai::ExecutionTraceSpan",
           foreign_key: :parent_span_id,
           primary_key: :span_id

  # Validations
  validates :span_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :span_type, presence: true,
            inclusion: { in: %w[root llm_call tool_execution retrieval generic agent workflow mcp reasoning reflection planning evaluation] }
  validates :status, presence: true,
            inclusion: { in: %w[pending running completed failed cancelled] }

  # Scopes
  scope :by_type, ->(type) { where(span_type: type) }
  scope :with_errors, -> { where.not(error: nil) }
  scope :root_spans, -> { where(parent_span_id: nil) }
  scope :llm_calls, -> { where(span_type: "llm_call") }
  scope :tool_executions, -> { where(span_type: "tool_execution") }
  scope :reasoning_spans, -> { where(span_type: "reasoning") }
  scope :reflection_spans, -> { where(span_type: "reflection") }
  scope :planning_spans, -> { where(span_type: "planning") }
  scope :evaluation_spans, -> { where(span_type: "evaluation") }

  # Delegation
  delegate :account, to: :execution_trace

  # Token counts
  def prompt_tokens
    tokens&.dig("prompt") || tokens&.dig(:prompt) || 0
  end

  def completion_tokens
    tokens&.dig("completion") || tokens&.dig(:completion) || 0
  end

  def total_tokens
    prompt_tokens + completion_tokens
  end

  # Duration in seconds
  def duration_seconds
    return nil unless duration_ms

    duration_ms / 1000.0
  end

  # Check if span has children
  def has_children?
    child_spans.exists?
  end

  # Get depth in span tree
  def depth
    depth = 0
    current = self
    while current.parent_span.present?
      depth += 1
      current = current.parent_span
    end
    depth
  end

  # Mark span as completed
  def complete!(output: nil, error: nil)
    update!(
      status: error.present? ? "failed" : "completed",
      completed_at: Time.current,
      duration_ms: started_at ? ((Time.current - started_at) * 1000).round : 0,
      output_data: output,
      error: error
    )
  end

  # Add an event to the span
  def add_event(name:, data: {})
    current_events = events || []
    current_events << {
      name: name,
      data: data,
      timestamp: Time.current.iso8601
    }
    update!(events: current_events)
  end

  # Serialize for API response
  def as_json(options = {})
    {
      id: id,
      span_id: span_id,
      name: name,
      type: span_type,
      parent_span_id: parent_span_id,
      status: status,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      duration_ms: duration_ms,
      input: input_data,
      output: output_data,
      error: error,
      tokens: {
        prompt: prompt_tokens,
        completion: completion_tokens,
        total: total_tokens
      },
      cost: cost,
      events: events,
      metadata: metadata,
      depth: depth
    }
  end
end
