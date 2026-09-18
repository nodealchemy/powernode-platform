# frozen_string_literal: true

require "rails_helper"

# Evaluation 2026-09-18 §1.1 / design D3 — the operator's ruling, not open for
# re-litigation here: rank surfaced learnings by similarity x quality (not
# quality alone), and gate injection at a tighter similarity floor (0.65) than
# recall (0.5).
#
# Floor literals below are hardcoded, not read off
# Ai::Learning::CompoundLearningService::DEFAULT_*_SIMILARITY_THRESHOLD: an
# oracle that reads the value it tests moves with a mutant that changes the
# constant and reports a false green.
RSpec.describe Ai::Learning::CompoundLearningService, "similarity-weighted ranking", type: :service do
  let(:account) { create(:account) }
  let(:embedding_service) { instance_double(Ai::Memory::EmbeddingService) }
  let(:service) { described_class.new(account: account) }
  let(:embedding) { Array.new(1536, 0.1) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:generate_or_nil).and_return(embedding)
    allow(Shared::FeatureFlagService).to receive(:enabled?)
      .with(:compound_learning_injection, account).and_return(true)
  end

  # A real AR record decorated with a hardcoded neighbor_distance via a raw
  # SELECT alias — the same mechanism the neighbor gem uses on genuine
  # nearest_neighbors results (see neighbor/model.rb: `select(..., "<expr> AS
  # neighbor_distance")`), so #respond_to?(:neighbor_distance) is true exactly
  # like a real semantic_search row, and the distance is an exact float we
  # control rather than one derived from real embedding math.
  def with_distance(learning, distance)
    Ai::CompoundLearning
      .where(id: learning.id)
      .select("ai_compound_learnings.*, CAST(#{distance} AS double precision) AS neighbor_distance")
      .first
  end

  describe "the ranking oracle: similarity dominates, quality only breaks ties" do
    # Weakly-similar (similarity 0.55) but heavily-credited (importance 0.95) —
    # the shape of the live store's top-15-by-injection-count rows (12 rows,
    # 52-237 injections each, see the evaluation). injection_count stays below
    # 5 so effective_importance == importance_score, isolating the ranking
    # formula from the outcome-smoothing math tested elsewhere.
    let!(:weak_but_credited) do
      create(:ai_compound_learning, account: account, status: "active",
             title: "CORRECTION to an unrelated task",
             content: "narrowly task-bound correction text",
             importance_score: 0.95)
    end

    # Strongly-similar (similarity 0.95) but fresh (importance 0.3) — a row
    # that actually answers the query and has not yet accumulated credit.
    let!(:strong_but_fresh) do
      create(:ai_compound_learning, account: account, status: "active",
             title: "Directly on point for this task",
             content: "directly relevant fresh content",
             importance_score: 0.3)
    end

    before do
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([
        with_distance(weak_but_credited, 0.45), # similarity 0.55
        with_distance(strong_but_fresh, 0.05)   # similarity 0.95
      ])
    end

    it "ranks the strongly-similar fresh row ABOVE the weakly-similar heavily-credited row on recall" do
      result = service.search_learnings(query: "directly relevant")

      expect(result[:learnings].map(&:id)).to eq([ strong_but_fresh.id, weak_but_credited.id ])
    end

    it "ranks the same way on the injection path (build_compound_context)" do
      result = service.build_compound_context(agent: nil, task_description: "directly relevant")

      expect(result[:learning_ids]).to eq([ strong_but_fresh.id, weak_but_credited.id ])
    end
  end

  describe "separate similarity floors: injection (0.65) vs recall (0.5)" do
    let!(:at_injection_floor) do
      create(:ai_compound_learning, account: account, status: "active",
             content: "row sitting exactly at the injection floor")
    end

    let!(:below_injection_floor) do
      create(:ai_compound_learning, account: account, status: "active",
             content: "row just below the injection floor, still above recall's")
    end

    before do
      # Mirrors Ai::CompoundLearning.semantic_search's own post-filter
      # (`neighbor_distance <= 1.0 - threshold`) so the stub is sensitive to
      # which threshold CompoundLearningService actually passes for each
      # consumer, not just to a canned return value.
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        [
          with_distance(at_injection_floor, 0.35),   # similarity 0.65 exactly
          with_distance(below_injection_floor, 0.36) # similarity 0.64
        ].select { |l| l.neighbor_distance <= 1.0 - kwargs[:threshold] }
      end
    end

    # This example's inclusive edge passes because `1.0 - 0.65` is not exactly
    # 0.35 in IEEE754 (it's 0.35000000000000003), and that rounds the
    # admissible way: `0.35 <= 0.35000000000000003` is true. Production's
    # own comparison (Ai::CompoundLearning.semantic_search) does the identical
    # `neighbor_distance <= 1.0 - threshold`, so this documents real behavior
    # rather than an artifact of the stub.
    it "excludes the sub-floor row from injection but keeps the row exactly at 0.65" do
      result = service.build_compound_context(agent: nil, task_description: "floor test")

      expect(result[:learning_ids]).to include(at_injection_floor.id)
      expect(result[:learning_ids]).not_to include(below_injection_floor.id)
    end

    it "keeps BOTH rows on recall, whose floor (0.5) both sit well above" do
      result = service.search_learnings(query: "floor test")

      ids = result[:learnings].map(&:id)
      expect(ids).to include(at_injection_floor.id, below_injection_floor.id)
    end
  end

  describe "recall floor boundary (0.5)" do
    let!(:at_recall_floor) do
      create(:ai_compound_learning, account: account, status: "active",
             content: "row sitting exactly at the recall floor")
    end

    let!(:below_recall_floor) do
      create(:ai_compound_learning, account: account, status: "active",
             content: "row just below the recall floor")
    end

    before do
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        [
          with_distance(at_recall_floor, 0.5),     # similarity 0.5 exactly
          with_distance(below_recall_floor, 0.51)  # similarity 0.49
        ].select { |l| l.neighbor_distance <= 1.0 - kwargs[:threshold] }
      end
    end

    it "keeps the row exactly at 0.5 and drops the row below it on recall" do
      result = service.search_learnings(query: "floor test")

      ids = result[:learnings].map(&:id)
      expect(ids).to include(at_recall_floor.id)
      expect(ids).not_to include(below_recall_floor.id)
    end
  end

  describe "threshold selection captured at the semantic_search call" do
    let(:captured) { [] }

    before do
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        captured << kwargs
        []
      end
    end

    it "recall (search_learnings) defaults to 0.5" do
      service.search_learnings(query: "anything")

      expect(captured.first[:threshold]).to eq(0.5)
    end

    it "injection (build_compound_context) defaults to 0.65" do
      service.build_compound_context(agent: nil, task_description: "anything")

      expect(captured.first[:threshold]).to eq(0.65)
    end

    it "injection threshold is overridable via the account setting, independent of recall" do
      learning = create(:ai_compound_learning, account: account, status: "active", content: "anything")
      account.update!(settings: (account.settings || {}).merge(
        "ai_learning_injection_similarity_threshold" => 0.8
      ))
      overridden_service = described_class.new(account: account.reload)
      allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
      # IMP-bfe8d1ef425e: an empty primary-tier result now triggers a real
      # (production, not diagnostic) retry at the recall floor — see the
      # dedicated "tiered similarity floor fallback" describe block below.
      # This test is only about which threshold each SURFACE's primary call
      # uses, so the stub returns a hit at every threshold it's asked about,
      # keeping that retry from firing and adding a call this test doesn't
      # expect.
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        captured << kwargs
        [ with_distance(learning, 0.1) ]
      end

      overridden_service.build_compound_context(agent: nil, task_description: "anything")
      overridden_service.search_learnings(query: "anything")

      expect(captured[0][:threshold]).to eq(0.8)   # injection: overridden
      expect(captured[1][:threshold]).to eq(0.5)   # recall: untouched by the injection setting
    end
  end

  # IMP-bfe8d1ef425e (follow-up to IMP-71ea81f5ab16 / evaluation 2026-09-18
  # §1.1): the 0.65 injection floor legitimately empties a real fraction of
  # tasks (measured 68% on a realistically-sized probe), and the injection
  # path has no keyword fallback (see the fallback-mode note on
  # #ranked_learning_candidates_with_mode), so an empty primary tier meant
  # the agent ran with zero learnings. Operator ruling: TIERED retry, not a
  # floor change — try 0.65 first; only when that returns zero candidates,
  # retry once at 0.5 and mark which tier served the result.
  #
  # Three distinct behaviours get three distinct examples — a single example
  # asserting only "results came back non-empty" would still pass under a
  # mutant that collapsed the two tiers into one (e.g. always querying at
  # 0.5), which is exactly the regression this pair of tasks is trying to
  # prevent.
  describe "tiered similarity floor fallback" do
    let!(:clears_primary) do
      create(:ai_compound_learning, account: account, status: "active",
             content: "row that clears the 0.65 injection floor")
    end

    let!(:clears_only_fallback) do
      create(:ai_compound_learning, account: account, status: "active",
             content: "row that only clears the looser 0.5 recall floor")
    end

    it "a probe clearing the primary 0.65 floor is served by the first tier and never reaches the second query" do
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        [ with_distance(clears_primary, 0.2) ].select { |l| l.neighbor_distance <= 1.0 - kwargs[:threshold] }
      end

      result = service.build_compound_context(agent: nil, task_description: "primary tier probe")

      expect(result[:learning_ids]).to eq([ clears_primary.id ])
      expect(result[:match_mode]).to eq("semantic")
      expect(Ai::CompoundLearning).to have_received(:semantic_search).once
    end

    it "a probe clearing only the 0.5 fallback floor is served by the retry and marked as such" do
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        [ with_distance(clears_only_fallback, 0.45) ].select { |l| l.neighbor_distance <= 1.0 - kwargs[:threshold] }
      end

      result = service.build_compound_context(agent: nil, task_description: "fallback tier probe")

      expect(result[:learning_ids]).to eq([ clears_only_fallback.id ])
      expect(result[:match_mode]).to eq("semantic_fallback")
      expect(Ai::CompoundLearning).to have_received(:semantic_search).twice
    end

    it "a probe clearing neither floor still returns empty gracefully and is marked genuinely empty" do
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([])

      result = service.build_compound_context(agent: nil, task_description: "no match probe")

      expect(result[:context]).to be_nil
      expect(result[:learning_ids]).to eq([])
      expect(result[:match_mode]).to eq("none")
      expect(Ai::CompoundLearning).to have_received(:semantic_search).twice
    end

    it "logs the fallback-served outcome with the surfaced count" do
      allow(Rails.logger).to receive(:info)
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        [ with_distance(clears_only_fallback, 0.45) ].select { |l| l.neighbor_distance <= 1.0 - kwargs[:threshold] }
      end

      service.build_compound_context(agent: nil, task_description: "fallback tier probe")

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/injection retrieval outcome.*match_mode=semantic_fallback.*embedding_present=true.*primary_threshold=0\.65.*fallback_threshold=0\.5.*surfaced=1/)
      )
    end

    it "logs the genuinely-empty outcome with surfaced=0" do
      allow(Rails.logger).to receive(:info)
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([])

      service.build_compound_context(agent: nil, task_description: "no match probe")

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/injection retrieval outcome.*match_mode=none.*embedding_present=true.*primary_threshold=0\.65.*fallback_threshold=0\.5.*surfaced=0/)
      )
    end

    # F1 (review of IMP-bfe8d1ef425e, 2026-09-18): a tiered fallback only
    # closes the observability gap this task exists to close if the HEALTHY
    # outcome is ALSO distinguishable from every unhealthy one. Staying silent
    # on primary-tier success (the pre-fix behavior) was byte-identical to
    # staying silent because the embedding service is down and every task is
    # quietly degrading — so the primary-served case must log too.
    it "logs the primary-tier-served (healthy) outcome too, so it's distinguishable from an outage" do
      allow(Rails.logger).to receive(:info)
      allow(Ai::CompoundLearning).to receive(:semantic_search) do |_embedding, **kwargs|
        [ with_distance(clears_primary, 0.2) ].select { |l| l.neighbor_distance <= 1.0 - kwargs[:threshold] }
      end

      service.build_compound_context(agent: nil, task_description: "primary tier probe")

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/injection retrieval outcome.*match_mode=semantic.*embedding_present=true.*fallback_threshold=n\/a.*surfaced=1/)
      )
    end

    # F1: the case with the widest blast radius — an embedding-service outage
    # degrading injection to keyword (or to nothing) — must be as visible as
    # the similarity-floor outcomes, not indistinguishable from either a clean
    # 0.65 match (silence) or a genuine similarity-floor withhold.
    it "logs embedding_present=false when the injection path degrades to keyword on a missing embedding" do
      allow(Rails.logger).to receive(:info)
      allow(embedding_service).to receive(:generate_or_nil).and_return(nil)
      create(:ai_compound_learning, account: account, status: "active", content: "caching queries pattern")

      service.build_compound_context(agent: nil, task_description: "caching queries")

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/injection retrieval outcome.*match_mode=keyword.*embedding_present=false.*fallback_threshold=n\/a/)
      )
    end

    it "logs embedding_present=false and match_mode=none when a missing embedding also finds no keyword hits" do
      allow(Rails.logger).to receive(:info)
      allow(embedding_service).to receive(:generate_or_nil).and_return(nil)

      service.build_compound_context(agent: nil, task_description: "zzzz nonexistent phrase qqqq")

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(/injection retrieval outcome.*match_mode=none.*embedding_present=false.*fallback_threshold=n\/a/)
      )
    end

    it "does not log on the RECALL surface, which has its own keyword fallback instead" do
      allow(Rails.logger).to receive(:info)
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([])

      service.search_learnings(query: "no match probe")

      expect(Rails.logger).not_to have_received(:info).with(a_string_matching(/injection retrieval outcome/))
    end

    # F3 (review of IMP-bfe8d1ef425e, 2026-09-18): both floors are
    # account-overridable, independently. If an account tightens its
    # injection floor to at-or-below its recall floor, the "fallback" tier is
    # no looser than primary — it can only ever reproduce primary's empty
    # result — so the retry must be skipped rather than paying a provably
    # useless duplicate query.
    describe "when the account's injection floor is not looser to fall back to (F3)" do
      before do
        account.update!(settings: (account.settings || {}).merge(
          "ai_learning_injection_similarity_threshold" => 0.4
        ))
      end

      let(:tight_service) { described_class.new(account: account.reload) }

      it "skips the retry query entirely and reports genuinely empty" do
        allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
        allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([])

        result = tight_service.build_compound_context(agent: nil, task_description: "no match probe")

        expect(result[:match_mode]).to eq("none")
        expect(Ai::CompoundLearning).to have_received(:semantic_search).once
      end

      it "logs fallback_threshold as the value that would have applied, not a looser one that never ran" do
        allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
        allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([])
        allow(Rails.logger).to receive(:info)

        tight_service.build_compound_context(agent: nil, task_description: "no match probe")

        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/injection retrieval outcome.*primary_threshold=0\.4.*fallback_threshold=0\.5.*surfaced=0/)
        )
      end
    end
  end

  describe "keyword-fallback rows (no neighbor_distance) still rank by quality alone" do
    before do
      allow(embedding_service).to receive(:generate_or_nil).and_return(nil)
    end

    it "does not raise when candidates carry no similarity signal" do
      create(:ai_compound_learning, account: account, status: "active",
             content: "caching queries pattern", importance_score: 0.6)

      expect {
        service.search_learnings(query: "caching queries")
      }.not_to raise_error
    end
  end
end
