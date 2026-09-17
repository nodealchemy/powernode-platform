# frozen_string_literal: true

require "rails_helper"

# server/lib/tasks/ralph_learnings_drain.rake — IMP-077c2471b85a / operator
# ruling 2026-09-13 (b). ai_ralph_loops.learnings is already dropped in this
# checkout, so every example re-adds it (raw SQL) inside the transactional-
# fixture wrapper — nothing persists past the example.
RSpec.describe "ai:drain_dormant_ralph_learnings" do
  let!(:account) { create(:account) }
  let(:connection) { ActiveRecord::Base.connection }

  def run_task
    previous_application = Rake.application
    begin
      Rake.application = Rake::Application.new
      Rake.application.rake_require("tasks/ralph_learnings_drain", [ Rails.root.join("lib").to_s ], [])
      Rake::Task.define_task(:environment)
      silence_stream { Rake::Task["ai:drain_dormant_ralph_learnings"].invoke }
    ensure
      Rake.application = previous_application
    end
  end

  def silence_stream
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  def readd_column!
    connection.add_column(:ai_ralph_loops, :learnings, :jsonb, default: []) unless
      connection.column_exists?(:ai_ralph_loops, :learnings)
  end

  def raw_set_learnings(loop_id, value)
    connection.execute(
      "UPDATE ai_ralph_loops SET learnings = #{connection.quote(value.to_json)}::jsonb WHERE id = #{connection.quote(loop_id)}"
    )
  end

  def raw_learnings(loop_id)
    connection.select_value(
      "SELECT learnings FROM ai_ralph_loops WHERE id = #{connection.quote(loop_id)}"
    )
  end

  before { allow(Rails.logger).to receive(:info) }

  context "when a loop carries a leftover legacy entry" do
    it "harvests it into CompoundLearning and empties the column" do
      readd_column!
      loop_record = create(:ai_ralph_loop, account: account)
      raw_set_learnings(loop_record.id, [
        { "text" => "Webhook receivers must return 202, never 500", "iteration" => 1 }
      ])
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))

      expect { run_task }.to change {
        Ai::CompoundLearning.where(account: account, extraction_method: "ralph_loop").count
      }.by(1)

      expect(raw_learnings(loop_record.id)).to eq("[]")
    end

    it "is idempotent — a second run has nothing left to drain" do
      readd_column!
      loop_record = create(:ai_ralph_loop, account: account)
      raw_set_learnings(loop_record.id, [ { "text" => "first pass entry", "iteration" => 1 } ])
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))

      run_task
      expect { run_task }.not_to(change { Ai::CompoundLearning.where(account: account).count })
    end
  end

  # D3 (review 2026-09-17): a non-empty row that fails the entry filter is NOT
  # evidence there is nothing worth keeping — it is a shape this task does not
  # recognize (a bare jsonb object, a JSON string, an array keyed
  # "learning"/"content" from an older writer). The only copy of unknown
  # content must never be discarded because it doesn't parse the way this
  # task expects.
  context "when a row is non-empty but carries an unrecognized entry shape" do
    it "leaves the column intact, invokes no extractor, and counts the loop as skipped" do
      readd_column!
      loop_record = create(:ai_ralph_loop, account: account)
      raw_set_learnings(loop_record.id, [ { "iteration" => 1 } ]) # no "text" key
      expect(Ai::Learning::RalphLearningExtractor).not_to receive(:new)
      allow(Rails.logger).to receive(:error)

      error = nil
      begin
        run_task
      rescue SystemExit => e
        error = e
      end

      # Incomplete (a loop was skipped) is reported loudly, not as a quiet success.
      expect(error).not_to be_nil
      expect(error.status).not_to eq(0)
      expect(JSON.parse(raw_learnings(loop_record.id))).to eq([ { "iteration" => 1 } ])
    end
  end

  # D1 (review 2026-09-17): Ai::Learning::RalphLearningExtractor#extract sums a
  # block under ONE method-level rescue, so a raise on entry 2 of 3 used to
  # abort the whole batch, report 0 (identical to "everything deduped"), and
  # this task cleared the column anyway — destroying entries 2 and 3 though only
  # 2 ever failed. #extract_entry! is called once per entry in its own
  # begin/rescue instead, specifically so this cannot happen.
  context "when the extractor raises partway through a loop's entries" do
    it "keeps exactly the entries not confirmed stored, not a blanket wipe, and reports it" do
      readd_column!
      loop_record = create(:ai_ralph_loop, account: account)
      raw_set_learnings(loop_record.id, [
        { "text" => "first entry, stores fine", "iteration" => 1 },
        { "text" => "second entry, storage raises", "iteration" => 2 },
        { "text" => "third entry, stores fine", "iteration" => 3 }
      ])
      # The account-level health probe must stay healthy so execution reaches
      # the per-entry loop — this is D1's failure mode, not D2's (probe-down).
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
      allow_any_instance_of(Ai::Learning::RalphLearningExtractor)
        .to receive(:extract_entry!) do |_instance, _loop, entry|
          raise StandardError, "embedding provider unreachable" if entry["text"] == "second entry, storage raises"

          true
        end
      allow(Rails.logger).to receive(:error)

      error = nil
      begin
        run_task
      rescue SystemExit => e
        error = e
      end

      # Incomplete (an entry was kept) is reported loudly, not as a quiet success.
      expect(error).not_to be_nil
      expect(error.status).not_to eq(0)
      remaining = JSON.parse(raw_learnings(loop_record.id))
      expect(remaining.map { |e| e["text"] }).to eq([ "second entry, storage raises" ])
    end
  end

  context "when every loop's column is already empty" do
    it "does nothing and does not blow up" do
      expect(Ai::Learning::RalphLearningExtractor).not_to receive(:new)

      expect { run_task }.not_to raise_error
    end
  end

  context "when the embedding service is unreachable" do
    it "stops before touching any row for that account, and exits nonzero" do
      readd_column!
      loop_record = create(:ai_ralph_loop, account: account)
      raw_set_learnings(loop_record.id, [ { "text" => "would be lost silently", "iteration" => 1 } ])
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_raise(Ai::Memory::EmbeddingService::EmbeddingError, "worker embedding service down")
      allow(Rails.logger).to receive(:error)

      error = nil
      begin
        run_task
      rescue SystemExit => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.status).not_to eq(0)
      # THE SAFETY PROPERTY: an outage must not read as "nothing to drain" and
      # silently clear the row — that would be the exact permanent loss the
      # drop migration's refusal guard exists to prevent.
      expect(raw_learnings(loop_record.id)).not_to eq("[]")
    end
  end
end
