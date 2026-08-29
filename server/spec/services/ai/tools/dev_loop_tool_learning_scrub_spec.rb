# frozen_string_literal: true

require "rails_helper"

# IMP-9d49b9833a67: a dev-loop learning fans out to THREE sinks, and only one of
# them was scrubbed.
#
#   1. ralph_loops.learnings (jsonb)      -- scrubbed in RalphLoop#add_learning
#   2. ai_ralph_iterations.learning_extracted -- RAW (durable, iteration-keyed)
#   3. Ai::CompoundLearning (compound store)  -- RAW (embedded, and re-served as
#      `context.relevant_learnings` into EVERY later dev_next_task, INCLUDING
#      other loops -- the store is cross-loop by design)
#
# Sink 1 is a denormalised cache of which only the last 5 entries are ever read.
# Sinks 2 and 3 are the durable, redistributed ones -- so a spec that asserts
# only sink 1 passes against the defective code and measures nothing. Every
# example below asserts the STORED ROW of all three sinks.
#
# The "passed" outcome is the leakiest path: it does NOT go through
# #capture_learning at all, so a scrub placed there alone would still leak sink 3.
RSpec.describe Ai::Tools::DevLoopTool, "learning secret scrubbing" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "scrub-test-loop") }
  let!(:task) { create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "S1-01") }

  # SYNTHETIC only. Deliberately low-entropy and self-describing so it can never
  # be mistaken for -- or mined as -- a real credential. The marker is asserted
  # via String#include? so a failure renders a bare boolean, never the text.
  #
  # These are `let`s, not constants: a constant assigned inside a block is defined
  # on Object, not on the example group, which is the duplicate-constant-clobber
  # shape that produces order-dependent flakes across the suite.
  let(:secret_marker) { "xxxxSYNTHETICxxxxNOTAREALKEYxxxx" }
  let(:leaky_learning) { "The importer authenticates with api_key: #{secret_marker} and then retries." }
  let(:benign_learning) do
    "Eager-load associations with .includes() before iterating; a bare .all then .map is an N+1."
  end

  before do
    # Force the keyword/text-dedup fallback so these examples aren't coupled to
    # embedding infrastructure (mirrors dev_loop_tool_spec.rb).
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
    ralph_loop.update!(status: "running", started_at: Time.current)
    tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
  end

  def complete(outcome:, learning:, summary: "work reported")
    tool.execute(params: {
      action: "dev_complete_task",
      loop_id: ralph_loop.id,
      task_key: "S1-01",
      outcome: outcome,
      summary: summary,
      learning: learning
    })
  end

  # --- Sink readers. Each returns a STRING read back from the database. ---

  def sink1_loop_learnings_array
    ralph_loop.reload.learnings.to_s
  end

  def sink2_iteration_learning_extracted
    Ai::RalphIteration.where(ralph_loop_id: ralph_loop.id).pluck(:learning_extracted).join("\n")
  end

  def sink3_compound_store
    Ai::CompoundLearning.where(account_id: account.id, extraction_method: "ralph_loop")
                        .pluck(:content, :title).flatten.compact.join("\n")
  end

  def all_sinks
    { "sink1 loop.learnings" => sink1_loop_learnings_array,
      "sink2 iteration.learning_extracted" => sink2_iteration_learning_extracted,
      "sink3 compound store" => sink3_compound_store }
  end

  # "skipped" is deliberately absent: transition_allowed? maps it to
  # RalphTask#can_skip?, which is false for the in_progress task a dev_next_task
  # claim produces, so record_outcome's skipped branch is unreachable through this
  # entry point and an example for it would assert on three empty sinks (a vacuous
  # green). It shares #capture_learning with failed/blocked and sits below the same
  # single scrub, so it is covered by construction rather than by example.
  %w[passed failed blocked].each do |outcome|
    context "on a #{outcome} outcome" do
      it "does not persist the synthetic secret in ANY of the three sinks" do
        complete(outcome: outcome, learning: leaky_learning)

        all_sinks.each do |name, stored|
          # Reduce to a boolean: a failure must never render the secret.
          expect("#{name} leaked the secret: #{stored.include?(secret_marker)}")
            .to eq("#{name} leaked the secret: false")
        end
      end

      it "still persists the surrounding learning text, redacted rather than dropped" do
        complete(outcome: outcome, learning: leaky_learning)

        all_sinks.each do |name, stored|
          expect("#{name} kept context: #{stored.include?('The importer authenticates')}")
            .to eq("#{name} kept context: true")
          expect("#{name} redacted: #{stored.include?('[REDACTED]')}")
            .to eq("#{name} redacted: true")
        end
      end

      # Over-redaction guard. An absence-only oracle is satisfied by a change that
      # scrubs EVERYTHING, which would destroy the learning corpus -- the exact trap
      # the Auditable redaction work (36951df81) had to avoid.
      it "leaves benign learning text byte-for-byte intact in all three sinks" do
        complete(outcome: outcome, learning: benign_learning)

        all_sinks.each do |name, stored|
          expect("#{name} verbatim: #{stored.include?(benign_learning)}")
            .to eq("#{name} verbatim: true")
          expect("#{name} over-redacted: #{stored.include?('[REDACTED')}")
            .to eq("#{name} over-redacted: false")
        end
      end
    end
  end

  # The model-level seam, exercised directly: RalphIteration#complete! is a public
  # API and iteration_execution.rb is a second caller. The durable column must be
  # scrubbed at the WRITE, not by each caller remembering to.
  describe "Ai::RalphIteration#complete!" do
    it "scrubs learning_extracted even when a caller hands it raw text" do
      iteration = create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop)

      iteration.complete!(output: "done", checks_passed: true, learning: leaky_learning)

      stored = Ai::RalphIteration.where(id: iteration.id).pick(:learning_extracted).to_s
      expect("leaked: #{stored.include?(secret_marker)}").to eq("leaked: false")
      expect("redacted: #{stored.include?('[REDACTED]')}").to eq("redacted: true")
    end

    it "leaves benign learning text intact" do
      iteration = create(:ai_ralph_iteration, :running, ralph_loop: ralph_loop)

      iteration.complete!(output: "done", checks_passed: true, learning: benign_learning)

      stored = Ai::RalphIteration.where(id: iteration.id).pick(:learning_extracted).to_s
      expect("verbatim: #{stored.include?(benign_learning)}").to eq("verbatim: true")
    end
  end
end
