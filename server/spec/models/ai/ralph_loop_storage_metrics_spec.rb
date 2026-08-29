# frozen_string_literal: true

require "rails_helper"

# ============================================================================
# IMP-4bc71cfb2d2c — MEASURE the loop's durable store, and COMPARE it to a bound.
#
# The original defect (IMP-7f415874c14a) was that `ai_ralph_loops.learnings` grew
# to 548 kB / 354 entries and was rewritten IN FULL on every completion. Nothing
# reported it — no metric, no alert, no cap. It was found by reading code.
#
# So the assertion that matters here is NOT "the number is right". It is: a loop
# whose store EXCEEDS the configured bound says so on the surface an operator
# reads. A metric with no threshold comparison reproduces the original silence.
#
# ai_output and ai_prompt are reported SEPARATELY on purpose. ai_prompt measures
# 0 bytes across all 493 production rows, which reads exactly like a dead column;
# it is not. Its sole writer is the in-platform Ai::Ralph::ExecutionService, and
# every production row was written by the MCP dev_loop bridge instead, which
# never populates it. Averaging the two into one number invites a wrong
# "unused, drop it" conclusion.
#
# The metric must also not reintroduce the O(n) read it exists to prevent:
# the batch path is ONE aggregate query for N loops, never a query per loop.
# ============================================================================
RSpec.describe "ralph-loop storage metrics", type: :model do
  let(:account) { create(:account) }
  let(:record) { create(:ai_ralph_loop, account: account, current_iteration: 0) }

  def add_iteration!(number, ai_output: nil, ai_prompt: nil, learning: nil)
    create(:ai_ralph_iteration, ralph_loop: record, iteration_number: number,
           status: "completed", completed_at: Time.current,
           ai_output: ai_output, ai_prompt: ai_prompt, learning_extracted: learning)
  end

  # Count only real statements — schema reflection and transaction control are
  # noise for "did this become an N+1".
  def count_queries
    queries = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      name = payload[:name].to_s
      next if payload[:cached]
      next if name.in?([ "SCHEMA", "TRANSACTION" ])
      next if payload[:sql].to_s.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      queries << payload[:sql]
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(sub) if sub
  end

  describe "#storage_metrics" do
    it "reports counts and reports ai_output / ai_prompt as separate byte totals" do
      add_iteration!(1, ai_output: "x" * 4000, learning: "learned something")
      add_iteration!(2, ai_output: "y" * 4000)
      add_iteration!(3, ai_output: "z" * 4000, learning: "learned another")

      metrics = record.storage_metrics

      expect(metrics[:iteration_count]).to eq(3)
      expect(metrics[:learning_iteration_count]).to eq(2)
      expect(metrics[:ai_output_bytes]).to be > 0
      # The production asymmetry: the dev_loop bridge never writes ai_prompt.
      expect(metrics[:ai_prompt_bytes]).to eq(0)
      expect(metrics).to have_key(:ai_prompt_bytes)
    end

    # ai_prompt is NOT dead. Its in-platform writer moves this number and only
    # this number, which is exactly why the two are not averaged together.
    it "moves ai_prompt_bytes independently of ai_output_bytes" do
      add_iteration!(1, ai_prompt: "p" * 4000)

      metrics = record.storage_metrics

      expect(metrics[:ai_prompt_bytes]).to be > 0
      expect(metrics[:ai_output_bytes]).to eq(0)
    end

    # The dormant loop-level column is the ORIGINAL defect's surface. If a future
    # change starts appending to it again, this number is what notices.
    it "measures the dormant loop-level learnings column" do
      expect(record.storage_metrics).to have_key(:learnings_column_bytes)
      expect(record.storage_metrics[:learnings_column_bytes]).to be >= 0
    end

    it "reports an empty loop as zero rather than raising" do
      metrics = record.storage_metrics

      expect(metrics[:iteration_count]).to eq(0)
      expect(metrics[:ai_output_bytes]).to eq(0)
      expect(metrics[:ai_prompt_bytes]).to eq(0)
    end
  end

  describe "the configured bound" do
    it "defaults to the documented constant when nothing is configured" do
      expect(record.storage_limit_bytes)
        .to eq(Ai::RalphLoopConcerns::StorageMetrics::DEFAULT_STORAGE_LIMIT_BYTES)
    end

    it "is tunable platform-wide through SiteSetting" do
      SiteSetting.set(Ai::RalphLoopConcerns::StorageMetrics::STORAGE_LIMIT_SETTING,
                      4096, setting_type: "integer")

      expect(record.storage_limit_bytes).to eq(4096)
    end

    it "is tunable per loop through configuration, overriding the platform default" do
      SiteSetting.set(Ai::RalphLoopConcerns::StorageMetrics::STORAGE_LIMIT_SETTING,
                      4096, setting_type: "integer")
      record.update!(configuration: { "max_storage_bytes" => 123 })

      expect(record.storage_limit_bytes).to eq(123)
    end

    # A GARBLED BOUND MUST NOT SILENTLY UNCAP THE LOOP. `"abc".to_i` is 0 and 0
    # means "no cap" here, so a naive coercion would disable the alarm this
    # increment exists to raise — the original defect wearing a different hat.
    it "falls back to the documented default when the per-loop bound is not a number" do
      record.update!(configuration: { "max_storage_bytes" => "abc" })

      expect(record.storage_limit_bytes)
        .to eq(Ai::RalphLoopConcerns::StorageMetrics::DEFAULT_STORAGE_LIMIT_BYTES)
    end

    it "falls back to the documented default when the SiteSetting bound is not a number" do
      SiteSetting.set(Ai::RalphLoopConcerns::StorageMetrics::STORAGE_LIMIT_SETTING,
                      "unlimited", setting_type: "string")

      expect(record.storage_limit_bytes)
        .to eq(Ai::RalphLoopConcerns::StorageMetrics::DEFAULT_STORAGE_LIMIT_BYTES)
    end

    # "64MB" is the single most likely thing an operator types. `.to_i` would
    # make it a 64-BYTE cap — every loop permanently over budget, which burns the
    # alarm's credibility as surely as no alarm at all.
    it "rejects a unit-suffixed bound instead of reading it as a byte count" do
      SiteSetting.set(Ai::RalphLoopConcerns::StorageMetrics::STORAGE_LIMIT_SETTING,
                      "64MB", setting_type: "string")

      expect(record.storage_limit_bytes)
        .to eq(Ai::RalphLoopConcerns::StorageMetrics::DEFAULT_STORAGE_LIMIT_BYTES)
    end

    # Scientific notation DOES parse, and must parse as 1e9, never as 1.
    it "reads a scientific-notation bound as its full value" do
      SiteSetting.set(Ai::RalphLoopConcerns::StorageMetrics::STORAGE_LIMIT_SETTING,
                      "1e9", setting_type: "string")

      expect(record.storage_limit_bytes).to eq(1_000_000_000)
    end

    # SiteSetting.get returns a String unless setting_type is "integer", so the
    # string form is the common path, not the exotic one.
    it "honours a numeric bound stored as a string" do
      SiteSetting.set(Ai::RalphLoopConcerns::StorageMetrics::STORAGE_LIMIT_SETTING,
                      "4096", setting_type: "string")

      expect(record.storage_limit_bytes).to eq(4096)
    end

    it "treats a non-positive bound as no cap" do
      record.update!(configuration: { "max_storage_bytes" => 0 })
      add_iteration!(1, ai_output: "x" * 8000)

      expect(record.storage_limit_bytes).to eq(0)
      expect(record.storage_limit_exceeded?).to be(false)
    end
  end

  # ==========================================================================
  # THE TEST THAT WOULD HAVE CAUGHT THE ORIGINAL DEFECT.
  # A loop whose store exceeds the configured bound is REPORTED as exceeding it
  # through the summary surface an operator actually reads.
  # ==========================================================================
  # NOTE ON THE FIXTURE: pg_column_size reports STORED bytes, so a run of
  # identical characters compresses to almost nothing (3 x 4000 "x" measured 173
  # bytes, not 12000). That is the correct semantic — an operator wants the space
  # actually consumed — but it means a size fixture has to be incompressible.
  describe "threshold comparison on the summary surface" do
    before { record.update!(configuration: { "max_storage_bytes" => 1024 }) }

    it "reports a loop over the bound as exceeding it" do
      3.times { |i| add_iteration!(i + 1, ai_output: SecureRandom.alphanumeric(4000)) }

      storage = record.loop_summary[:storage]

      expect(storage[:limit_bytes]).to eq(1024)
      expect(storage[:total_bytes]).to be > 1024
      expect(storage[:limit_exceeded]).to be(true)
      expect(storage[:usage_pct]).to be > 100
    end

    it "reports a loop under the bound as within it" do
      add_iteration!(1, ai_output: "small")

      storage = record.loop_summary[:storage]

      expect(storage[:limit_exceeded]).to be(false)
      expect(storage[:total_bytes]).to be < 1024
    end

    it "carries the same verdict through loop_details" do
      3.times { |i| add_iteration!(i + 1, ai_output: SecureRandom.alphanumeric(4000)) }

      expect(record.loop_details[:storage][:limit_exceeded]).to be(true)
    end
  end

  describe "the metric does not reintroduce an O(n) read" do
    it "costs ONE aggregate query for N loops on the batch path" do
      others = create_list(:ai_ralph_loop, 3, account: account)
      others.each_with_index do |loop_record, idx|
        create(:ai_ralph_iteration, ralph_loop: loop_record, iteration_number: idx + 1,
               status: "completed", ai_output: "out")
      end

      queries = count_queries { Ai::RalphLoop.preload_storage_metrics(others) }

      expect(queries.size).to eq(1)
    end

    it "issues NO further query once preloaded" do
      add_iteration!(1, ai_output: "out")
      Ai::RalphLoop.preload_storage_metrics([ record ])

      queries = count_queries { record.storage_metrics }

      expect(queries).to be_empty
    end

    # #storage_summary asks for the bound three times. The SiteSetting leg is a
    # real SELECT, so an unmemoised bound would fire three settings queries per
    # loop rendered — an N+1 on the settings table instead of the loops one.
    it "resolves the bound ONCE per record, not once per field" do
      Ai::RalphLoop.preload_storage_metrics([ record ])

      queries = count_queries { record.storage_summary }

      expect(queries.size).to be <= 1
    end

    it "never reads iteration rows into memory" do
      add_iteration!(1, ai_output: "out")

      expect(Ai::RalphIteration).not_to receive(:find_each)
      expect(record.storage_metrics[:iteration_count]).to eq(1)
    end
  end
end
