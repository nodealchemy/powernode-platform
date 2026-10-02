# frozen_string_literal: true

require "rails_helper"

# IMP-36483b880322 (follow-up to IMP-3e36e30d5c72, which widened nine columns).
# These four columns are written with the same `((now - started_at) * 1000)`
# millisecond span into a Postgres int4, so any execution older than
# ~24.855 days (2_147_483_647 ms) raises ActiveModel::RangeError when it
# completes. It fails at runtime, not at boot.
RSpec.describe "duration_ms columns hold spans past the int4 ceiling" do
  let(:over_int4) { 3_000_000_000 } # ~34.7 days in ms

  {
    "ai_dag_executions" => "Ai::DagExecution",
    "ai_execution_traces" => "Ai::ExecutionTrace",
    "ai_agent_executions" => "Ai::AgentExecution",
    "ai_execution_trace_spans" => "Ai::ExecutionTraceSpan"
  }.each do |table, klass|
    it "#{table}.duration_ms is bigint" do
      column = klass.constantize.columns_hash.fetch("duration_ms")

      expect(column.sql_type).to eq("bigint")
    end
  end

  it "persists and reloads 3,000,000,000 ms on an Ai::DagExecution" do
    record = create(:ai_dag_execution)

    record.update!(duration_ms: over_int4)

    expect(record.reload.duration_ms).to eq(over_int4)
  end

  it "persists and reloads 3,000,000,000 ms on an Ai::AgentExecution" do
    record = create(:ai_agent_execution)

    record.update!(duration_ms: over_int4)

    expect(record.reload.duration_ms).to eq(over_int4)
  end

  it "completes an Ai::ExecutionTrace that started 40 days ago without overflowing" do
    trace = create(:ai_execution_trace, started_at: 40.days.ago)

    trace.complete!

    expect(trace.reload.duration_ms).to be > 2_147_483_647
  end

  it "completes an Ai::ExecutionTraceSpan that started 40 days ago without overflowing" do
    span = create(:ai_execution_trace_span, started_at: 40.days.ago)

    span.complete!

    expect(span.reload.duration_ms).to be > 2_147_483_647
  end
end
