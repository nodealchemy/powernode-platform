# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::CompoundLearningService, type: :service do
  let(:account) { create(:account) }
  let(:embedding_service) { instance_double(Ai::Memory::EmbeddingService) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:generate).and_return(nil)
  end

  describe "constants" do
    it "sets DEDUP_THRESHOLD to 0.92" do
      expect(described_class::DEDUP_THRESHOLD).to eq(0.92)
    end

    it "sets CHARS_PER_TOKEN to 4" do
      expect(described_class::CHARS_PER_TOKEN).to eq(4)
    end
  end

  describe "#post_execution_extract" do
    let(:team) { create(:ai_agent_team, account: account) }
    let(:execution) do
      double("TeamExecution",
             id: SecureRandom.uuid,
             status: "completed",
             agent_team: team,
             respond_to?: false)
    end

    before do
      allow(execution).to receive(:respond_to?).with(:agent_team).and_return(true)
      allow(execution).to receive(:respond_to?).with(:output_result).and_return(false)
      allow(execution).to receive(:respond_to?).with(:termination_reason).and_return(false)
      allow(execution).to receive(:respond_to?).with(:duration_ms).and_return(false)
      allow(execution).to receive(:respond_to?).with(:total_cost_usd).and_return(false)
      allow(execution).to receive(:respond_to?).with(:tasks_completed).and_return(false)
      allow(execution).to receive(:respond_to?).with(:tasks_failed).and_return(false)
      allow(execution).to receive(:respond_to?).with(:tasks_total).and_return(false)
    end

    it "returns nil for nil execution" do
      expect(service.post_execution_extract(nil)).to be_nil
    end

    it "extracts learnings from successful execution" do
      allow(execution).to receive(:respond_to?).with(:duration_ms).and_return(true)
      allow(execution).to receive(:duration_ms).and_return(2000)

      count = service.post_execution_extract(execution)
      expect(count).to be >= 0
    end

    it "extracts learnings from failed execution" do
      allow(execution).to receive(:status).and_return("failed")
      allow(execution).to receive(:respond_to?).with(:termination_reason).and_return(true)
      allow(execution).to receive(:termination_reason).and_return("Timeout error")

      count = service.post_execution_extract(execution)
      expect(count).to be >= 0
    end

    it "handles exceptions gracefully" do
      allow(execution).to receive(:status).and_raise(StandardError, "boom")

      expect(service.post_execution_extract(execution)).to eq(0)
    end
  end

  describe "#review_feedback_extract" do
    it "returns 0 for nil review" do
      expect(service.review_feedback_extract(nil)).to eq(0)
    end

    it "handles exceptions gracefully" do
      review = double("Review")
      allow(Ai::Learning::AutoExtractorService).to receive_message_chain(:new, :extract_from_review)
        .and_raise(StandardError, "extraction failed")

      expect(service.review_feedback_extract(review)).to eq(0)
    end
  end

  describe "#store_learning fallback dedup (no embedding)" do
    # Long enough that String#truncate(100) actually truncates and would
    # otherwise append a literal "..." omission. Includes a LIKE metacharacter
    # ("%") to exercise SQL-LIKE escaping in the fallback fragment.
    let(:long_content) do
      "Always 100% reuse existing infrastructure before building anything new, " \
      "and query the knowledge graph first to avoid duplicating prior learnings here."
    end

    let(:learning_data) do
      {
        content: long_content,
        category: "best_practice",
        importance: 0.6,
        confidence: 0.6
      }
    end

    before do
      # Embedding outage -> nil -> fallback text dedup path
      allow(embedding_service).to receive(:generate).and_return(nil)
    end

    it "dedupes against an existing identical learning instead of inserting a duplicate" do
      expect(long_content.length).to be > 100 # ensures truncate(100) kicks in

      first = service.send(:store_learning, learning_data)
      expect(first).to be_truthy

      expect {
        second = service.send(:store_learning, learning_data)
        expect(second).to be(false)
      }.not_to change { Ai::CompoundLearning.where(account_id: account.id).count }
    end
  end

  describe "#build_compound_context" do
    let(:agent) { create(:ai_agent, account: account) }

    context "when injection is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_injection, account).and_return(false)
      end

      it "returns empty context" do
        result = service.build_compound_context(
          agent: agent,
          task_description: "Build a feature"
        )

        expect(result[:context]).to be_nil
        expect(result[:token_estimate]).to eq(0)
        expect(result[:learning_ids]).to eq([])
      end
    end

    context "when injection is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_injection, account).and_return(true)
      end

      context "with no matching learnings" do
        it "returns empty context" do
          result = service.build_compound_context(
            agent: agent,
            task_description: "Something with no matches"
          )

          expect(result[:context]).to be_nil
          expect(result[:learning_ids]).to eq([])
        end
      end

      context "with matching learnings" do
        before do
          create(:ai_compound_learning,
                 account: account,
                 category: "best_practice",
                 title: "Use caching",
                 content: "Always use caching for repeated queries",
                 importance_score: 0.8,
                 status: "active")
        end

        it "builds context with learnings" do
          # Use keyword fallback since embedding returns nil
          result = service.build_compound_context(
            agent: agent,
            task_description: "caching queries"
          )

          if result[:context]
            expect(result[:context]).to include("Compound Learnings")
            expect(result[:token_estimate]).to be > 0
            expect(result[:learning_ids]).not_to be_empty
          end
        end

        it "records a neutral injection for each injected learning" do
          learning = Ai::CompoundLearning.find_by!(title: "Use caching")

          result = service.build_compound_context(
            agent: agent,
            task_description: "caching queries"
          )

          expect(result[:learning_ids]).to include(learning.id)
          learning.reload
          expect(learning.access_count).to eq(1)
          expect(learning.injection_count).to eq(1)
          expect(learning.last_injected_at).to be_within(5.seconds).of(Time.current)
          # Neutral: the outcome only resolves on later reinforcement
          expect(learning.positive_outcome_count).to eq(0)
          expect(learning.negative_outcome_count).to eq(0)
        end
      end

      it "respects token budget" do
        result = service.build_compound_context(
          agent: agent,
          task_description: "test",
          token_budget: 10
        )

        if result[:token_estimate] > 0
          expect(result[:token_estimate]).to be <= 10
        end
      end

      it "handles exceptions gracefully" do
        allow(embedding_service).to receive(:generate).and_raise(StandardError, "embedding error")

        result = service.build_compound_context(
          agent: agent,
          task_description: "test"
        )

        expect(result[:context]).to be_nil
        expect(result[:learning_ids]).to eq([])
      end
    end
  end

  describe "#top_relevant_learnings" do
    context "when injection is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_injection, account).and_return(false)
      end

      it "returns an empty array" do
        create(:ai_compound_learning, account: account, content: "caching queries pattern", status: "active")

        expect(service.top_relevant_learnings(task_description: "caching queries")).to eq([])
      end
    end

    context "when injection is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_injection, account).and_return(true)
      end

      it "returns an empty array for a blank task description" do
        expect(service.top_relevant_learnings(task_description: "")).to eq([])
      end

      it "returns an empty array with no matching learnings" do
        expect(service.top_relevant_learnings(task_description: "something with no matches")).to eq([])
      end

      it "returns lean summaries of matching learnings, reusing build_compound_context's ranking" do
        learning = create(:ai_compound_learning,
                          account: account,
                          category: "best_practice",
                          title: "Use caching",
                          content: "Always use caching for repeated queries",
                          importance_score: 0.8,
                          confidence_score: 0.7,
                          status: "active")

        results = service.top_relevant_learnings(task_description: "caching queries")

        expect(results.size).to eq(1)
        expect(results.first).to include(
          id: learning.id,
          category: "best_practice",
          title: "Use caching",
          confidence: 0.7
        )
        expect(results.first[:summary]).to include("caching")
      end

      it "caps results at k even when more candidates match" do
        6.times do |i|
          create(:ai_compound_learning, account: account, content: "caching pattern number #{i}",
                 importance_score: 0.5, status: "active")
        end

        results = service.top_relevant_learnings(task_description: "caching pattern", k: 3)

        expect(results.size).to eq(3)
      end

      it "bumps injection_count/access_count/last_injected_at on each surfaced learning" do
        learning = create(:ai_compound_learning, account: account, content: "caching queries pattern",
                          status: "active", injection_count: 0, access_count: 0)

        service.top_relevant_learnings(task_description: "caching queries")
        learning.reload

        expect(learning.injection_count).to eq(1)
        expect(learning.access_count).to eq(1)
        expect(learning.last_injected_at).to be_within(5.seconds).of(Time.current)
      end

      it "excludes retired learnings" do
        retained = create(:ai_compound_learning, account: account, status: "active", tags: ["dev-loop"],
                          content: "caching queries pattern", importance_score: 0.9)
        trading = create(:ai_compound_learning, account: account, status: "active", tags: ["trading"],
                         content: "caching queries trading pattern", importance_score: 0.95)
        service.retire_domain!("trading")

        results = service.top_relevant_learnings(task_description: "caching queries trading pattern")

        ids = results.map { |r| r[:id] }
        expect(ids).to include(retained.id)
        expect(ids).not_to include(trading.id)
      end

      it "handles exceptions gracefully" do
        allow(embedding_service).to receive(:generate).and_raise(StandardError, "embedding error")

        expect(service.top_relevant_learnings(task_description: "test")).to eq([])
      end
    end
  end

  describe "#boost_injected_learnings_on_success" do
    it "resolves recent neutral injections as positive outcomes without re-counting the injection" do
      learning = create(:ai_compound_learning,
                        account: account,
                        injection_count: 3,
                        positive_outcome_count: 2,
                        last_injected_at: 5.minutes.ago,
                        confidence_score: 0.5)
      execution = double("TeamExecution", created_at: 1.hour.ago)
      allow(execution).to receive(:respond_to?).with(:created_at).and_return(true)

      service.send(:boost_injected_learnings_on_success, execution)
      learning.reload

      expect(learning.injection_count).to eq(3)
      expect(learning.positive_outcome_count).to eq(3)
      expect(learning.effectiveness_score.to_f).to eq(1.0)
      expect(learning.confidence_score.to_f).to be_within(0.001).of(0.52)
    end

    it "skips learnings not injected since the execution started" do
      learning = create(:ai_compound_learning,
                        account: account,
                        injection_count: 2,
                        positive_outcome_count: 0,
                        last_injected_at: 2.days.ago)
      execution = double("TeamExecution", created_at: 1.hour.ago)
      allow(execution).to receive(:respond_to?).with(:created_at).and_return(true)

      service.send(:boost_injected_learnings_on_success, execution)

      expect(learning.reload.positive_outcome_count).to eq(0)
    end
  end

  describe "#promote_cross_team" do
    context "when promotion is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_promotion, account).and_return(false)
      end

      it "returns 0" do
        expect(service.promote_cross_team).to eq(0)
      end
    end

    context "when promotion is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_promotion, account).and_return(true)
      end

      it "returns 0 when no eligible candidates exist" do
        expect(service.promote_cross_team).to eq(0)
      end

      it "handles exceptions gracefully" do
        allow(Ai::CompoundLearning).to receive(:for_account).and_raise(StandardError, "query error")
        expect(service.promote_cross_team).to eq(0)
      end

      # find_similar returns a plain Array (its post-filter needs
      # neighbor_distance materialized), not an ActiveRecord::Relation.
      # promote_cross_team must not chain relation methods onto it.
      it "promotes when find_similar returns a non-global Array match" do
        candidate = create(:ai_compound_learning, account: account, scope: "team",
                            status: "active", importance_score: 0.8, confidence_score: 0.8,
                            access_count: 2, embedding: Array.new(1536, 0.1))
        team_scoped_match = create(:ai_compound_learning, account: account, scope: "team",
                                    status: "active")

        allow(Ai::CompoundLearning).to receive(:find_similar).and_return([team_scoped_match])

        result = nil
        expect { result = service.promote_cross_team }.not_to raise_error
        expect(result).to eq(1)
        expect(
          Ai::CompoundLearning.global_scope.for_account(account.id)
            .where("metadata->>'original_id' = ?", candidate.id.to_s)
        ).to exist
      end

      it "skips promotion when find_similar returns a global-scope Array match" do
        candidate = create(:ai_compound_learning, account: account, scope: "team",
                            status: "active", importance_score: 0.8, confidence_score: 0.8,
                            access_count: 2, embedding: Array.new(1536, 0.1))
        create(:ai_compound_learning, account: account, scope: "global", status: "active")

        global_match = build(:ai_compound_learning, account: account, scope: "global",
                              status: "active")
        allow(Ai::CompoundLearning).to receive(:find_similar).and_return([global_match])

        result = nil
        expect { result = service.promote_cross_team }.not_to raise_error
        expect(result).to eq(0)
        expect(
          Ai::CompoundLearning.global_scope.for_account(account.id)
            .where("metadata->>'original_id' = ?", candidate.id.to_s)
        ).not_to exist
      end

      it "includes verified (not just active) learnings in the candidate set" do
        candidate = create(:ai_compound_learning, account: account, scope: "team",
                            status: "verified", importance_score: 0.8, confidence_score: 0.8,
                            access_count: 2)

        result = nil
        expect { result = service.promote_cross_team }.not_to raise_error
        expect(result).to eq(1)
        expect(
          Ai::CompoundLearning.global_scope.for_account(account.id)
            .where("metadata->>'original_id' = ?", candidate.id.to_s)
        ).to exist
      end

      it "does not promote a sensor/reconcile-tick-style learning that meets importance+access but never earned confidence" do
        # Mirrors System::Fleet::LearningExtractor's decision-pattern rows:
        # reinforced repeatedly via record_access! (access_count climbs) and
        # boosted via boost_importance! (importance_score climbs), but
        # confidence_score is never touched by that reinforcement path and
        # stays at the unexamined default.
        create(:ai_compound_learning, account: account, scope: "team", status: "active",
               category: "discovery", importance_score: 1.0, confidence_score: 0.5,
               access_count: 50, tags: ["fleet", "autonomy", "system.config_drift"])

        expect(service.promote_cross_team).to eq(0)
        expect(Ai::CompoundLearning.global_scope.for_account(account.id)).not_to exist
      end

      it "does not promote a candidate with a measured poor effectiveness track record" do
        create(:ai_compound_learning, account: account, scope: "team", status: "active",
               importance_score: 0.8, confidence_score: 0.8, access_count: 2,
               injection_count: 5, positive_outcome_count: 1, effectiveness_score: 0.2)

        expect(service.promote_cross_team).to eq(0)
      end

      it "promotes a candidate with an unmeasured (nil) effectiveness score" do
        candidate = create(:ai_compound_learning, account: account, scope: "team", status: "active",
                            importance_score: 0.8, confidence_score: 0.8, access_count: 2,
                            effectiveness_score: nil)

        expect(service.promote_cross_team).to eq(1)
        expect(
          Ai::CompoundLearning.global_scope.for_account(account.id)
            .where("metadata->>'original_id' = ?", candidate.id.to_s)
        ).to exist
      end

    end
  end

  describe "#dedup_promoted_copies" do
    it "collapses duplicate promoted copies at the same scope, keeping the oldest" do
      keeper = create(:ai_compound_learning, account: account, scope: "global", status: "active",
                       content: "Promotion-optimal training session design", promoted_at: 2.days.ago,
                       created_at: 2.days.ago, access_count: 3, injection_count: 4, positive_outcome_count: 2)
      dup = create(:ai_compound_learning, account: account, scope: "global", status: "active",
                    content: "Promotion-optimal training session design", promoted_at: 1.day.ago,
                    created_at: 1.day.ago, access_count: 1, injection_count: 2, positive_outcome_count: 1)

      result = service.dedup_promoted_copies

      expect(result).to include(success: true, collapsed: 1, groups: 1)
      expect(dup.reload.status).to eq("superseded")
      expect(dup.superseded_by_id).to eq(keeper.id)
      keeper.reload
      expect(keeper.status).to eq("active")
      expect(keeper.access_count).to eq(4)
      expect(keeper.injection_count).to eq(6)
      expect(keeper.positive_outcome_count).to eq(3)
    end

    it "leaves non-duplicate promoted copies untouched" do
      solo = create(:ai_compound_learning, account: account, scope: "global", status: "active",
                     content: "Unique promoted content", promoted_at: 1.day.ago)

      result = service.dedup_promoted_copies

      expect(result).to include(success: true, collapsed: 0)
      expect(solo.reload.status).to eq("active")
    end

    it "does not group across different scopes even with identical content" do
      create(:ai_compound_learning, account: account, scope: "team", status: "active",
             content: "Shared content", promoted_at: 1.day.ago)
      create(:ai_compound_learning, account: account, scope: "global", status: "active",
             content: "Shared content", promoted_at: 1.day.ago)

      result = service.dedup_promoted_copies

      expect(result[:collapsed]).to eq(0)
    end

    it "ignores non-promoted rows (promoted_at nil) even if content matches" do
      create(:ai_compound_learning, account: account, scope: "team", status: "active",
             content: "Not yet promoted", promoted_at: nil)
      create(:ai_compound_learning, account: account, scope: "team", status: "active",
             content: "Not yet promoted", promoted_at: nil)

      result = service.dedup_promoted_copies

      expect(result[:collapsed]).to eq(0)
    end

    it "is idempotent — a second run finds nothing left to collapse" do
      create(:ai_compound_learning, account: account, scope: "global", status: "active",
             content: "Dup content", promoted_at: 2.days.ago, created_at: 2.days.ago)
      create(:ai_compound_learning, account: account, scope: "global", status: "active",
             content: "Dup content", promoted_at: 1.day.ago, created_at: 1.day.ago)

      first = service.dedup_promoted_copies
      second = service.dedup_promoted_copies

      expect(first[:collapsed]).to eq(1)
      expect(second[:collapsed]).to eq(0)
    end

    it "handles exceptions gracefully" do
      allow(Ai::CompoundLearning).to receive(:for_account).and_raise(StandardError, "query error")

      result = service.dedup_promoted_copies

      expect(result[:success]).to eq(false)
      expect(result[:collapsed]).to eq(0)
    end
  end

  describe "#verify_unverified_batch" do
    context "when scheduled verification is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_scheduled_verification, account).and_return(false)
      end

      it "no-ops and reports feature_disabled" do
        create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
               injection_count: 5, effectiveness_score: 0.9, confidence_score: 0.9)

        result = service.verify_unverified_batch

        expect(result).to include(success: true, feature_disabled: true, verified: 0, disputed: 0)
      end
    end

    context "when scheduled verification is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_scheduled_verification, account).and_return(true)
      end

      it "verifies a candidate with measured effectiveness+confidence above the promotion bars" do
        candidate = create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
                            injection_count: 5, effectiveness_score: 0.8, confidence_score: 0.9,
                            importance_score: 0.5)

        result = service.verify_unverified_batch

        expect(result).to include(success: true, verified: 1, disputed: 0, skipped: 0, remaining: 0)
        candidate.reload
        expect(candidate.status).to eq("verified")
        expect(candidate.verified_at).to be_present
        expect(candidate.verified_by_id).to be_nil
      end

      it "disputes a candidate with a measured poor effectiveness track record" do
        candidate = create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
                            injection_count: 5, effectiveness_score: 0.2, confidence_score: 0.9)

        result = service.verify_unverified_batch

        expect(result).to include(success: true, verified: 0, disputed: 1, skipped: 0)
        candidate.reload
        expect(candidate.status).to eq("disproven")
        expect(candidate.disproven_by_id).to be_nil
        expect(candidate.contradiction_note).to include("Automated verification pass")
      end

      it "skips a candidate with positive effectiveness but unproven confidence" do
        candidate = create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
                            injection_count: 5, effectiveness_score: 0.8, confidence_score: 0.5)

        result = service.verify_unverified_batch

        expect(result).to include(success: true, verified: 0, disputed: 0, skipped: 1)
        expect(candidate.reload.status).to eq("active")
        expect(candidate.reload.verified_at).to be_nil
      end

      it "leaves unmeasured (low injection_count) learnings alone regardless of scores" do
        candidate = create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
                            injection_count: 1, effectiveness_score: nil, confidence_score: 0.9)

        result = service.verify_unverified_batch

        expect(result).to include(verified: 0, disputed: 0)
        expect(candidate.reload.status).to eq("active")
      end

      it "skips already-verified learnings" do
        already_verified = create(:ai_compound_learning, account: account, status: "verified",
                                   verified_at: 1.day.ago, injection_count: 5, effectiveness_score: 0.9,
                                   confidence_score: 0.9)

        result = service.verify_unverified_batch

        expect(result[:verified]).to eq(0)
        expect(already_verified.reload.verified_at).to be_within(1.second).of(1.day.ago)
      end

      it "respects the batch cap and reports remaining" do
        3.times do
          create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
                 injection_count: 5, effectiveness_score: 0.8, confidence_score: 0.9)
        end

        result = service.verify_unverified_batch(max_per_run: 2)

        expect(result[:verified]).to eq(2)
        expect(result[:remaining]).to eq(1)
      end

      it "is idempotent — a second run finds nothing left to verify" do
        create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
               injection_count: 5, effectiveness_score: 0.8, confidence_score: 0.9)

        first = service.verify_unverified_batch
        second = service.verify_unverified_batch

        expect(first[:verified]).to eq(1)
        expect(second[:verified]).to eq(0)
        expect(second[:remaining]).to eq(0)
      end

      it "resolves batch size from Account#settings when max_per_run is omitted" do
        account.update!(settings: account.settings.merge("ai_learning_verify_batch_size" => 1))
        2.times do
          create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
                 injection_count: 5, effectiveness_score: 0.8, confidence_score: 0.9)
        end

        result = service.verify_unverified_batch

        expect(result[:verified]).to eq(1)
        expect(result[:remaining]).to eq(1)
      end

      it "continues processing when an individual learning fails" do
        good = create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
                       injection_count: 5, effectiveness_score: 0.8, confidence_score: 0.9)
        bad = create(:ai_compound_learning, account: account, status: "active", verified_at: nil,
                     injection_count: 5, effectiveness_score: 0.8, confidence_score: 0.9)

        # Block form of any_instance_of yields the receiving instance, so the
        # freshly-queried row (a different Ruby object than `bad` above, same
        # id) can still be identified and made to fail deterministically.
        allow_any_instance_of(Ai::CompoundLearning).to receive(:verify!) do |instance|
          raise StandardError, "DB error" if instance.id == bad.id

          instance.update!(status: "verified", verified_at: Time.current)
        end

        result = nil
        expect { result = service.verify_unverified_batch }.not_to raise_error
        expect(result[:verified]).to eq(1)
        expect(good.reload.status).to eq("verified")
        expect(bad.reload.status).to eq("active")
      end

      it "handles exceptions gracefully" do
        allow(Ai::CompoundLearning).to receive(:active).and_raise(StandardError, "query error")

        result = service.verify_unverified_batch

        expect(result[:success]).to eq(false)
        expect(result[:verified]).to eq(0)
      end
    end
  end

  describe "#reinforce_learning" do
    let!(:learning) do
      create(:ai_compound_learning, account: account, importance_score: 0.5, status: "active")
    end

    it "boosts importance of the learning" do
      result = service.reinforce_learning(learning.id)

      expect(result).to be_present
      expect(result.importance_score).to be > 0.5
    end

    it "returns nil for non-existent learning" do
      expect(service.reinforce_learning(SecureRandom.uuid)).to be_nil
    end

    it "returns nil for learning from another account" do
      other = create(:ai_compound_learning, account: create(:account))
      expect(service.reinforce_learning(other.id)).to be_nil
    end
  end

  describe "#decay_and_consolidate" do
    it "returns hash with decayed and archived counts" do
      result = service.decay_and_consolidate

      expect(result).to include(:decayed, :archived)
      expect(result[:decayed]).to be >= 0
      expect(result[:archived]).to be >= 0
    end

    it "decays old learnings" do
      old_learning = create(:ai_compound_learning,
                            account: account,
                            importance_score: 0.8,
                            status: "active",
                            updated_at: 10.days.ago)

      service.decay_and_consolidate

      old_learning.reload
      expect(old_learning.importance_score).to be < 0.8
    end

    it "archives very low importance old learnings" do
      stale_learning = create(:ai_compound_learning,
                              account: account,
                              importance_score: 0.05,
                              status: "active",
                              created_at: 60.days.ago,
                              updated_at: 60.days.ago)

      result = service.decay_and_consolidate

      stale_learning.reload
      expect(stale_learning.status).to eq("deprecated")
      expect(result[:archived]).to be >= 1
    end
  end

  describe "#backfill_embeddings" do
    it "embeds active rows with a nil embedding" do
      unembedded = create(:ai_compound_learning, account: account, status: "active", embedding: nil)
      vector = Array.new(1536) { 0.1 }
      allow(embedding_service).to receive(:generate_batch).and_return([ vector ])

      result = service.backfill_embeddings

      expect(result).to include(success: true, embedded: 1, failed: 0, remaining: 0)
      expect(unembedded.reload.embedding).not_to be_nil
    end

    it "counts a per-row generate failure without aborting the run" do
      create(:ai_compound_learning, account: account, status: "active", embedding: nil)
      create(:ai_compound_learning, account: account, status: "active", embedding: nil)
      allow(embedding_service).to receive(:generate_batch).and_return([ Array.new(1536) { 0.1 }, nil ])

      result = service.backfill_embeddings

      expect(result[:embedded]).to eq(1)
      expect(result[:failed]).to eq(1)
    end

    it "respects max_per_run and reports the remaining backlog" do
      3.times { create(:ai_compound_learning, account: account, status: "active", embedding: nil) }
      allow(embedding_service).to receive(:generate_batch).and_return([ Array.new(1536) { 0.1 } ])

      result = service.backfill_embeddings(max_per_run: 1)

      expect(result[:embedded]).to eq(1)
      expect(result[:remaining]).to eq(2)
    end

    it "excludes non-active rows from the backfill scope" do
      create(:ai_compound_learning, account: account, status: "deprecated", embedding: nil)
      expect(embedding_service).not_to receive(:generate_batch)

      result = service.backfill_embeddings

      expect(result).to eq(success: true, embedded: 0, failed: 0, remaining: 0)
    end
  end

  describe "#compound_metrics" do
    it "returns a metrics hash with expected keys" do
      metrics = service.compound_metrics

      expect(metrics).to include(
        :total_learnings, :active_learnings, :by_category,
        :by_scope, :avg_importance, :avg_effectiveness,
        :most_effective, :recently_added, :compound_score
      )
    end

    it "calculates compound score" do
      metrics = service.compound_metrics
      expect(metrics[:compound_score]).to be_a(Float)
    end

    context "with active learnings" do
      before do
        create_list(:ai_compound_learning, 3, account: account, status: "active")
      end

      it "counts active learnings" do
        metrics = service.compound_metrics
        expect(metrics[:active_learnings]).to eq(3)
      end
    end
  end

  describe "#store_learning event processing" do
    before do
      allow(WorkerJobService).to receive(:enqueue_ai_dedup_learning)
    end

    it "sets last_event_processed_at on newly created learnings" do
      service.store_learning(
        { content: "Test learning content", category: "pattern",
          title: "Test", extraction_method: "marker" }
      )

      learning = Ai::CompoundLearning.for_account(account.id).last
      expect(learning.last_event_processed_at).to be_within(2.seconds).of(Time.current)
    end

    it "sets last_event_processed_at on dedup boost via text fallback" do
      # Create an existing learning that will match text dedup
      existing = create(:ai_compound_learning, account: account,
                        content: "Existing learning content for dedup test",
                        status: "active")

      service.store_learning(
        { content: "Existing learning content for dedup test",
          category: "pattern", title: "Dupe", extraction_method: "marker" }
      )

      expect(existing.reload.last_event_processed_at).to be_within(2.seconds).of(Time.current)
    end

    # find_similar returns a plain Array; store_learning's contradiction-check
    # path must not chain relation methods (e.g. .where) onto it.
    it "detects a contradiction without raising when find_similar returns an Array" do
      embedding = Array.new(1536, 0.1)
      allow(embedding_service).to receive(:generate).and_return(embedding)

      successful_conflict = create(:ai_compound_learning, account: account,
                                    source_execution_successful: true, status: "active")

      allow(Ai::CompoundLearning).to receive(:find_similar)
        .with(embedding, account_id: account.id, threshold: described_class::DEDUP_THRESHOLD)
        .and_return([])
      allow(Ai::CompoundLearning).to receive(:find_similar)
        .with(embedding, account_id: account.id, threshold: described_class::CONFLICT_THRESHOLD_LOW)
        .and_return([successful_conflict])

      result = nil
      expect {
        result = service.store_learning(
          { content: "New failure learning content", category: "failure_mode",
            title: "Failure", extraction_method: "auto_failure",
            source_execution_successful: false }
        )
      }.not_to raise_error

      expect(result).to be_truthy
      expect(Rails.logger).to have_received(:info)
        .with(a_string_matching(/Potential contradiction detected with learning #{successful_conflict.id}/))
    end

    it "persists skill_node_ids metadata onto the created learning" do
      service.store_learning(
        { content: "Skill-attributed learning content", category: "pattern",
          title: "Attributed", extraction_method: "auto_success",
          metadata: { "skill_node_ids" => %w[skill-1 skill-2] } }
      )

      learning = Ai::CompoundLearning.for_account(account.id).last
      expect(learning.metadata["skill_node_ids"]).to eq(%w[skill-1 skill-2])
    end

    it "defaults metadata to an empty hash when the caller does not pass one" do
      service.store_learning(
        { content: "Unattributed learning content", category: "pattern",
          title: "Unattributed", extraction_method: "marker" }
      )

      learning = Ai::CompoundLearning.for_account(account.id).last
      expect(learning.metadata).to eq({})
    end
  end

  describe "#retire_domain!" do
    it "returns an error and retires nothing when domain is blank" do
      result = service.retire_domain!("")

      expect(result).to eq(success: false, error: "domain is required", retired_count: 0)
    end

    it "retires learnings tagged with the given domain, by tag or applicable_domains" do
      trading_by_tag = create(:ai_compound_learning, account: account, status: "active", tags: ["trading"])
      trading_by_domain = create(:ai_compound_learning, account: account, status: "verified", applicable_domains: ["trading"])
      other_domain = create(:ai_compound_learning, account: account, status: "active", tags: ["dev-loop"])

      result = service.retire_domain!("trading")

      expect(result).to eq(success: true, domain: "trading", retired_count: 2)
      expect(trading_by_tag.reload.status).to eq("retired")
      expect(trading_by_domain.reload.status).to eq("retired")
      expect(other_domain.reload.status).to eq("active")
    end

    it "records the domain and an optional reason on each retired learning" do
      learning = create(:ai_compound_learning, account: account, status: "active", tags: ["trading"])

      service.retire_domain!("trading", reason: "purged domain")

      learning.reload
      expect(learning.metadata["retired_domain"]).to eq("trading")
      expect(learning.metadata["retired_reason"]).to eq("purged domain")
    end

    it "does not retire learnings already deprecated/superseded/disproven (they don't surface today anyway)" do
      deprecated = create(:ai_compound_learning, :deprecated, account: account, tags: ["trading"])

      result = service.retire_domain!("trading")

      expect(result[:retired_count]).to eq(0)
      expect(deprecated.reload.status).to eq("deprecated")
    end

    it "does not hard-delete retired rows — they remain queryable for audit" do
      learning = create(:ai_compound_learning, account: account, status: "active", tags: ["trading"])

      service.retire_domain!("trading")

      expect(service.list_learnings(status: "retired")).to include(learning.reload)
    end

    it "leaves other accounts' learnings untouched" do
      other_account = create(:account)
      other_learning = create(:ai_compound_learning, account: other_account, status: "active", tags: ["trading"])

      service.retire_domain!("trading")

      expect(other_learning.reload.status).to eq("active")
    end

    it "handles exceptions gracefully" do
      allow(Ai::CompoundLearning).to receive(:for_account).and_raise(StandardError, "query error")

      result = service.retire_domain!("trading")

      expect(result[:success]).to eq(false)
      expect(result[:retired_count]).to eq(0)
    end

    context "surfacing exclusion" do
      let!(:retained) do
        create(:ai_compound_learning, account: account, status: "active", tags: ["dev-loop"],
               title: "Use caching", content: "Always use caching for repeated queries",
               importance_score: 0.9, effectiveness_score: 0.9)
      end
      let!(:trading) do
        create(:ai_compound_learning, account: account, status: "active", tags: ["trading"],
               title: "Trading pattern", content: "Trading strategy content",
               importance_score: 0.95, effectiveness_score: 0.95)
      end

      before { service.retire_domain!("trading") }

      it "excludes retired learnings from compound_metrics' most_effective ranking" do
        metrics = service.compound_metrics

        ids = metrics[:most_effective].map { |l| l[:id] }
        expect(ids).to include(retained.id)
        expect(ids).not_to include(trading.id)
      end

      it "excludes retired learnings from build_compound_context keyword-fallback retrieval" do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_injection, account).and_return(true)

        result = service.build_compound_context(agent: create(:ai_agent, account: account),
                                                  task_description: "trading strategy content")

        expect(result[:learning_ids]).not_to include(trading.id)
      end
    end
  end

  describe "#list_learnings" do
    before do
      create(:ai_compound_learning, account: account, category: "best_practice",
             status: "active", importance_score: 0.9)
      create(:ai_compound_learning, account: account, category: "anti_pattern",
             status: "active", importance_score: 0.3)
      create(:ai_compound_learning, account: account, category: "best_practice",
             status: "deprecated", importance_score: 0.3)
    end

    it "returns all learnings by default" do
      results = service.list_learnings
      expect(results.length).to eq(3)
    end

    it "filters by status" do
      results = service.list_learnings(status: "active")
      expect(results.length).to eq(2)
    end

    it "filters by category" do
      results = service.list_learnings(category: "best_practice")
      expect(results.length).to eq(2)
    end

    it "filters by minimum importance" do
      results = service.list_learnings(min_importance: 0.5)
      expect(results.length).to eq(1)
    end

    it "limits results" do
      results = service.list_learnings(limit: 1)
      expect(results.length).to eq(1)
    end
  end

  # IMP-3470890a626f — the MCP recall surface. Two pins the tool-level specs
  # cannot provide: the keyword fallback must surface VERIFIED learnings (the
  # most trusted tier — .active alone made status-less recall silently depend
  # on embedding availability), and the embedding-present branch must actually
  # route through semantic_search.
  describe "#search_learnings" do
    it "surfaces verified learnings on the keyword fallback" do
      # File-level before stubs the embedding double's generate to nil, which
      # is exactly the keyword-fallback condition.
      verified = create(:ai_compound_learning, account: account, status: "verified",
                        content: "Widget reconciliation must be idempotent")

      results = service.search_learnings(query: "widget reconciliation")

      expect(results.map(&:id)).to include(verified.id)
    end

    it "routes through semantic_search when an embedding is available" do
      learning = create(:ai_compound_learning, account: account, status: "active",
                        content: "Semantic-only match, no keyword overlap")
      embedding = Array.new(1536, 0.1)
      # The file-level before replaces EmbeddingService.new with a shared
      # double — stub THAT double, not any_instance (which can never reach it).
      allow(embedding_service).to receive(:generate).and_return(embedding)
      allow(Ai::CompoundLearning).to receive(:semantic_search).and_return([ learning ])

      results = service.search_learnings(query: "completely different wording")

      # No .with on the kwargs: RSpec's recorded-kwargs comparison false-negatives
      # here (identical args print as "received 0 times"). Branch selection is
      # the load-bearing pin; the call's own args belong to semantic_search's
      # unit specs.
      expect(Ai::CompoundLearning).to have_received(:semantic_search)
      expect(results.map(&:id)).to eq([ learning.id ])
    end
  end
end
