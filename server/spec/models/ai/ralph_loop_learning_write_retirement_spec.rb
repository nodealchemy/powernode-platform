# frozen_string_literal: true

require "rails_helper"

# ============================================================================
# IMP-7f415874c14a — RETIRE THE WRITE to the loop-level `learnings` jsonb array.
#
# IMP-44964469b565 moved the RECENCY read off the array. The write stayed: every
# completion did an O(n) read-modify-write of the whole column under the loop row
# lock (548 kB / 354 entries in production; ~1.5 GB of cumulative write traffic at
# the loop's 1000-iteration ceiling, contending with #increment_iteration!).
#
# This spec is deliberately BROADER than "the array stopped growing" — that
# assertion alone passes against a change that also broke every reader. Each
# re-derived reader is pinned to its CONTENT here, the API group-by-iteration
# SHAPE included (the one a naive re-derivation loses).
#
# The column is NOT dropped: it stays, dormant and empty, so this whole change is
# a single revertible range with no migration on a live install.
# ============================================================================
RSpec.describe "ralph-loop learning write retirement", type: :model do
  let(:account) { create(:account) }
  let(:record) { create(:ai_ralph_loop, account: account, current_iteration: 0) }

  # Drive the real production path: ExecutionService and the dev-loop bridge both
  # reach the array through RalphIteration#complete!.
  def complete_iteration!(number, text, task: nil)
    iteration = create(:ai_ralph_iteration, :running, ralph_loop: record,
                       ralph_task: task, iteration_number: number)
    iteration.complete!(output: "did the work", learning: text)
    iteration
  end

  describe "the write is gone" do
    it "records the learning on the iteration row and leaves the array empty" do
      complete_iteration!(1, "Webhook receivers must return 202, never 500")

      expect(record.ralph_iterations.find_by(iteration_number: 1).learning_extracted)
        .to eq("Webhook receivers must return 202, never 500")
      expect(record.reload.learnings).to eq([])
    end

    it "does not grow the array across successive completions" do
      complete_iteration!(1, "first")
      complete_iteration!(2, "second")
      complete_iteration!(3, "third")

      expect(record.reload.learnings).to eq([])
    end

    # The array rewrite took the SAME row lock #increment_iteration! takes, so the
    # per-completion contention is what this increment actually removes.
    it "no longer takes the loop row lock to record a learning" do
      expect(record).not_to receive(:with_lock)
      record.add_learning("no lock needed", context: { iteration: 1 })
    end

    # #add_learning is a public model API. It must not become a silent no-op for a
    # caller that has not already written the row — it back-fills the surviving
    # channel instead. Never CLOBBERS: an iteration that already carries a learning
    # keeps it (the column holds one; the array used to hold many).
    it "back-fills a blank iteration row rather than silently dropping the learning" do
      iteration = create(:ai_ralph_iteration, :running, ralph_loop: record, iteration_number: 4)

      record.add_learning("recorded via the public API", context: { iteration: 4 })

      expect(iteration.reload.learning_extracted).to eq("recorded via the public API")
      expect(record.reload.learnings).to eq([])
    end

    it "never overwrites a learning the iteration row already carries" do
      iteration = create(:ai_ralph_iteration, :running, ralph_loop: record,
                         iteration_number: 4, learning_extracted: "the original")

      record.add_learning("a second learning for the same iteration", context: { iteration: 4 })

      expect(iteration.reload.learning_extracted).to eq("the original")
    end

    it "still scrubs secrets at the back-fill boundary (G15)" do
      create(:ai_ralph_iteration, :running, ralph_loop: record, iteration_number: 4)

      record.add_learning('Set api_key=sk-supersecretvalue123 in the env', context: { iteration: 4 })

      text = record.ralph_iterations.find_by(iteration_number: 4).learning_extracted
      expect(text).not_to include("sk-supersecretvalue123")
      expect(text).to match(/\[REDACTED/)
    end
  end

  # ==========================================================================
  # EVERY reader re-derived. A reader left on the raw column goes PERMANENTLY
  # EMPTY for new data, silently — no error, no failing shape assertion.
  # ==========================================================================
  describe "re-derived readers" do
    let(:task) { create(:ai_ralph_task, ralph_loop: record, task_key: "IMP-shape") }

    before do
      complete_iteration!(1, "oldest", task: task)
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 2, learning_extracted: nil)
      complete_iteration!(3, "newest", task: task)
    end

    it "#learning_entries returns every learning, oldest first, in the array's entry shape" do
      entries = record.learning_entries

      expect(entries.map { |e| e["text"] }).to eq(%w[oldest newest])
      expect(entries.first["iteration"]).to eq(1)
      expect(entries.first["timestamp"]).to be_present
      expect(entries.first["context"]).to eq({ "iteration" => 1, "task_key" => "IMP-shape" })
      expect(entries.first.keys).to match_array(%w[text iteration timestamp context])
    end

    it "#recent_learnings (the recency channel) still returns the right content" do
      expect(record.recent_learnings.map { |l| l["text"] }).to eq(%w[oldest newest])
    end

    it "#loop_details still carries the learnings (API show)" do
      expect(record.loop_details[:learnings].map { |l| l["text"] }).to eq(%w[oldest newest])
    end

    describe "Ai::Ralph::ExecutionService#learnings (API learnings endpoint)" do
      subject(:payload) do
        Ai::Ralph::ExecutionService.new(ralph_loop: record, account: account).learnings
      end

      it "returns the learnings and a matching total_count" do
        expect(payload[:learnings].map { |l| l["text"] }).to eq(%w[oldest newest])
        expect(payload[:total_count]).to eq(2)
      end

      # THE SHAPE A NAIVE RE-DERIVATION LOSES: by_iteration is a Hash keyed by the
      # producing iteration's number, values being that iteration's entries.
      it "keeps the group-by-iteration shape, keyed by the producing iteration" do
        by_iteration = payload[:by_iteration]

        expect(by_iteration).to be_a(Hash)
        expect(by_iteration.keys).to match_array([ 1, 3 ])
        expect(by_iteration[1].map { |l| l["text"] }).to eq([ "oldest" ])
        expect(by_iteration[3].map { |l| l["text"] }).to eq([ "newest" ])
      end
    end

    # SOURCE ORACLE: a populated legacy array must not be able to satisfy any of
    # the above. Clearing the rows empties every reader even though the array is
    # full — which is what pins the source to ai_ralph_iterations.
    it "goes empty everywhere when the rows are cleared, a full legacy array notwithstanding" do
      record.update!(learnings: [
        { "text" => "legacy array entry", "iteration" => 1, "timestamp" => Time.current.iso8601,
          "context" => { "iteration" => 1 } }
      ])
      record.ralph_iterations.update_all(learning_extracted: nil)
      record.reload

      expect(record.learnings).to be_present
      expect(record.learning_entries).to eq([])
      expect(record.recent_learnings).to eq([])
      expect(record.loop_details[:learnings]).to eq([])
      payload = Ai::Ralph::ExecutionService.new(ralph_loop: record, account: account).learnings
      expect(payload[:learnings]).to eq([])
      expect(payload[:total_count]).to eq(0)
      expect(payload[:by_iteration]).to eq({})
    end
  end

  # ==========================================================================
  # #reset! — iteration 498 added #preserve_iteration_learnings! because reset!'s
  # delete_all destroys the per-iteration record. That concern is UNCHANGED; only
  # its destination moved. Back-filling the array would now be writing to a column
  # nothing reads, so the preservation moves onto the CompoundLearning store —
  # the channel that IS read (re-injected as `relevant_learnings`).
  # ==========================================================================
  describe "#reset! preservation" do
    let(:record) { create(:ai_ralph_loop, :failed, account: account, current_iteration: 4) }

    before do
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 1,
             learning_extracted: "Webhook receivers must return 202, never 500")
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 2, learning_extracted: nil)
    end

    # The harvest must see the rows, so it has to run while they still exist —
    # i.e. BEFORE delete_all. Harvesting afterwards reads nothing and quietly
    # harvests nothing, which is the exact failure mode that would silently undo
    # iteration 498's fix.
    it "harvests the doomed rows' learnings into the durable store" do
      harvested = nil
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract) { |_x, _loop, entries: nil| harvested = Array(entries).map { |e| e["text"] } }

      record.reset!

      expect(harvested).to eq([ "Webhook receivers must return 202, never 500" ])
    end

    it "still destroys the iteration rows and leaves the dormant array empty" do
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor).to receive(:extract).and_return(1)

      record.reset!
      record.reload

      expect(record.ralph_iterations.count).to eq(0)
      expect(Ai::RalphIteration.where(ralph_loop_id: record.id).count).to eq(0)
      expect(record.learnings).to eq([])
    end

    # #extract_compound_learnings RESCUES StandardError. Under
    # #preserve_iteration_learnings! a swallowed failure was harmless — the entries
    # had already been committed to the jsonb array. With that gone, deleting
    # regardless would put the learnings in NO durable store, silently and
    # permanently. Embedding calls are exactly what fails here.
    it "KEEPS the iteration rows when the harvest fails, rather than destroying the only copy" do
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract).and_raise(StandardError, "embedding provider unreachable")

      expect { record.reset! }.not_to raise_error
      record.reload

      expect(record.status).to eq("pending")
      expect(record.ralph_iterations.pluck(:learning_extracted))
        .to include("Webhook receivers must return 202, never 500")
    end

    # A zeroed counter against retained rows hands the next claim the surviving,
    # already-completed iteration 1 — #complete! then raises and the loop cannot
    # run. Keeping the counter is what makes the degraded path still usable.
    it "keeps current_iteration when it keeps the rows, so the next claim gets a fresh one" do
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract).and_raise(StandardError, "embedding provider unreachable")

      record.reset!
      record.reload

      expect(record.current_iteration).to eq(4)
      expect(record.create_iteration.iteration_number).to eq(5)
    end

    it "reports whether the reset was able to make the learnings durable" do
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract).and_raise(StandardError, "boom")

      expect(record.reset!).to be false
    end

    # A loop reset BEFORE this change carries array entries whose iteration rows
    # are already gone. Deriving from the rows alone would strand them forever.
    it "harvests a legacy array entry whose iteration row no longer exists" do
      record.ralph_iterations.delete_all
      record.update!(learnings: [
        { "text" => "A learning stranded by an earlier reset", "iteration" => 1,
          "timestamp" => Time.current.iso8601, "context" => { "iteration" => 1 } }
      ])
      harvested = nil
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract) { |_x, _loop, entries: nil| harvested = Array(entries).map { |e| e["text"] } }

      record.reset!

      expect(harvested).to eq([ "A learning stranded by an earlier reset" ])
    end

    it "does not harvest a legacy entry twice when its iteration row still carries it" do
      record.update!(learnings: [
        { "text" => "Webhook receivers must return 202, never 500", "iteration" => 0,
          "timestamp" => Time.current.iso8601, "context" => {} }
      ])
      harvested = nil
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract) { |_x, _loop, entries: nil| harvested = Array(entries).map { |e| e["text"] } }

      record.reset!

      expect(harvested).to eq([ "Webhook receivers must return 202, never 500" ])
    end

    it "no longer back-fills the dead column" do
      expect(record).not_to respond_to(:preserve_iteration_learnings!)
    end
  end

  # ==========================================================================
  # THE DEV-LOOP BRIDGE, END TO END. DevLoopTool never calls
  # #increment_iteration!, so it looks as though every claim in a run would reuse
  # one iteration row and each learning would clobber the last — which, with the
  # array gone, would collapse a whole run to its final learning. It does not:
  # RalphIteration's `after_save :update_loop_progress, if: :saved_change_to_status?`
  # (ralph_iteration.rb:37) advances current_iteration on every status change, so
  # #create_iteration's `current_iteration + 1` yields a fresh row per claim.
  # That producer is invisible to a grep for #increment_iteration!, so this pins
  # the behaviour by EXECUTION rather than by reading.
  # ==========================================================================
  describe "two dev-loop completions in one run" do
    let(:user) { create(:user, account: account) }
    let(:tool) { Ai::Tools::DevLoopTool.new(account: account, user: user) }
    let(:record) { create(:ai_ralph_loop, :running, account: account, started_at: Time.current) }

    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
      create(:ai_ralph_task, ralph_loop: record, task_key: "W1-01", position: 1)
      create(:ai_ralph_task, ralph_loop: record, task_key: "W1-02", position: 2)
    end

    def claim_and_fail!(task_key, learning)
      tool.execute(params: { action: "dev_next_task", loop_id: record.id })
      tool.execute(params: {
        action: "dev_complete_task", loop_id: record.id, task_key: task_key,
        outcome: "failed", summary: "reported", learning: learning
      })
    end

    it "keeps BOTH learnings — each claim lands on its own iteration row" do
      claim_and_fail!("W1-01", "the first run learning")
      claim_and_fail!("W1-02", "the second run learning")

      expect(record.reload.learning_entries.map { |l| l["text"] })
        .to eq([ "the first run learning", "the second run learning" ])
      expect(record.recent_learnings.map { |l| l["text"] })
        .to eq([ "the first run learning", "the second run learning" ])
      expect(record.learnings).to eq([])
    end
  end

  # ==========================================================================
  # #complete! harvests from the same derived channel. Left on the raw array this
  # reader goes empty and the durable CompoundLearning store — the one channel
  # that survives both reset! and the array's retirement — stops being fed.
  # ==========================================================================
  describe "#complete! harvest" do
    let(:record) { create(:ai_ralph_loop, :running, account: account, current_iteration: 1) }

    it "harvests the iteration rows' learnings" do
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 1,
             learning_extracted: "Eager-load before iterating an association")
      harvested = nil
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract) { |_x, _loop, entries: nil| harvested = Array(entries).map { |e| e["text"] } }

      record.complete!

      expect(harvested).to eq([ "Eager-load before iterating an association" ])
    end

    it "does not invoke the extractor when no iteration carries a learning" do
      create(:ai_ralph_iteration, ralph_loop: record, iteration_number: 1, learning_extracted: nil)
      expect(Ai::Learning::RalphLearningExtractor).not_to receive(:new)

      record.complete!
    end
  end

  # The column stays. Dropping it would be a migration on a live install and buys
  # nothing; leaving it dormant keeps the revert a single contiguous range.
  it "keeps the learnings column, dormant and defaulting to []" do
    expect(Ai::RalphLoop.column_names).to include("learnings")
    expect(create(:ai_ralph_loop, account: account).learnings).to eq([])
  end
end
