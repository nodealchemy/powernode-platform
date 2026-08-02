# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Memory::SharedKnowledgeService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  # Stub embedding service to return deterministic vectors
  let(:mock_embedding) { Array.new(1536) { rand(-1.0..1.0) } }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService)
      .to receive(:generate).and_return(mock_embedding)
  end

  # ===========================================================================
  # create
  # ===========================================================================

  describe "#create" do
    it "creates entry with embedding" do
      result = service.create(
        title: "API Response Standards",
        content: "All API responses must use render_success and render_error helpers.",
        content_type: "procedure",
        access_level: "team",
        tags: ["api", "standards"]
      )

      expect(result[:success]).to be true
      expect(result[:entry]).to be_present
      expect(result[:entry][:title]).to eq("API Response Standards")
      expect(result[:entry][:content_type]).to eq("procedure")
      expect(result[:entry][:access_level]).to eq("team")
      expect(result[:entry][:tags]).to eq(["api", "standards"])

      entry = Ai::SharedKnowledge.find(result[:entry][:id])
      expect(entry.embedding).to be_present
    end

    it "detects duplicates" do
      # Create the first entry
      service.create(
        title: "Duplicate Test Entry",
        content: "This is the original content for dedup testing.",
        content_type: "text",
        access_level: "team"
      )

      # Same embedding → similarity=1.0 → above 0.92 threshold
      result = service.create(
        title: "Duplicate Test Entry Copy",
        content: "This is nearly identical content for dedup testing.",
        content_type: "text",
        access_level: "team"
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("Duplicate")
      expect(result[:existing_entry_id]).to be_present
    end

    it "validates content type via ArgumentError" do
      expect {
        service.create(
          title: "Bad Type",
          content: "Content",
          content_type: "invalid_type",
          access_level: "team"
        )
      }.to raise_error(ArgumentError, /Invalid content_type/)
    end

    it "validates access level via ArgumentError" do
      expect {
        service.create(
          title: "Bad Level",
          content: "Content",
          content_type: "text",
          access_level: "invalid_level"
        )
      }.to raise_error(ArgumentError, /Invalid access_level/)
    end
  end

  # ===========================================================================
  # search
  # ===========================================================================

  describe "#search" do
    before do
      # Create entries with distinct embeddings to avoid dedup
      embeddings = 3.times.map { Array.new(1536) { rand(-1.0..1.0) } }
      call_count = 0

      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate) do
          idx = call_count % embeddings.size
          call_count += 1
          embeddings[idx]
        end

      service.create(
        title: "Ruby Best Practices",
        content: "Use frozen string literal pragma in all Ruby files.",
        content_type: "procedure",
        access_level: "account",
        tags: ["ruby", "best-practices"]
      )

      service.create(
        title: "Database Migration Rules",
        content: "Never create separate indexes for t.references columns.",
        content_type: "procedure",
        access_level: "team",
        tags: ["database", "migrations"]
      )

      service.create(
        title: "Private Agent Config",
        content: "Agent-specific configuration details.",
        content_type: "text",
        access_level: "private",
        tags: ["agent", "config"]
      )
    end

    it "returns ranked results" do
      result = service.search(query: "Ruby programming best practices")

      expect(result[:success]).to be true
      expect(result[:entries]).to be_an(Array)
      expect(result[:count]).to be > 0
    end

    it "filters by content type" do
      result = service.search(
        query: "practices",
        content_type: "procedure"
      )

      expect(result[:success]).to be true
      result[:entries].each do |entry|
        expect(entry[:content_type]).to eq("procedure")
      end
    end

    it "includes similarity scores in results" do
      result = service.search(query: "Ruby practices")

      expect(result[:success]).to be true
      result[:entries].each do |entry|
        expect(entry).to have_key(:similarity)
      end
    end

    it "respects result limit" do
      result = service.search(query: "practices", limit: 1)

      expect(result[:success]).to be true
      expect(result[:entries].size).to be <= 1
    end

    context "when the embedding service is unavailable (RAG outage)" do
      before do
        allow_any_instance_of(Ai::Memory::EmbeddingService)
          .to receive(:generate)
          .and_raise(
            Ai::Memory::EmbeddingService::EmbeddingError,
            "Worker embedding service returned no result."
          )
      end

      it "falls back to keyword search instead of failing the whole query" do
        result = service.search(query: "migration rules")

        expect(result[:success]).to be true
        expect(result[:entries].map { |e| e[:title] }).to include("Database Migration Rules")
      end

      it "reports the underlying reason when the fallback itself cannot run" do
        allow(service).to receive(:keyword_search).and_raise(StandardError, "pg down")

        result = service.search(query: "migration rules")

        expect(result[:success]).to be false
        expect(result[:error]).to include("pg down")
      end
    end

    context "with archived entries" do
      let(:target) { Ai::SharedKnowledge.find_by!(title: "Ruby Best Practices") }

      before do
        # Pin the query embedding to exactly match the target entry so the
        # assertions are about archived-filtering, not vector-similarity luck.
        allow_any_instance_of(Ai::Memory::EmbeddingService)
          .to receive(:generate).and_return(target.embedding)
      end

      it "excludes archived entries from results" do
        service.archive(entry_id: target.id)

        result = service.search(query: "Ruby programming best practices")

        expect(result[:success]).to be true
        expect(result[:entries].map { |e| e[:id] }).not_to include(target.id)
      end

      it "does not usage-boost an archived entry via search" do
        service.archive(entry_id: target.id)
        usage_before = target.reload.usage_count

        service.search(query: "Ruby programming best practices")

        expect(target.reload.usage_count).to eq(usage_before)
      end

      it "still returns entries with NULL provenance (not miscategorized as archived)" do
        target.update_columns(provenance: nil)

        result = service.search(query: "Ruby programming best practices")

        expect(result[:success]).to be true
        expect(result[:entries].map { |e| e[:id] }).to include(target.id)
      end
    end
  end

  # ===========================================================================
  # update
  # ===========================================================================

  describe "#update" do
    let!(:entry_result) do
      service.create(
        title: "Original Title",
        content: "Original content that will be updated.",
        content_type: "text",
        access_level: "team"
      )
    end

    let(:entry_id) { entry_result[:entry][:id] }

    it "regenerates embedding on content change" do
      new_embedding = Array.new(1536) { rand(-1.0..1.0) }
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate).and_return(new_embedding)

      result = service.update(
        entry_id: entry_id,
        content: "Completely new and different content for this entry."
      )

      expect(result[:success]).to be true
      expect(result[:entry][:content]).to include("Completely new")

      entry = Ai::SharedKnowledge.find(entry_id)
      expect(entry.embedding).to be_present
    end

    it "does not regenerate embedding when only title changes" do
      expect_any_instance_of(Ai::Memory::EmbeddingService)
        .not_to receive(:generate)

      result = service.update(
        entry_id: entry_id,
        title: "Updated Title Only"
      )

      expect(result[:success]).to be true
      expect(result[:entry][:title]).to eq("Updated Title Only")
    end

    it "returns error for nonexistent entry" do
      result = service.update(
        entry_id: SecureRandom.uuid,
        title: "Updated"
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end
  end

  # ===========================================================================
  # archive
  # ===========================================================================

  describe "#archive" do
    let!(:entry_result) do
      service.create(
        title: "Entry to Archive",
        content: "This entry will be archived.",
        content_type: "text",
        access_level: "team"
      )
    end

    let(:entry_id) { entry_result[:entry][:id] }

    it "soft-archives entry" do
      result = service.archive(entry_id: entry_id)

      expect(result[:success]).to be true
      expect(result[:entry_id]).to eq(entry_id)

      entry = Ai::SharedKnowledge.find(entry_id)
      expect(entry.provenance["archived"]).to be true
      expect(entry.provenance["archived_at"]).to be_present
    end

    it "returns error for nonexistent entry" do
      result = service.archive(entry_id: SecureRandom.uuid)

      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end
  end

  # ===========================================================================
  # promote
  # ===========================================================================

  describe "#promote" do
    let!(:entry_result) do
      service.create(
        title: "Promotable Entry",
        content: "This entry will be promoted to higher access level.",
        content_type: "fact",
        access_level: "private"
      )
    end

    let(:entry_id) { entry_result[:entry][:id] }

    it "upgrades access level" do
      result = service.promote(entry_id: entry_id, new_access_level: "team")

      expect(result[:success]).to be true
      expect(result[:entry][:access_level]).to eq("team")

      entry = Ai::SharedKnowledge.find(entry_id)
      expect(entry.provenance["promoted_at"]).to be_present
      expect(entry.provenance["promoted_from"]).to eq("private")
    end

    # Regression: the log line interpolated entry.access_level AFTER update!, so it printed
    # "team → team" instead of "private → team" (old_level was captured but unused).
    it "logs the previous access level, not the post-update value" do
      allow(Rails.logger).to receive(:info)

      service.promote(entry_id: entry_id, new_access_level: "team")

      expect(Rails.logger).to have_received(:info)
        .with(a_string_matching(/Promoted entry .*: private → team/))
    end

    it "prevents demotion" do
      # First promote to account
      service.promote(entry_id: entry_id, new_access_level: "account")

      # Try to demote to team
      result = service.promote(entry_id: entry_id, new_access_level: "team")

      expect(result[:success]).to be false
      expect(result[:error]).to include("Cannot demote")
    end

    it "returns error for nonexistent entry" do
      result = service.promote(entry_id: SecureRandom.uuid, new_access_level: "team")

      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end
  end

  # ===========================================================================
  # import_from_learnings
  # ===========================================================================

  describe "#import_from_learnings" do
    before do
      # Create compound learnings directly since no factory exists
      call_count = 0
      embeddings = 3.times.map { Array.new(1536) { rand(-1.0..1.0) } }
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate) do
          idx = call_count % embeddings.size
          call_count += 1
          embeddings[idx]
        end

      team = create(:ai_agent_team, account: account)

      Ai::CompoundLearning.create!(
        account: account,
        ai_agent_team: team,
        title: "Important Pattern",
        content: "Always validate input parameters before processing.",
        category: "best_practice",
        importance_score: 0.85,
        scope: "global",
        status: "active",
        extraction_method: "auto_success"
      )

      Ai::CompoundLearning.create!(
        account: account,
        ai_agent_team: team,
        title: "Low Priority Note",
        content: "Minor observation about response times.",
        category: "performance_insight",
        importance_score: 0.3,
        scope: "global",
        status: "active",
        extraction_method: "auto_success"
      )
    end

    it "imports from CompoundLearning" do
      result = service.import_from_learnings(min_importance: 0.7)

      expect(result[:success]).to be true
      expect(result[:imported]).to be >= 1
    end

    it "respects minimum importance threshold" do
      result = service.import_from_learnings(min_importance: 0.9)

      expect(result[:success]).to be true
      expect(result[:imported]).to eq(0)
    end
  end

  # ===========================================================================
  # import_from_learnings marks source learnings
  # ===========================================================================

  describe "#import_from_learnings source learning event processing" do
    let(:team) { create(:ai_agent_team, account: account) }

    before do
      # Distinct embeddings per call
      call_count = 0
      embeddings = 5.times.map { Array.new(1536) { rand(-1.0..1.0) } }
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate) do
          idx = call_count % embeddings.size
          call_count += 1
          embeddings[idx]
        end
    end

    it "sets last_event_processed_at on source learnings after successful import" do
      learning = Ai::CompoundLearning.create!(
        account: account,
        ai_agent_team: team,
        title: "Imported Pattern",
        content: "Pattern content that will be imported into shared knowledge.",
        category: "best_practice",
        importance_score: 0.85,
        scope: "global",
        status: "active",
        extraction_method: "auto_success"
      )

      expect(learning.last_event_processed_at).to be_nil

      service.import_from_learnings(min_importance: 0.7)

      expect(learning.reload.last_event_processed_at).to be_within(2.seconds).of(Time.current)
    end
  end

  # ===========================================================================
  # import_from_learnings backlog draining (fixes the stalled feedback pipeline:
  # duplicate-skipped learnings used to stay in scope forever, so every daily
  # run re-embedded the same head-of-scope batch and the backlog never drained)
  # ===========================================================================

  describe "#import_from_learnings backlog draining" do
    let(:team) { create(:ai_agent_team, account: account) }

    def build_learning(title, content)
      Ai::CompoundLearning.create!(
        account: account,
        ai_agent_team: team,
        title: title,
        content: content,
        category: "best_practice",
        importance_score: 0.85,
        scope: "global",
        status: "active",
        extraction_method: "auto_success"
      )
    end

    it "marks duplicate-skipped learnings processed so the batch cursor advances" do
      # Single fixed embedding (default stub) → the learning dedups against
      # the pre-existing shared knowledge entry.
      service.create(
        title: "Existing Entry",
        content: "Duplicate learning content that already exists in shared knowledge.",
        content_type: "procedure"
      )
      learning = build_learning("Dup Learning", "Duplicate learning content that already exists in shared knowledge.")

      result = service.import_from_learnings(min_importance: 0.7)

      expect(result[:skipped]).to eq(1)
      expect(result[:remaining]).to eq(0)
      expect(learning.reload.last_event_processed_at).to be_within(2.seconds).of(Time.current)
    end

    it "excludes recently processed learnings from subsequent runs" do
      build_learning("Once Imported", "Content imported on the first pass of the day.")

      first = service.import_from_learnings(min_importance: 0.7)
      second = service.import_from_learnings(min_importance: 0.7)

      expect(first[:imported] + first[:skipped]).to eq(1)
      expect(second[:imported]).to eq(0)
      expect(second[:skipped]).to eq(0)
      expect(second[:remaining]).to eq(0)
    end

    it "reports honest remaining when capped by max_per_run" do
      embeddings = 3.times.map { Array.new(1536) { rand(-1.0..1.0) } }
      call_count = 0
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate) do
          idx = call_count % embeddings.size
          call_count += 1
          embeddings[idx]
        end

      build_learning("Backlog A", "First distinct learning body for backlog drain testing.")
      build_learning("Backlog B", "Second completely different content about worker queue tuning.")

      result = service.import_from_learnings(min_importance: 0.7, max_per_run: 1)

      expect(result[:imported]).to eq(1)
      expect(result[:remaining]).to eq(1)
    end
  end

  # ===========================================================================
  # backfill_embeddings
  # ===========================================================================

  describe "#backfill_embeddings" do
    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate_batch) { |_svc, texts, **_| texts.map { mock_embedding } }
    end

    def build_unembedded(title:, archived: false)
      Ai::SharedKnowledge.create!(
        account: account, title: title, content: "#{title} body content here",
        content_type: "text", access_level: "team", embedding: nil,
        provenance: archived ? { archived: true } : {}
      )
    end

    it "backfills embeddings for entries stored without one" do
      a = build_unembedded(title: "Stranded A")
      b = build_unembedded(title: "Stranded B")

      result = service.backfill_embeddings

      expect(result[:success]).to be true
      expect(result[:embedded]).to eq(2)
      expect(result[:remaining]).to eq(0)
      expect(a.reload.embedding).to be_present
      expect(b.reload.embedding).to be_present
    end

    it "is idempotent — a second run finds nothing pending" do
      build_unembedded(title: "Once")
      service.backfill_embeddings

      expect(service.backfill_embeddings).to include(embedded: 0, remaining: 0)
    end

    it "skips archived entries" do
      archived = build_unembedded(title: "Archived", archived: true)

      expect(service.backfill_embeddings[:embedded]).to eq(0)
      expect(archived.reload.embedding).to be_nil
    end

    it "respects max_per_run and reports the remainder" do
      3.times { |i| build_unembedded(title: "Batch #{i}") }

      result = service.backfill_embeddings(max_per_run: 2)

      expect(result[:embedded]).to eq(2)
      expect(result[:remaining]).to eq(1)
    end

    it "does not touch entries that already have an embedding" do
      embedded_entry = Ai::SharedKnowledge.create!(
        account: account, title: "Already", content: "has a vector",
        content_type: "text", access_level: "team", embedding: mock_embedding
      )

      expect { service.backfill_embeddings }
        .not_to(change { embedded_entry.reload.updated_at })
    end
  end

  # ===========================================================================
  # stats
  # ===========================================================================

  describe "#stats" do
    before do
      # Create distinct embeddings
      embeddings = 3.times.map { Array.new(1536) { rand(-1.0..1.0) } }
      call_count = 0
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate) do
          idx = call_count % embeddings.size
          call_count += 1
          embeddings[idx]
        end

      service.create(
        title: "Stats Test 1",
        content: "First entry for stats testing.",
        content_type: "text",
        access_level: "team"
      )

      service.create(
        title: "Stats Test 2",
        content: "Second entry for stats testing.",
        content_type: "procedure",
        access_level: "account"
      )

      service.create(
        title: "Stats Test 3",
        content: "Third entry for stats testing.",
        content_type: "fact",
        access_level: "team"
      )
    end

    it "returns correct counts" do
      result = service.stats

      expect(result[:success]).to be true
      expect(result[:stats][:total]).to be >= 3
      expect(result[:stats][:by_access_level]).to be_a(Hash)
      expect(result[:stats][:by_content_type]).to be_a(Hash)
      expect(result[:stats][:avg_quality_score]).to be_a(Float)
      expect(result[:stats][:with_embeddings]).to be >= 0
      expect(result[:stats][:embedding_coverage]).to be_a(Numeric)
      expect(result[:stats][:most_used]).to be_an(Array)
      expect(result[:stats][:recently_added]).to be_an(Array)
    end
  end

  # ===========================================================================
  # recalculate_all_quality
  # ===========================================================================

  describe "#recalculate_all_quality" do
    before do
      embeddings = 3.times.map { Array.new(1536) { rand(-1.0..1.0) } }
      call_count = 0
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate) do
          idx = call_count % embeddings.size
          call_count += 1
          embeddings[idx]
        end
    end

    it "recalculates stale entries" do
      entry = create(:ai_shared_knowledge, account: account,
                     last_quality_recalc_at: 2.days.ago)
      old_score = entry.quality_score

      result = service.recalculate_all_quality

      expect(result[:success]).to be true
      expect(result[:recalculated]).to be >= 1

      entry.reload
      expect(entry.last_quality_recalc_at).to be_within(2.seconds).of(Time.current)
    end

    it "skips entries recalculated within 24 hours" do
      create(:ai_shared_knowledge, account: account,
             last_quality_recalc_at: 1.hour.ago)

      result = service.recalculate_all_quality

      expect(result[:success]).to be true
      expect(result[:recalculated]).to eq(0)
    end

    it "skips archived entries" do
      create(:ai_shared_knowledge, account: account,
             last_quality_recalc_at: 2.days.ago,
             provenance: { "archived" => true, "archived_at" => 1.day.ago.iso8601 })

      result = service.recalculate_all_quality

      expect(result[:success]).to be true
      expect(result[:recalculated]).to eq(0)
    end

    it "recalculates entries that have never been scored" do
      create(:ai_shared_knowledge, account: account,
             last_quality_recalc_at: nil)

      result = service.recalculate_all_quality

      expect(result[:success]).to be true
      expect(result[:recalculated]).to be >= 1
    end

    it "stamps last_event_processed_at on recalculated entries (live freshness signal)" do
      entry = create(:ai_shared_knowledge, account: account,
                     last_quality_recalc_at: 2.days.ago,
                     last_event_processed_at: nil)

      result = service.recalculate_all_quality

      expect(result[:success]).to be true
      expect(result[:recalculated]).to be >= 1

      entry.reload
      # Embedding-independent freshness signal so event_processed_24h reflects
      # ongoing pipeline health, not only new-embedding activity.
      expect(entry.last_event_processed_at).to be_within(2.seconds).of(Time.current)
    end

    it "reports honest remaining when capped by max_per_run (no double subtraction)" do
      3.times do |i|
        create(:ai_shared_knowledge, account: account,
               last_quality_recalc_at: (2 + i).days.ago,
               last_event_processed_at: nil)
      end

      result = service.recalculate_all_quality(max_per_run: 2)

      expect(result[:recalculated]).to eq(2)
      # Processed rows leave the stale scope (recalc stamps both timestamps),
      # so `remaining` must be the recomputed scope count — subtracting the
      # batch size again would report 0 and stop the worker's drain chain.
      expect(result[:remaining]).to eq(1)
    end
  end

  # ===========================================================================
  # build_context
  # ===========================================================================

  describe "#build_context" do
    before do
      embeddings = 2.times.map { Array.new(1536) { rand(-1.0..1.0) } }
      call_count = 0
      allow_any_instance_of(Ai::Memory::EmbeddingService)
        .to receive(:generate) do
          idx = call_count % embeddings.size
          call_count += 1
          embeddings[idx]
        end

      service.create(
        title: "Context Test Entry",
        content: "Important context about API design patterns and best practices for building REST APIs.",
        content_type: "procedure",
        access_level: "team"
      )

      service.create(
        title: "Another Context Entry",
        content: "Database optimization techniques for large-scale PostgreSQL deployments.",
        content_type: "text",
        access_level: "account"
      )
    end

    it "respects token budget" do
      result = service.build_context(query: "API design", token_budget: 2000)

      expect(result[:success]).to be true
      if result[:context]
        expect(result[:token_estimate]).to be <= 2000
        expect(result[:entry_ids]).to be_an(Array)
      end
    end

    it "returns entry_ids of used entries" do
      result = service.build_context(query: "API patterns", token_budget: 5000)

      expect(result[:success]).to be true
      expect(result[:entry_ids]).to be_an(Array)
    end
  end
end
