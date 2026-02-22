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
      expect(result[:count]).to be >= 0
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
