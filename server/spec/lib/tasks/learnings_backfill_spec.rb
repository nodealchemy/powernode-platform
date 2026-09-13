# frozen_string_literal: true

require "rails_helper"

# server/lib/tasks/learnings_backfill.rake — repairs compound learnings whose
# embedding is nil (persisted while the worker embedding service was down and
# therefore invisible to every nearest_neighbors path, including the semantic
# branch of query_learnings recall).
RSpec.describe "ai:backfill_learning_embeddings" do
  let!(:account) { create(:account) }
  let(:vector) { Array.new(1536, 0.1) }

  # Rake::Application is used rather than Rails.application.load_tasks so this
  # neither depends on nor mutates global Rake state (mirrors
  # spec/lib/tasks/claude_sync_spec.rb).
  def run_task(*args)
    previous_application = Rake.application
    begin
      Rake.application = Rake::Application.new
      Rake.application.rake_require("tasks/learnings_backfill", [ Rails.root.join("lib").to_s ], [])
      Rake::Task.define_task(:environment)
      silence_stream { Rake::Task["ai:backfill_learning_embeddings"].invoke(*args) }
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

  before { allow(Rails.logger).to receive(:info) }

  context "when the embedding service answers" do
    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate_batch) { |_svc, texts, **| texts.map { vector } }
    end

    it "embeds active learnings that have none" do
      learning = create(:ai_compound_learning, account: account, status: "active", embedding: nil)

      run_task

      expect(learning.reload.embedding).to be_present
    end

    it "embeds a VERIFIED learning that has none — the most trusted tier is not skipped" do
      verified = create(:ai_compound_learning, account: account, status: "verified", embedding: nil)

      run_task

      expect(verified.reload.embedding).to be_present
    end

    it "leaves a learning outside the surfacing set alone" do
      # retired/superseded/deprecated/disproven rows are excluded from every
      # recall branch, so embedding them buys nothing and would spend worker
      # calls. Both arms of the status oracle: the surfacing pair is repaired
      # (above), everything else is not.
      retired = create(:ai_compound_learning, account: account, status: "retired", embedding: nil)
      superseded = create(:ai_compound_learning, account: account, status: "superseded", embedding: nil)

      run_task

      expect(retired.reload.embedding).to be_nil
      expect(superseded.reload.embedding).to be_nil
    end

    it "leaves a learning that already has an embedding untouched" do
      existing = Array.new(1536, 0.42)
      learning = create(:ai_compound_learning, account: account, status: "active", embedding: existing)
      before_updated_at = learning.reload.last_event_processed_at

      run_task

      learning.reload
      expect(learning.embedding.to_a.first).to eq(0.42)
      expect(learning.last_event_processed_at).to eq(before_updated_at)
    end

    it "is idempotent — a second run has nothing left to do" do
      learning = create(:ai_compound_learning, account: account, status: "active", embedding: nil)

      run_task
      first = learning.reload.last_event_processed_at
      run_task

      expect(learning.reload.last_event_processed_at).to eq(first)
    end

    it "honors the limit argument" do
      3.times { create(:ai_compound_learning, account: account, status: "active", embedding: nil) }

      run_task("1")

      embedded = Ai::CompoundLearning.where(account: account).where.not(embedding: nil).count
      expect(embedded).to eq(1)
    end

    # F5 (review) — the limit is a PER-ACCOUNT budget, and the single-account
    # example above cannot tell that apart from a global one: both leave 1
    # embedded row. With two accounts a global limit embeds 1 in total, a
    # per-account limit embeds 1 in EACH. Hence the argument name.
    it "applies the limit per account, not across the fleet" do
      other_account = create(:account)
      2.times { create(:ai_compound_learning, account: account, status: "active", embedding: nil) }
      2.times { create(:ai_compound_learning, account: other_account, status: "active", embedding: nil) }

      run_task("1")

      expect(Ai::CompoundLearning.where(account: account).where.not(embedding: nil).count).to eq(1)
      expect(Ai::CompoundLearning.where(account: other_account).where.not(embedding: nil).count).to eq(1)
    end

    it "rejects a non-positive limit" do
      expect { run_task("0") }.to raise_error(SystemExit)
    end
  end

  context "when the embedding service is unreachable" do
    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate_batch)
        .and_raise(Ai::Memory::EmbeddingService::EmbeddingError, "worker embedding service down")
      allow(Rails.logger).to receive(:error)
    end

    it "writes nothing and exits nonzero" do
      learning = create(:ai_compound_learning, account: account, status: "active", embedding: nil)

      error = nil
      begin
        run_task
      rescue SystemExit => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.status).not_to eq(0)
      expect(learning.reload.embedding).to be_nil
    end
  end

  context "when the embedding service answers with no vectors" do
    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate_batch) { |_svc, texts, **| texts.map { nil } }
      allow(Rails.logger).to receive(:error)
    end

    it "writes no empty vector and exits nonzero" do
      learning = create(:ai_compound_learning, account: account, status: "active", embedding: nil)

      expect { run_task }.to raise_error(SystemExit)
      expect(learning.reload.embedding).to be_nil
    end
  end
end
