# frozen_string_literal: true

require "rails_helper"

# IMP-077c2471b85a / operator ruling 2026-09-13 (b), D4 (split into two
# releases): this release stops READING and WRITING the dormant
# `ai_ralph_loops.learnings` column. The column ITSELF is deliberately left in
# place — dropping it is a separate follow-up, gated on a clean
# `bin/rails ai:drain_dormant_ralph_learnings` run against the live column, and
# is out of scope here (a refusing migration cannot ship in the same release as
# its own remedy: rails-start.sh runs db:migrate under `set -e` before exec
# puma, and a boot-time refusal would leave the backend unable to start).
#
#   - StateMachine#harvestable_learning_entries (the "legacy union") — gone;
#     #extract_compound_learnings reads only #learning_entries.
#   - RalphLoop#set_defaults' `self.learnings ||= []` — gone (the column's own
#     DB-level `default: []` still applies on insert, so this is a no-op removal).
#   - StorageMetrics' `learnings_column_bytes` term — gone (EMPTY_METRICS,
#     METRICS_SQL, storage_metrics_rows, #storage_total_bytes).
#   - RalphLoopTool#get_statistics' `learnings_column_bytes` term — gone (the
#     4th reader, missed by the original finding — see spec/services/ai/tools/
#     ralph_loop_tool_spec.rb).
#   - The column remains in schema.rb, dormant: nothing in this checkout reads
#     or writes it anymore, but `bin/rails ai:drain_dormant_ralph_learnings`
#     still needs it present to have something to drain.
RSpec.describe "ralph-loop dormant learnings column — readers retired, column NOT dropped", type: :model do
  let(:account) { create(:account) }
  let(:record) { create(:ai_ralph_loop, account: account, current_iteration: 0) }

  it "no longer exposes #harvestable_learning_entries — extraction reads only the derived entries" do
    expect(record).not_to respond_to(:harvestable_learning_entries)
  end

  it "still carries the column — dropping it is a separate, deferred follow-up" do
    expect(Ai::RalphLoop.column_names).to include("learnings")
  end

  it "no longer sets a Ruby-side default for it (the DB-level default still applies)" do
    expect(record.learnings).to eq([])
  end

  it "reports storage metrics with no learnings_column_bytes term" do
    expect(record.storage_metrics).not_to have_key(:learnings_column_bytes)
    expect(Ai::RalphLoopConcerns::StorageMetrics::EMPTY_METRICS).not_to have_key(:learnings_column_bytes)
  end

  it "does not fold a learnings byte count into #storage_total_bytes" do
    # Regression guard on the ARITHMETIC, not just the hash key: a term that
    # silently stayed in the SUM while vanishing from the reported hash would
    # still pass the key-absence check above.
    create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 1,
           status: "completed", ai_output: "x" * 4000)

    metrics = record.storage_metrics
    expect(record.storage_total_bytes).to eq(metrics[:ai_output_bytes] + metrics[:ai_prompt_bytes])
  end
end
