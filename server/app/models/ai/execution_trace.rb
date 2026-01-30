# frozen_string_literal: true

# Ai::ExecutionTrace - Stores trace data for AI operations
#
# Provides persistence for LangSmith-style execution tracing.
# Each trace contains multiple spans representing steps in the execution.
#
# == Schema Information
#
# Table name: ai_execution_traces
#
#  id            :uuid             not null, primary key
#  trace_id      :string           not null, unique
#  account_id    :uuid             not null
#  name          :string           not null
#  trace_type    :string           not null
#  status        :string           default("running")
#  root_span_id  :string
#  started_at    :datetime
#  completed_at  :datetime
#  duration_ms   :integer
#  total_tokens  :integer          default(0)
#  total_cost    :decimal(10,6)    default(0.0)
#  metadata      :jsonb            default({})
#  error         :text
#  output        :jsonb
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class Ai::ExecutionTrace < ApplicationRecord
  self.table_name = "ai_execution_traces"

  # Associations
  belongs_to :account
  has_many :execution_trace_spans,
           class_name: "Ai::ExecutionTraceSpan",
           dependent: :destroy

  # Validations
  validates :trace_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :trace_type, presence: true,
            inclusion: { in: %w[agent workflow conversation tool mcp batch] }
  validates :status, presence: true,
            inclusion: { in: %w[pending running completed failed cancelled] }

  # Scopes
  scope :recent, -> { order(started_at: :desc) }
  scope :running, -> { where(status: "running") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :by_type, ->(type) { where(trace_type: type) }
  scope :with_errors, -> { where.not(error: nil) }

  # Callbacks
  after_save :update_aggregated_metrics

  # Calculate total duration
  def duration_seconds
    return nil unless duration_ms

    duration_ms / 1000.0
  end

  # Calculate success rate for spans
  def success_rate
    return 0 if execution_trace_spans.empty?

    completed = execution_trace_spans.where(status: "completed").count
    (completed.to_f / execution_trace_spans.count * 100).round(2)
  end

  # Get spans organized as a tree structure
  def span_tree
    spans = execution_trace_spans.order(:started_at)
    build_span_tree(spans, root_span_id)
  end

  # Get timeline data for visualization
  def timeline
    spans = execution_trace_spans.order(:started_at)
    spans.map do |span|
      {
        id: span.span_id,
        name: span.name,
        type: span.span_type,
        status: span.status,
        start_offset_ms: span.started_at ? ((span.started_at - started_at) * 1000).round : 0,
        duration_ms: span.duration_ms || 0,
        parent_id: span.parent_span_id,
        has_error: span.error.present?
      }
    end
  end

  # Mark trace as completed
  def complete!(status: "completed", error: nil)
    update!(
      status: status,
      completed_at: Time.current,
      duration_ms: ((Time.current - started_at) * 1000).round,
      error: error
    )
  end

  private

  def build_span_tree(spans, parent_id)
    spans.select { |s| s.parent_span_id == parent_id }.map do |span|
      {
        span: span.as_json,
        children: build_span_tree(spans, span.span_id)
      }
    end
  end

  def update_aggregated_metrics
    return unless saved_change_to_status? || saved_change_to_completed_at?

    # Calculate totals from spans
    totals = execution_trace_spans.pluck(:tokens, :cost).reduce(
      { tokens: 0, cost: 0.0 }
    ) do |acc, (tokens, cost)|
      acc[:tokens] += tokens&.values&.sum || 0 if tokens.is_a?(Hash)
      acc[:cost] += cost || 0
      acc
    end

    update_columns(
      total_tokens: totals[:tokens],
      total_cost: totals[:cost]
    )
  end
end
