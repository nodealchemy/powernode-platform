# frozen_string_literal: true

module Ai
  module Learning
    class CompoundLearningService
      DEDUP_THRESHOLD = 0.92
      CONFLICT_THRESHOLD_LOW = 0.7
      CHARS_PER_TOKEN = 4

      # Interim injection cap (evaluation 2026-09-18 section 1.2 / item 3): both
      # injection consumers (#build_compound_context and #top_relevant_learnings)
      # truncated content to 200 chars while the live store's median entry is
      # 1,078 chars, so most learnings arrived as their first sentence. 600 is a
      # stopgap raise, not the final number — item 5 in the same evaluation
      # proposes a write-side shape contract (dev_complete_task.learning capped
      # at a `rule`/`why` pair, ~40-1,200 chars) that this constant should track
      # once it lands; until then this is what the token budget already allows.
      INJECTION_CONTENT_CHAR_CAP = 600

      # Cross-team/global promotion quality gate. importance_score + access_count
      # alone are not sufficient evidence of "genuinely reusable" — importance is
      # cheaply inflated by same-source reinforcement (e.g. a sensor/reconcile-tick
      # pattern bumping its own access_count on every tick via record_access!,
      # never actually recalled into another execution's context), and neither
      # field is touched by that reinforcement path's confidence. Two extra
      # checks, both matching thresholds already established elsewhere in this
      # codebase rather than inventing new numbers:
      #   - MIN_PROMOTION_CONFIDENCE: every extraction path derived from a real
      #     observed outcome (auto_failure, review, evaluation, team_execution)
      #     seeds confidence >= 0.7; only default-seeded, never-corroborated
      #     entries (fleet reconcile-tick "manual" creates, raw ralph_loop
      #     harvests) sit at the unexamined 0.5 default. Matches
      #     Ai::KnowledgeDocSyncService::LEARNING_MIN_CONFIDENCE (the existing
      #     bar for "confident enough to surface in shared docs" — promotion is
      #     at least as strict).
      #   - MIN_PROMOTION_EFFECTIVENESS: once a learning has enough injections to
      #     have a *measured* effectiveness_score (see #recalculate_effectiveness!,
      #     injection_count >= 3), a poor track record should block promotion
      #     even if importance/confidence are high; unmeasured (nil) is not held
      #     against it. Matches Ai::SkillGraph::EvolutionProposalService::LOW_EFFECTIVENESS_THRESHOLD.
      MIN_PROMOTION_CONFIDENCE = 0.7
      MIN_PROMOTION_EFFECTIVENESS = 0.4

      # Scheduled verification pass (C4): a learning only has a *measured*
      # effectiveness_score once #recalculate_effectiveness! has run, which
      # requires this many injections — below it there's no real outcome
      # evidence yet, so the pass leaves the learning alone rather than
      # guessing. Matches CompoundLearning#recalculate_effectiveness!.
      MIN_VERIFICATION_SAMPLE = 3
      DEFAULT_VERIFY_BATCH_SIZE = 100

      # Recall (D7). Similarity floor for the semantic branch of
      # #search_learnings (fallback: :on_empty), and the size of the candidate
      # window it pulls before ranking. #ranked_learning_candidates — the
      # INJECTION entry point — uses DEFAULT_INJECTION_SIMILARITY_THRESHOLD
      # below instead (D3.2). Overridable per account via
      # Account#settings["ai_learning_recall_similarity_threshold"], matching
      # the ai_learning_cluster_* thresholds in
      # Ai::Learning::LearningClusterService (Account#settings -> constant
      # fallback). The default is the value the floor was hardcoded to.
      DEFAULT_RECALL_SIMILARITY_THRESHOLD = 0.5

      # Injection (evaluation 2026-09-18 §1.1 / design D3.2). The recall floor
      # above is deliberately loose — a caller reading results can discount a
      # weak match. Injection has no such backstop: every surfaced row is
      # counted (record_injection!) and later credited on task success
      # (credit_injections! / boost_injected_learnings_on_success), which is
      # exactly the feedback loop that let a handful of heavily-credited,
      # weakly-similar rows dominate every task regardless of relevance.
      # Injection therefore needs a tighter floor than recall. Overridable via
      # Account#settings["ai_learning_injection_similarity_threshold"], same
      # convention as the recall threshold above.
      DEFAULT_INJECTION_SIMILARITY_THRESHOLD = 0.65
      SEMANTIC_CANDIDATE_LIMIT = 30

      def initialize(account:)
        @account = account
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
        @auto_extractor = AutoExtractorService.new(account: account)
      end

      # ==================================================
      # Extraction Phase
      # ==================================================

      # Called after any team execution completes or fails
      def post_execution_extract(execution)
        return unless execution

        team = execution.respond_to?(:agent_team) ? execution.agent_team : nil
        status = execution.status
        successful = status == "completed"

        learnings = []

        # 1. Marker-based extraction (backward compat with SharedLearningService)
        if successful && execution.respond_to?(:output_result)
          output = execution.output_result
          storage = Ai::Memory::StorageService.new(account: @account)
          markers = storage.extract_learnings_from_output(output: output)
          markers.each do |m|
            learnings << m.merge(
              extraction_method: "marker",
              source_execution_successful: true
            )
          end
        end

        # 2. Pattern-based extraction
        metadata = build_execution_metadata(execution)
        if successful
          learnings += @auto_extractor.extract_from_success(
            output: execution.respond_to?(:output_result) ? execution.output_result : nil,
            metadata: metadata
          ).map { |l| l.merge(source_execution_successful: true) }
        else
          error = execution.respond_to?(:termination_reason) ? execution.termination_reason : "Unknown error"
          learnings += @auto_extractor.extract_from_failure(
            error: error,
            metadata: metadata
          ).map { |l| l.merge(source_execution_successful: false) }
        end

        # 3. Evaluation-based extraction
        eval_learnings = @auto_extractor.extract_from_evaluations(execution_id: execution.id)
        learnings += eval_learnings.map { |l| l.merge(source_execution_successful: successful) }

        # 4. Store each learning with deduplication
        stored_count = 0
        learnings.each do |learning_data|
          stored = store_learning(
            learning_data,
            team: team,
            execution: execution
          )
          stored_count += 1 if stored
        end

        # 5. Boost confidence for previously injected learnings on successful outcome
        boost_injected_learnings_on_success(execution) if successful

        Rails.logger.info("[CompoundLearning] Extracted #{stored_count} learnings from execution #{execution.id}")

        # 6. Trigger experience replay capture for successful high-quality executions
        if successful && execution_quality_sufficient?(execution)
          begin
            WorkerJobService.enqueue_ai_experience_replay_capture(execution.id)
          rescue StandardError => e
            Rails.logger.warn("[CompoundLearning] Failed to enqueue experience replay: #{e.message}")
          end
        end

        # 7. Trigger reflexion for failed executions
        unless successful
          begin
            reflexion_service = Ai::Learning::ReflexionService.new(account: @account)
            if reflexion_service.should_reflect?(execution)
              WorkerJobService.enqueue_ai_reflexion(execution.id)
            end
          rescue StandardError => e
            Rails.logger.warn("[CompoundLearning] Failed to enqueue reflexion: #{e.message}")
          end
        end

        stored_count
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Extraction failed: #{e.message}")
        0
      end

      # Called after review rejection/revision
      def review_feedback_extract(review)
        return 0 unless review

        learnings = @auto_extractor.extract_from_review(review)

        team = review.team_task&.team_execution&.agent_team
        execution = review.team_task&.team_execution

        stored_count = 0
        learnings.each do |learning_data|
          stored = store_learning(learning_data, team: team, execution: execution)
          stored_count += 1 if stored
        end

        Rails.logger.info("[CompoundLearning] Extracted #{stored_count} learnings from review #{review.id}")
        stored_count
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Review extraction failed: #{e.message}")
        0
      end

      # ==================================================
      # Context Injection Phase (feature-flagged)
      # ==================================================

      def build_compound_context(agent:, task_description:, token_budget: 2000)
        return { context: nil, token_estimate: 0, learning_ids: [], match_mode: nil } unless injection_enabled?

        char_budget = token_budget * CHARS_PER_TOKEN
        learning_ids = []

        ranked, match_mode = ranked_learning_candidates(task_description)
        return { context: nil, token_estimate: 0, learning_ids: [], match_mode: match_mode } if ranked.empty?

        # Build context string within budget
        lines = ["## Compound Learnings"]
        used_chars = lines.first.length + 2

        ranked.each do |learning|
          category_label = "[#{learning.category}]"
          freshness = learning_freshness(learning.updated_at)
          freshness_label = freshness == "fresh" ? "" : " [#{freshness}]"
          line = "- #{category_label}#{freshness_label} #{learning.title || learning.content.truncate(100)}: #{learning.content.truncate(INJECTION_CONTENT_CHAR_CAP)}"
          break if used_chars + line.length > char_budget

          lines << line
          used_chars += line.length + 1
          learning_ids << learning.id
          learning.record_access!
          # Recall-driven crediting: record a neutral injection now; the outcome
          # resolves via boost_injected_learnings_on_success (positive) or stays
          # unresolved. Without this, injection_count/effectiveness never move on
          # the recall path and effectiveness metrics starve.
          learning.record_injection!
        end

        return { context: nil, token_estimate: 0, learning_ids: [], match_mode: match_mode } if lines.size == 1

        context = lines.join("\n")
        {
          context: context,
          token_estimate: (used_chars / CHARS_PER_TOKEN.to_f).ceil,
          learning_ids: learning_ids,
          match_mode: match_mode
        }
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Context build failed: #{e.message}")
        { context: nil, token_estimate: 0, learning_ids: [], match_mode: nil }
      end

      # Lean, top-k relevant learnings for a caller that wants a small structured
      # list rather than a formatted context block — e.g. Ai::Tools::DevLoopTool's
      # dev_next_task, injecting prior learnings into the primary (Claude Code)
      # executor's payload the same way build_compound_context already does for
      # platform-agent executions. Reuses the identical retrieval/ranking
      # (embedding search at the injection similarity floor, tiered fallback to
      # the recall floor on an empty primary tier -> keyword fallback on
      # missing embedding only -> similarity x effective_importance rank via
      # #ranking_score, both of which already restrict to the active/verified
      # surfacing set — retired learnings never reach either) so the two
      # consumers can't drift apart. match_mode is intentionally not threaded
      # into this method's return value (an Array, unlike build_compound_context's
      # Hash) — the shared retrieval already logs a fallback/empty outcome
      # regardless of what either caller does with it, so nothing here is
      # silently lost by not widening this consumer's return shape.
      # Bumps injection_count/last_injected on each surfaced learning exactly like
      # build_compound_context, so usage from either path feeds the same
      # effectiveness accrual. Summaries only (truncated title/content) to keep
      # the payload lean.
      def top_relevant_learnings(task_description:, k: 5)
        return [] unless injection_enabled?
        return [] if task_description.blank?

        ranked, _match_mode = ranked_learning_candidates(task_description)
        ranked = ranked.first(k)
        return [] if ranked.empty?

        ranked.map do |learning|
          learning.record_access!
          learning.record_injection!
          {
            id: learning.id,
            category: learning.category,
            title: learning.title || learning.content.truncate(100),
            summary: learning.content.truncate(INJECTION_CONTENT_CHAR_CAP),
            confidence: learning.confidence_score,
            effectiveness: learning.effectiveness_score
          }
        end
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] top_relevant_learnings failed: #{e.message}")
        []
      end

      # ==================================================
      # Compounding Phase (feature-flagged)
      # ==================================================

      def promote_cross_team(min_importance: 0.7)
        return 0 unless promotion_enabled?

        candidates = Ai::CompoundLearning
          .for_account(@account.id)
          # Surfacing set (see .semantic_search / .find_similar) — was status:
          # "active" only, which wrongly excluded verified learnings from ever
          # being promoted.
          .where(status: %w[active verified])
          .team_scope
          .where("importance_score >= ?", min_importance)
          .where("access_count >= ?", 2)
          .where("confidence_score >= ?", MIN_PROMOTION_CONFIDENCE)
          .where("effectiveness_score IS NULL OR effectiveness_score >= ?", MIN_PROMOTION_EFFECTIVENESS)

        promoted_count = 0

        candidates.find_each do |learning|
          # Check if already promoted globally. Drop truncate's "..." omission
          # and escape LIKE metacharacters so the fragment matches literally.
          fragment = ActiveRecord::Base.sanitize_sql_like(learning.content.truncate(100, omission: ""))
          existing_global = Ai::CompoundLearning.active
            .for_account(@account.id)
            .global_scope
            .where("content ILIKE ?", "%#{fragment}%")

          # find_similar returns an Array, not a Relation — replicate the
          # global_scope predicate with Array#any? instead of chaining .or().
          if learning.embedding.present?
            similar = Ai::CompoundLearning.find_similar(
              learning.embedding,
              account_id: @account.id,
              threshold: DEDUP_THRESHOLD
            )
            next if similar.any? { |l| l.scope == "global" }
          end

          next if existing_global.exists?

          Ai::CompoundLearning.create!(
            account: @account,
            category: learning.category,
            content: learning.content,
            title: learning.title,
            importance_score: learning.importance_score,
            confidence_score: learning.confidence_score,
            scope: "global",
            extraction_method: learning.extraction_method,
            tags: learning.tags,
            applicable_domains: learning.applicable_domains,
            embedding: learning.embedding,
            promoted_at: Time.current,
            metadata: { promoted_from_team: learning.ai_agent_team_id, original_id: learning.id }
          )
          promoted_count += 1
        end

        Rails.logger.info("[CompoundLearning] Promoted #{promoted_count} learnings to global scope")
        promoted_count
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Promotion failed: #{e.message}")
        0
      end

      # Collapses duplicate PROMOTED copies (rows with promoted_at present) that
      # share identical content at the same scope. Both promotion write paths —
      # this service's #promote_cross_team and the event-driven
      # Api::V1::Ai::LearningController#promote_learning action — guard against
      # creating a *new* duplicate at write time, but neither retroactively
      # cleans up copies that already exist (pre-dating those guards, or slipping
      # through one path while the other's independent check missed it). Never
      # hard-deletes: keeps the oldest row per duplicate group (closest to the
      # original promotion event) and marks the rest superseded_by it, folding
      # their reinforcement counters into the keeper so that signal isn't lost.
      # Mirrors System::Fleet::LearningExtractor#consolidate_legacy_rows!'s
      # oldest-keeper pattern. Restricting to status active/verified makes
      # repeated runs idempotent — once collapsed, duplicates carry status
      # "superseded" and drop out of the group scope.
      def dedup_promoted_copies(scope: nil)
        base = Ai::CompoundLearning
          .for_account(@account.id)
          .where(status: %w[active verified])
          .where.not(promoted_at: nil)
        base = base.where(scope: scope) if scope.present?

        groups = base.group(:scope, :content).having("COUNT(*) > 1").count

        collapsed = 0
        groups.each_key do |(dup_scope, content)|
          rows = base.where(scope: dup_scope, content: content).order(:created_at).to_a
          keeper = rows.first
          duplicates = rows.drop(1)
          next if duplicates.empty?

          folded_access = duplicates.sum(&:access_count)
          folded_injections = duplicates.sum(&:injection_count)
          folded_positive = duplicates.sum(&:positive_outcome_count)

          duplicates.each { |dup| dup.supersede!(keeper) }

          keeper.update_columns(
            access_count: keeper.access_count + folded_access,
            injection_count: keeper.injection_count + folded_injections,
            positive_outcome_count: keeper.positive_outcome_count + folded_positive
          )
          collapsed += duplicates.size
        end

        Rails.logger.info("[CompoundLearning] Collapsed #{collapsed} duplicate promoted copies across #{groups.size} groups")
        { success: true, collapsed: collapsed, groups: groups.size }
      rescue StandardError => e
        Rails.logger.error("[CompoundLearning] Dedup of promoted copies failed: #{e.message}")
        { success: false, error: e.message, collapsed: 0 }
      end

      # Scheduled quality-lifecycle pass (C4): verified_at is NULL corpus-wide
      # today because the only writer is the human/agent-directed
      # Ai::Tools::KnowledgeQualityTool (verify_learning/verify_learning_batch),
      # which requires an acting user — nothing runs it on a schedule, so the
      # corpus has no real quality signal (which #promote_cross_team's gate
      # and general trust depend on). This closes that gap with an
      # outcome-based heuristic (no LLM call, so no per-run cost) that reuses
      # the exact "trustworthy" bars #promote_cross_team already established
      # (MIN_PROMOTION_CONFIDENCE/EFFECTIVENESS) rather than inventing a
      # second judgment of the same signal:
      #   - effectiveness_score < MIN_PROMOTION_EFFECTIVENESS (a real, measured
      #     poor track record) -> disprove! (matches KnowledgeQualityTool's
      #     dispute_learning transition, just without a human-supplied reason)
      #   - effectiveness_score >= MIN_PROMOTION_EFFECTIVENESS AND
      #     confidence_score >= MIN_PROMOTION_CONFIDENCE -> verify!
      #   - otherwise (positive-enough outcome but unproven confidence) -> left
      #     alone; #verify! calls CompoundLearning directly (not through the
      #     tool), same as #promote_learning/#dedup_check/#update_graph_node.
      # Only considers learnings with a REAL measured outcome
      # (injection_count >= MIN_VERIFICATION_SAMPLE, the same bar
      # #recalculate_effectiveness! uses before effectiveness_score means
      # anything) — unmeasured learnings are left for a future run once
      # they've accrued enough injections, same "unmeasured is not held
      # against it" stance as the promotion gate.
      #
      # Gated behind :compound_learning_scheduled_verification (default OFF)
      # since — unlike the propose-only F5 evolution scan — this mutates
      # status/importance/confidence directly; batch size is
      # Account#settings-resolved (ai_learning_verify_batch_size) with a
      # constant fallback, per the config-driven-config convention already
      # established by Ai::ModelRefusalPromotionService.
      def verify_unverified_batch(max_per_run: nil)
        unless scheduled_verification_enabled?
          return { success: true, feature_disabled: true, reason: "compound_learning_scheduled_verification feature flag disabled",
                    verified: 0, disputed: 0, remaining: 0 }
        end

        cap = (max_per_run.presence || verify_batch_size).to_i.clamp(1, 1_000)

        scope = Ai::CompoundLearning.active
          .for_account(@account.id)
          .where(verified_at: nil)
          .where("injection_count >= ?", MIN_VERIFICATION_SAMPLE)

        pending = scope.count
        # find_each ignores .limit, so materialize the bounded slice. Oldest
        # first so the longest-waiting candidates get judged first across runs.
        batch = scope.order(:created_at).limit(cap).to_a
        remaining = [pending - batch.size, 0].max

        verified = 0
        disputed = 0

        batch.each do |learning|
          if learning.effectiveness_score.to_f < MIN_PROMOTION_EFFECTIVENESS
            learning.disprove!(
              reason: "Automated verification pass: effectiveness #{learning.effectiveness_score.to_f.round(2)} " \
                      "below trust threshold after #{learning.injection_count} injections"
            )
            disputed += 1
          elsif learning.confidence_score.to_f >= MIN_PROMOTION_CONFIDENCE
            learning.verify!
            verified += 1
          end
          # else: positive-enough effectiveness but unproven confidence — leave unverified for now.
        rescue StandardError => e
          Rails.logger.warn("[CompoundLearning] Scheduled verification failed for #{learning.id}: #{e.message}")
        end

        skipped = batch.size - verified - disputed
        Rails.logger.info("[CompoundLearning] Scheduled verification: verified=#{verified} disputed=#{disputed} skipped=#{skipped} remaining=#{remaining}")
        { success: true, verified: verified, disputed: disputed, skipped: skipped, remaining: remaining }
      rescue StandardError => e
        Rails.logger.error("[CompoundLearning] Scheduled verification batch failed: #{e.message}")
        { success: false, error: e.message, verified: 0, disputed: 0, remaining: 0 }
      end

      # Create a learning from team execution coordination results
      def create_from_team_execution(team_execution, results)
        return 0 unless team_execution && results

        stored_count = 0
        team = team_execution.respond_to?(:agent_team) ? team_execution.agent_team : nil
        outputs = results[:outputs] || []

        # Extract coordination pattern learning
        if outputs.size > 1
          strategy = team&.team_type || "unknown"
          tasks_completed = results[:tasks_completed] || 0
          tasks_failed = results[:tasks_failed] || 0
          success_rate = tasks_completed.to_f / [outputs.size, 1].max

          if success_rate >= 0.8
            stored = store_learning({
              title: "Team coordination: #{strategy} strategy with #{outputs.size} members",
              content: "Team '#{team&.name}' used #{strategy} strategy. #{tasks_completed}/#{outputs.size} tasks succeeded (#{(success_rate * 100).round}%). " \
                       "Roles involved: #{outputs.map { |o| o[:role] }.compact.uniq.join(', ')}. " \
                       "Total cost: $#{results[:total_cost]&.round(4)}.",
              category: "pattern",
              importance: [success_rate, 0.7].min,
              confidence: [success_rate, 0.8].min,
              extraction_method: "team_execution",
              tags: ["team", strategy, team&.name].compact,
              source_execution_successful: true
            }, team: team, execution: team_execution)
            stored_count += 1 if stored
          end

          # Extract failure pattern if any tasks failed
          if tasks_failed.positive?
            failed_agents = outputs.select { |o| o[:output].nil? }.map { |o| o[:agent_name] }
            stored = store_learning({
              title: "Team failure pattern: #{failed_agents.join(', ')} in #{strategy}",
              content: "#{tasks_failed} out of #{outputs.size} team members failed during #{strategy} execution. " \
                       "Failed agents: #{failed_agents.join(', ')}. Team: #{team&.name}.",
              category: "failure_mode",
              importance: 0.6,
              confidence: 0.7,
              extraction_method: "team_execution",
              tags: ["team", "failure", strategy].compact,
              source_execution_successful: false
            }, team: team, execution: team_execution)
            stored_count += 1 if stored
          end
        end

        Rails.logger.info("[CompoundLearning] Extracted #{stored_count} learnings from team execution")
        stored_count
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Team execution learning extraction failed: #{e.message}")
        0
      end

      # Backfill vector embeddings for active CompoundLearning rows stored without
      # one. `store_learning` generates the embedding synchronously via the
      # worker; if the embedding service was unavailable at that moment the row
      # is still persisted with embedding: nil (`content.blank?` is the only
      # guard) and is then permanently invisible to `find_similar` /
      # `semantic_search` (both require an embedding via `nearest_neighbors`),
      # so dedup no-ops as `no_embedding` and cross-team promotion never sees
      # it. Nothing else ever fixes it. Mirrors
      # Ai::Memory::SharedKnowledgeService#backfill_embeddings: idempotent,
      # batched, capped so the worker's HTTP timeout (120s) can't kill it
      # mid-batch, invoked by the compound maintenance endpoint so coverage
      # self-heals. Oldest rows recover first.
      def backfill_embeddings(batch_size: 50, max_per_run: 200)
        # The SURFACING set, not `.active`: a VERIFIED row stored without an
        # embedding was never repaired here, so the most trusted tier stayed
        # permanently invisible to nearest_neighbors — the same omission the
        # keyword fallback below already had to fix once. Same constant as both
        # recall branches so they cannot drift again.
        scope = Ai::CompoundLearning.surfacing
          .for_account(@account.id)
          .where(embedding: nil)

        pending = scope.count
        return { success: true, embedded: 0, failed: 0, remaining: 0 } if pending.zero?

        # `find_each` ignores .limit, so materialize the bounded batch.
        batch = scope.order(:created_at).limit(max_per_run).to_a
        embedded = 0
        failed = 0

        batch.each_slice(batch_size) do |slice|
          texts = slice.map { |learning| [ learning.title, learning.content ].compact_blank.join("\n\n") }
          vectors = @embedding_service.generate_batch(texts)

          slice.each_with_index do |learning, i|
            vector = vectors[i]
            if vector
              learning.update_columns(embedding: vector, last_event_processed_at: Time.current)
              embedded += 1
            else
              failed += 1
            end
          end
        end

        remaining = [ pending - embedded, 0 ].max
        Rails.logger.info("[CompoundLearning] Embedding backfill: #{embedded} embedded, #{failed} failed, #{remaining} remaining")
        { success: true, embedded: embedded, failed: failed, remaining: remaining }
      rescue StandardError => e
        Rails.logger.error("[CompoundLearning] Embedding backfill failed: #{e.message}")
        { success: false, error: e.message, embedded: 0, failed: 0, remaining: 0 }
      end

      def reinforce_learning(learning_id)
        learning = Ai::CompoundLearning.find_by(id: learning_id, account: @account)
        return unless learning

        learning.boost_importance!(0.05)
        learning.record_access!
        learning
      end

      # Periodic maintenance: decay old, archive stale, detect contradictions
      def decay_and_consolidate
        decayed = 0
        archived = 0
        skipped = 0

        # Decay old learnings (skip recently event-processed)
        scope = Ai::CompoundLearning.active.for_account(@account.id)
          .where("updated_at < ?", 7.days.ago)
          .where("last_event_processed_at IS NULL OR last_event_processed_at < ?", 24.hours.ago)

        scope.find_each do |learning|
          learning.decay_importance!
          decayed += 1
        end

        skipped = Ai::CompoundLearning.active.for_account(@account.id)
          .where("updated_at < ?", 7.days.ago)
          .where("last_event_processed_at >= ?", 24.hours.ago)
          .count

        # Archive very low importance learnings older than 30 days
        Ai::CompoundLearning.active.for_account(@account.id)
          .where("importance_score < ?", 0.1)
          .where("created_at < ?", 30.days.ago)
          .find_each do |learning|
            learning.deprecate!
            archived += 1
          end

        Rails.logger.info("[CompoundLearning] Maintenance: decayed=#{decayed} archived=#{archived} skipped_by_event=#{skipped}")
        { decayed: decayed, archived: archived, skipped_by_event: skipped }
      end

      # ==================================================
      # Lifecycle: Domain Retirement
      # ==================================================

      # Generic, domain-agnostic soft-retirement: excludes every learning
      # tagged/domained under `domain` from injection, retrieval, and ranking
      # by flipping status to "retired" (a status every surfacing query in
      # this class already restricts away from — semantic_search, find_similar,
      # keyword_search, and compound_metrics' active_base all scope to
      # active/verified). Never hard-deletes; retired rows remain queryable
      # via list_learnings(status: "retired") for audit.
      #
      # Scoped to active/verified because those are the only statuses that
      # ever surface (deprecated/superseded/disproven already carry their own
      # audit semantics and are excluded from surfacing today) — retiring them
      # too would just overwrite that history for no behavioral change.
      #
      # First caller: retiring the purged trading/Kalshi domain (see
      # lib/tasks/ai_learning.rake) — but this method takes domain as a
      # parameter, not a hardcoded value, so any future domain retirement
      # reuses it as-is.
      def retire_domain!(domain, reason: nil)
        return { success: false, error: "domain is required", retired_count: 0 } if domain.blank?

        scope = Ai::CompoundLearning
          .for_account(@account.id)
          .where(status: %w[active verified])
          .in_domain(domain)

        retired_count = 0
        scope.find_each do |learning|
          learning.retire!(domain: domain, reason: reason)
          retired_count += 1
        end

        Rails.logger.info("[CompoundLearning] Retired #{retired_count} learnings in domain '#{domain}' for account #{@account.id}")
        { success: true, domain: domain, retired_count: retired_count }
      rescue StandardError => e
        Rails.logger.error("[CompoundLearning] Domain retirement failed for '#{domain}': #{e.message}")
        { success: false, error: e.message, retired_count: 0 }
      end

      # ==================================================
      # Analytics
      # ==================================================

      def compound_metrics
        base = Ai::CompoundLearning.for_account(@account.id)
        active_base = base.active

        total = base.count
        active_count = active_base.count
        by_category = active_base.group(:category).count
        by_scope = active_base.group(:scope).count
        avg_importance = active_base.average(:importance_score)&.to_f&.round(4) || 0
        avg_effectiveness = active_base.where.not(effectiveness_score: nil).average(:effectiveness_score)&.to_f&.round(4)

        most_effective = active_base
          .where.not(effectiveness_score: nil)
          .order(effectiveness_score: :desc)
          .limit(5)
          .map(&:learning_summary)

        recently_added = active_base
          .order(created_at: :desc)
          .limit(10)
          .map(&:learning_summary)

        # Compound score: weighted combination of learning volume, effectiveness, and coverage
        coverage = by_category.keys.length.to_f / Ai::CompoundLearning::CATEGORIES.length
        effectiveness_factor = avg_effectiveness || 0.5
        volume_factor = [active_count / 50.0, 1.0].min
        compound_score = ((coverage * 0.3 + effectiveness_factor * 0.4 + volume_factor * 0.3) * 100).round(1)

        {
          total_learnings: total,
          active_learnings: active_count,
          by_category: by_category,
          by_scope: by_scope,
          avg_importance: avg_importance,
          avg_effectiveness: avg_effectiveness,
          most_effective: most_effective,
          recently_added: recently_added,
          compound_score: compound_score
        }
      end

      def list_learnings(filters = {})
        scope = build_learnings_scope(filters)

        if filters[:query].present?
          # Try semantic search first
          query_embedding = @embedding_service.generate(filters[:query])
          if query_embedding
            limit = filters[:limit] || 50
            return scope.active
              .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
              .limit(limit)
              .to_a
              .select { |e| e.neighbor_distance <= 0.6 }
          else
            scope = scope.where("content ILIKE ? OR title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(filters[:query])}%", "%#{ActiveRecord::Base.sanitize_sql_like(filters[:query])}%")
          end
        end

        scope = apply_sort(scope, filters)
        scope = scope.offset(filters[:offset]) if filters[:offset].to_i > 0
        scope.limit(filters[:limit] || 50)
      end

      def count_learnings(filters = {})
        scope = build_learnings_scope(filters)

        if filters[:query].present?
          query_embedding = @embedding_service.generate(filters[:query])
          if query_embedding
            return scope.active
              .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
              .limit(500)
              .to_a
              .count { |e| e.neighbor_distance <= 0.6 }
          else
            scope = scope.where("content ILIKE ? OR title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(filters[:query])}%", "%#{ActiveRecord::Base.sanitize_sql_like(filters[:query])}%")
          end
        end

        scope.count
      end

      # Store a learning with embedding generation and deduplication.
      # Returns true if a new learning was created, false if a near-duplicate was found and boosted.
      def store_learning(learning_data, team: nil, execution: nil)
        content = learning_data[:content]
        return false if content.blank?

        # Generate embedding for deduplication
        embedding = @embedding_service.generate(content)

        # Check for near-duplicates
        if embedding
          duplicates = Ai::CompoundLearning.find_similar(
            embedding,
            account_id: @account.id,
            threshold: DEDUP_THRESHOLD
          )

          if duplicates.any?
            # Boost existing instead of creating duplicate
            existing = duplicates.first
            existing.boost_importance!(0.03)
            existing.update!(
              confidence_score: [existing.confidence_score + 0.02, 1.0].min,
              metadata: existing.metadata.merge("last_duplicate_at" => Time.current.iso8601)
            )
            existing.touch_event_processed!
            return false
          end

          # Check for potential contradictions (similar content, opposite outcomes)
          if learning_data[:source_execution_successful] == false
            conflicts = Ai::CompoundLearning.find_similar(
              embedding,
              account_id: @account.id,
              threshold: CONFLICT_THRESHOLD_LOW
            ).select { |l| l.source_execution_successful }

            if conflicts.any?
              Rails.logger.info("[CompoundLearning] Potential contradiction detected with learning #{conflicts.first.id}")
            end
          end
        else
          # Fallback text dedup. truncate must drop its "..." omission, and the
          # fragment must escape LIKE metacharacters (% _) so it matches the
          # stored content literally; otherwise dedup never fires and duplicate
          # learnings accumulate during embedding outages.
          fragment = ActiveRecord::Base.sanitize_sql_like(content.truncate(100, omission: ""))
          existing = Ai::CompoundLearning.active
            .for_account(@account.id)
            .where("content ILIKE ?", "%#{fragment}%")
            .first

          if existing
            existing.boost_importance!(0.03)
            existing.touch_event_processed!
            return false
          end
        end

        # Create new learning
        new_learning = Ai::CompoundLearning.create!(
          account: @account,
          ai_agent_team: team,
          source_agent_id: learning_data[:source_agent_id] || learning_data[:agent_id],
          source_execution: execution,
          git_repository_id: learning_data[:git_repository_id], # Tier-2(d): portable repo scoping
          category: learning_data[:category],
          content: content,
          title: learning_data[:title],
          importance_score: learning_data[:importance] || 0.5,
          confidence_score: learning_data[:confidence] || 0.5,
          extraction_method: learning_data[:extraction_method],
          source_execution_successful: learning_data[:source_execution_successful],
          embedding: embedding,
          tags: learning_data[:tags] || [],
          metadata: learning_data[:metadata] || learning_data["metadata"] || {},
          scope: "team"
        )

        new_learning.touch_event_processed!

        # Enqueue async dedup check for the new learning
        begin
          WorkerJobService.enqueue_ai_dedup_learning(new_learning.id)
        rescue StandardError => e
          Rails.logger.warn("[CompoundLearning] Failed to enqueue dedup check: #{e.message}")
        end

        true
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[CompoundLearning] Failed to store learning: #{e.message}")
        false
      end

      # Resolve neutral injections positively by EXACT id — the dev-loop drain
      # path analog of boost_injected_learnings_on_success (private, below),
      # which infers membership from a time window on the agent-execution path.
      # The drain path knows precisely which learnings its claim injected
      # (task metadata), so no window heuristics. Public: called across the
      # service boundary by Ai::Tools::DevLoopTool#complete_task.
      # MCP recall surface (query_learnings): the same embedding-first
      # retrieval as context injection, but NOT the same rank or floor
      # (evaluation 2026-09-18 §1.1 / D3.2) — recall keeps the looser 0.5
      # similarity floor and ranks by effective_importance alone on the
      # keyword branch; injection uses the tighter 0.65 floor and weights by
      # similarity x effective_importance (#ranking_score) whenever a
      # candidate carries a neighbor_distance. Also WITHOUT record_injection!
      # — an MCP query has no completing execution to credit,
      # so counting it as an injection would depress effectiveness exactly the
      # way the uncredited dev-loop injections did (IMP-5f8a744b8892).
      # record_access! only (usage telemetry with no effectiveness impact).
      # Post-filters subset the retrieved candidate set (SEMANTIC_CANDIDATE_LIMIT
      # semantic / 20 keyword), so a tight filter can return fewer than limit —
      # acceptable for a recall surface; the no-query browse path in the tool
      # remains a plain filtered listing.
      #
      # Returns { learnings:, match_mode: }. match_mode names the RETRIEVAL
      # branch, before the post-filters — "semantic" with an empty learnings
      # array means the embedding branch found candidates and the filters
      # removed them, which is a different diagnosis from "none".
      def search_learnings(query:, category: nil, learning_scope: nil, status: nil, limit: 20)
        # `status` is pushed DOWN into both retrieval branches rather than
        # applied as a post-filter. As a post-filter it could only ever subset
        # a candidate set already restricted to the surfacing pair, so four of
        # the six statuses were unsatisfiable on the query path while the tool
        # advertised them and the no-query browse path returned them.
        candidates, match_mode = ranked_learning_candidates_with_mode(
          query.to_s,
          fallback: :on_empty,
          statuses: status.present? ? Array(status) : Ai::CompoundLearning::SURFACING_STATUSES
        )
        candidates = candidates.select { |l| l.category == category } if category.present?
        candidates = candidates.select { |l| l.scope == learning_scope } if learning_scope.present?

        { learnings: candidates.first(limit).each(&:record_access!), match_mode: match_mode }
      end

      def credit_injections!(learning_ids:)
        return if Array(learning_ids).empty?

        Ai::CompoundLearning.for_account(@account.id)
          .where(id: learning_ids, status: %w[active verified])
          .find_each do |learning|
            learning.record_positive_outcome!
            learning.update_column(:confidence_score, [ learning.confidence_score + 0.02, 1.0 ].min)
          end
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] credit_injections failed: #{e.message}")
      end

      private

      SORTABLE_COLUMNS = %w[created_at importance_score effectiveness_score injection_count confidence_score updated_at].freeze

      def build_learnings_scope(filters)
        scope = Ai::CompoundLearning.for_account(@account.id)
        scope = scope.where(status: filters[:status]) if filters[:status].present?
        scope = scope.by_category(filters[:category]) if filters[:category].present?
        scope = scope.where(scope: filters[:scope]) if filters[:scope].present?
        scope = scope.where("importance_score >= ?", filters[:min_importance]) if filters[:min_importance].present?
        scope = scope.for_team(filters[:team_id]) if filters[:team_id].present?
        scope
      end

      def apply_sort(scope, filters)
        column = SORTABLE_COLUMNS.include?(filters[:sort_by]) ? filters[:sort_by] : "created_at"
        direction = filters[:sort_dir] == "asc" ? :asc : :desc
        scope.order(column => direction)
      end

      def boost_injected_learnings_on_success(execution)
        # Find learnings injected into this execution (those with recent injection timestamps)
        execution_start = execution.respond_to?(:created_at) ? execution.created_at : 1.hour.ago
        recently_injected = Ai::CompoundLearning
          .for_account(@account.id)
          .where(status: %w[active verified])
          .where("injection_count >= ?", 1)
          .where("last_injected_at >= ?", execution_start)

        recently_injected.find_each do |learning|
          # Resolve the neutral injection recorded at recall as a positive
          # outcome (injection_count was already advanced by record_injection!).
          learning.record_positive_outcome!
          learning.update_column(:confidence_score, [learning.confidence_score + 0.02, 1.0].min)
        end
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] Confidence boost failed: #{e.message}")
      end

      def learning_freshness(updated_at)
        return "stale" unless updated_at

        age_days = (Time.current - updated_at) / 1.day
        if age_days < 7
          "fresh"
        elsif age_days < 30
          "aging"
        else
          "stale"
        end
      end

      def build_execution_metadata(execution)
        {
          duration_ms: execution.respond_to?(:duration_ms) ? execution.duration_ms : nil,
          total_cost_usd: execution.respond_to?(:total_cost_usd) ? execution.total_cost_usd : nil,
          tasks_completed: execution.respond_to?(:tasks_completed) ? execution.tasks_completed : nil,
          tasks_failed: execution.respond_to?(:tasks_failed) ? execution.tasks_failed : nil,
          tasks_total: execution.respond_to?(:tasks_total) ? execution.tasks_total : nil,
          team_name: execution.respond_to?(:agent_team) ? execution.agent_team&.name : nil
        }
      end

      # Shared retrieval + ranking for build_compound_context,
      # top_relevant_learnings and search_learnings: embedding search first,
      # keyword fallback, ranked by similarity x effective_importance on the
      # semantic branch (see #ranking_score) or effective_importance alone on
      # the keyword branch, which has no similarity signal to weight by. Both
      # retrieval paths already restrict to the active/verified surfacing set.
      # The INJECTION consumers' entry point. `fallback: :on_missing_embedding`
      # is deliberate — see the note on the mode parameter below. On the
      # injection path specifically, an empty primary-floor result additionally
      # retries once at the looser recall floor before giving up — see
      # #injection_floor_fallback.
      #
      # Returns [candidates, match_mode] — NOT just candidates. An earlier
      # version called `.first` here and discarded match_mode entirely, which
      # made a result served by the degraded fallback tier ("semantic_fallback")
      # exactly as invisible to callers as a genuinely empty result: both this
      # method's callers now capture it, even where a caller chooses not to
      # thread it any further (see #top_relevant_learnings).
      def ranked_learning_candidates(task_description)
        ranked_learning_candidates_with_mode(task_description, fallback: :on_missing_embedding)
      end

      # Returns [candidates, match_mode]. match_mode names the branch the rows
      # came from: "semantic", "semantic_fallback" (injection only — see
      # #injection_floor_fallback), "keyword", or "none" when nothing matched.
      #
      # D7 — on the RECALL surface the fallback fires whenever the semantic
      # branch yields NOTHING, not only when the query embedding is nil. An
      # embedding that succeeds but matches nothing above the floor is the
      # ordinary state of a corpus whose rows carry no embedding of their own
      # (stored during an embedding outage — see #backfill_embeddings):
      # nearest_neighbors cannot see them, so the old nil-only condition
      # returned an empty set with no keyword attempt and query_learnings
      # answered every keyword query with zero rows.
      #
      # THE MODE IS NOT COSMETIC. `fallback:` says which of the two rules
      # applies, and the two consumers genuinely need different ones:
      #   :on_empty              — recall (search_learnings -> query_learnings).
      #                            Read-only: it records access, never an
      #                            injection, so a loose keyword match costs
      #                            nothing but a caller's attention.
      #   :on_missing_embedding  — injection (build_compound_context,
      #                            top_relevant_learnings). Both call
      #                            record_injection! on every row they surface
      #                            and boost_injected_learnings_on_success
      #                            later credits those injections positively.
      #                            keyword_search ORs the first five words of
      #                            >= 3 characters, so on a prose task
      #                            description it is low precision; letting it
      #                            fire whenever the semantic branch merely
      #                            matched nothing would pour loosely matched
      #                            rows into injection_count/effectiveness —
      #                            the signal effective_importance ranks on.
      #                            A corpus with no embeddings gets semantic
      #                            recall back from the backfill task, not from
      #                            widened injection.
      #
      # #generate_or_nil, not #generate: #generate RAISES (EmbeddingError) when
      # the worker embedding service is down or has no provider credentials,
      # which escaped PAST the fallback in exactly the outage the fallback
      # exists for. The read-path wrapper degrades to nil and is what the other
      # search surfaces (SharedKnowledgeService, code_semantic_search) use.
      # Both modes keep that, so an outage still reaches the keyword branch.
      FALLBACK_MODES = %i[on_empty on_missing_embedding].freeze

      def ranked_learning_candidates_with_mode(task_description, fallback: :on_empty,
                                               statuses: Ai::CompoundLearning::SURFACING_STATUSES)
        unless FALLBACK_MODES.include?(fallback)
          raise ArgumentError, "unknown fallback mode #{fallback.inspect} (expected one of #{FALLBACK_MODES.inspect})"
        end

        query_embedding = @embedding_service.generate_or_nil(
          task_description,
          context: "CompoundLearningService#ranked_learning_candidates"
        )

        # fallback: :on_missing_embedding names the INJECTION consumers
        # (#ranked_learning_candidates, private, below); :on_empty names the
        # RECALL consumer (#search_learnings). The two need different
        # similarity floors (see DEFAULT_INJECTION_SIMILARITY_THRESHOLD) —
        # keying off the fallback mode reuses the seam that already
        # distinguishes them rather than adding a second parameter callers
        # could pass inconsistently.
        threshold = fallback == :on_missing_embedding ? injection_similarity_threshold : recall_similarity_threshold

        candidates = if query_embedding
          Ai::CompoundLearning.semantic_search(
            query_embedding,
            account_id: @account.id,
            threshold: threshold,
            limit: SEMANTIC_CANDIDATE_LIMIT,
            statuses: statuses
          ).to_a
        else
          []
        end

        match_mode = "semantic"
        fallback_threshold = nil
        if candidates.empty? && (fallback == :on_empty || query_embedding.nil?)
          candidates = keyword_search(task_description, statuses: statuses).to_a
          match_mode = candidates.any? ? "keyword" : "none"
        elsif candidates.empty?
          # This branch is reachable only when fallback == :on_missing_embedding
          # (the injection path) AND an embedding was generated — i.e. the
          # similarity floor, not a missing embedding, produced zero
          # candidates. Review of IMP-71ea81f5ab16 (2026-09-18) measured this
          # as common at the 0.65 injection floor (68% empty on a probe sized
          # like a real task description) — a legitimate withhold, but the
          # injection path has no keyword fallback to fall back on (see the
          # fallback-mode note above), so an empty primary tier meant the
          # agent ran with zero learnings. IMP-bfe8d1ef425e: retry once at the
          # looser recall floor rather than lowering the injection floor
          # outright (see #injection_floor_fallback for why precision-first
          # stays the default).
          candidates, match_mode, fallback_threshold = injection_floor_fallback(
            query_embedding: query_embedding, primary_threshold: threshold, statuses: statuses
          )
        end

        # F1 (review of IMP-bfe8d1ef425e, 2026-09-18): logged for ALL FOUR
        # injection outcomes, not just the two non-primary ones — a tiered
        # fallback only closes the observability gap this task exists to close
        # if the HEALTHY outcome is also distinguishable from every unhealthy
        # one. Before this line, silence on a primary-tier success was
        # byte-identical to silence on the worst case: the embedding service
        # being down, every task quietly degrading to keyword-only (or to
        # zero learnings), with match_mode and this log both absent either
        # way. Gated to the injection path only (:on_missing_embedding) —
        # recall (:on_empty) has its own keyword fallback and stays silent, as
        # a dedicated spec asserts.
        if fallback == :on_missing_embedding
          log_injection_outcome(
            task_description, match_mode: match_mode, embedding_present: !query_embedding.nil?,
            primary_threshold: threshold, fallback_threshold: fallback_threshold, surfaced: candidates.size
          )
        end

        [ candidates.sort_by { |l| -ranking_score(l) }, match_mode ]
      end

      # Tiered similarity floor for the injection path (IMP-bfe8d1ef425e,
      # follow-up to IMP-71ea81f5ab16). Reached only when the primary
      # injection floor (DEFAULT_INJECTION_SIMILARITY_THRESHOLD, 0.65)
      # produced zero candidates despite a real query embedding. Retrying
      # ONCE at the looser recall floor (DEFAULT_RECALL_SIMILARITY_THRESHOLD,
      # 0.5) — rather than simply lowering the injection floor to 0.5 — keeps
      # the precision gain IMP-71ea81f5ab16 bought for the common case (a
      # candidate clears 0.65) while stopping a legitimate-but-tight query
      # from costing an agent every learning. match_mode distinguishes the
      # two outcomes ("semantic_fallback" served vs "none" genuinely empty)
      # so a degraded-precision hit is as visible as a clean empty, never
      # silently indistinguishable from a primary-tier match.
      #
      # This retry doubles as A diagnostic the pre-fix code paid for
      # separately with an extra semantic_search call at threshold 0.0: it
      # tells us whether anything clears the loosest floor this service still
      # trusts for injection-adjacent ranking. It is a narrower question than
      # the old 0.0-threshold count answered — that count could distinguish
      # "corpus exists but is semantically distant" from "corpus empty or
      # unembedded"; surfaced=0 here collapses both into the same reading.
      # That narrower trade is the intended one (see the operator ruling this
      # task was scoped under), not a claim that this retry answers every
      # question the old diagnostic could.
      #
      # Returns [candidates, match_mode, fallback_threshold]. fallback_threshold
      # is returned even when the guard below skips the query, so the caller's
      # log line can report what the fallback floor WOULD have been.
      def injection_floor_fallback(query_embedding:, primary_threshold:, statuses:)
        fallback_threshold = recall_similarity_threshold

        # F3 (review of IMP-bfe8d1ef425e, 2026-09-18): both floors are
        # account-overridable (ai_learning_injection_similarity_threshold,
        # ai_learning_recall_similarity_threshold), independently. An account
        # that sets its injection floor at or below its recall floor makes
        # this "fallback" tier no looser than — or stricter than — primary:
        # every candidate that could clear it already had a chance to clear
        # primary, so the retry can only ever reproduce primary's empty
        # result. Skip the query rather than pay a provably useless duplicate
        # semantic_search call and log a "fallback" that was never actually
        # looser than what already ran.
        return [ [], "none", fallback_threshold ] if fallback_threshold >= primary_threshold

        fallback_candidates = Ai::CompoundLearning.semantic_search(
          query_embedding,
          account_id: @account.id,
          threshold: fallback_threshold,
          limit: SEMANTIC_CANDIDATE_LIMIT,
          statuses: statuses
        ).to_a

        match_mode = fallback_candidates.any? ? "semantic_fallback" : "none"
        [ fallback_candidates, match_mode, fallback_threshold ]
      end

      # Single log line covering every outcome of the INJECTION retrieval path
      # (fallback == :on_missing_embedding only; recall never calls this — see
      # the dedicated spec asserting that). embedding_present distinguishes a
      # "keyword"/"none" match_mode caused by a missing embedding (an outage —
      # see the #generate_or_nil note above) from a "none" caused by a real
      # embedding finding nothing at either similarity tier; primary_threshold/
      # fallback_threshold/surfaced give the same shape the previous
      # fallback-only log line carried. fallback_threshold is nil whenever the
      # fallback tier never ran (primary served, or the embedding was missing
      # and the branch never reached #injection_floor_fallback at all).
      def log_injection_outcome(task_description, match_mode:, embedding_present:, primary_threshold:,
                                fallback_threshold:, surfaced:)
        Rails.logger.info(
          "[CompoundLearning] injection retrieval outcome: " \
          "query_chars=#{task_description.to_s.length} match_mode=#{match_mode} " \
          "embedding_present=#{embedding_present} primary_threshold=#{primary_threshold} " \
          "fallback_threshold=#{fallback_threshold.nil? ? 'n/a' : fallback_threshold} surfaced=#{surfaced}"
        )
      rescue StandardError => e
        Rails.logger.warn("[CompoundLearning] log_injection_outcome failed: #{e.message}")
      end

      # Rank = similarity x quality (evaluation 2026-09-18 §1.1 / design D3.1).
      # Sorting by effective_importance alone — outcome counters, with only
      # positive outcomes ever recorded — let a handful of heavily-credited,
      # weakly-similar rows outrank a fresh, strongly-similar row on every
      # task: similarity gated candidates in, then got discarded. Similarity
      # dominates here (full weight); effective_importance only breaks ties
      # among comparably-similar rows (its term ranges 0.5-1.0).
      #
      # Rows with no neighbor_distance — the keyword-fallback branch, which has
      # no cosine distance to weight by, and any caller (real or test double)
      # that hands back a plain record instead of one selected via
      # Ai::CompoundLearning.semantic_search's nearest_neighbors chain — fall
      # back to quality alone, the pre-fix behavior. neighbor_distance is a
      # per-query SELECT alias (see the neighbor gem), not a real column, so
      # #respond_to? is the correct presence check: it is false on a plain
      # record and true only when the row actually came back with a distance.
      def ranking_score(learning)
        return learning.effective_importance unless learning.respond_to?(:neighbor_distance)

        similarity = 1.0 - learning.neighbor_distance
        similarity * (0.5 + 0.5 * learning.effective_importance)
      end

      # Account#settings -> constant fallback, matching
      # Ai::Learning::LearningClusterService#resolve_similarity_threshold.
      def recall_similarity_threshold
        value = setting("ai_learning_recall_similarity_threshold").presence || DEFAULT_RECALL_SIMILARITY_THRESHOLD
        value.to_f.clamp(0.0, 1.0)
      end

      # Same convention, injection-specific floor. See
      # DEFAULT_INJECTION_SIMILARITY_THRESHOLD for why injection needs a
      # tighter floor than recall.
      def injection_similarity_threshold
        value = setting("ai_learning_injection_similarity_threshold").presence || DEFAULT_INJECTION_SIMILARITY_THRESHOLD
        value.to_f.clamp(0.0, 1.0)
      end

      def keyword_search(query, statuses: Ai::CompoundLearning::SURFACING_STATUSES)
        return Ai::CompoundLearning.none if query.blank?

        keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
        return Ai::CompoundLearning.none if keywords.empty?

        # Parameterized, never string-built: sanitize_sql_like escapes LIKE
        # wildcards but NOT quotes, so interpolating it into a raw SQL string
        # broke (and was injectable) for any query containing an apostrophe —
        # which matters now that MCP query_learnings routes user-typed queries
        # here. Title included for parity with the old tool-side matcher.
        conditions = Array.new(keywords.size) { "(LOWER(title) LIKE ? OR LOWER(content) LIKE ?)" }.join(" OR ")
        patterns = keywords.flat_map { |kw| pattern = "%#{Ai::CompoundLearning.sanitize_sql_like(kw)}%"; [ pattern, pattern ] }
        # The same status set semantic_search uses, from the same constant
        # (Ai::CompoundLearning::SURFACING_STATUSES) so the two branches cannot
        # drift — `.active` alone once excluded the MOST TRUSTED tier from the
        # fallback, which made status-less recall silently depend on
        # embedding-service availability. A caller asking for a specific status
        # overrides it on BOTH branches, so a non-surfacing status is
        # answerable instead of silently unsatisfiable.
        Ai::CompoundLearning.where(status: Array(statuses))
          .for_account(@account.id)
          .where(conditions, *patterns)
          .order(importance_score: :desc)
          .limit(20)
      end

      def injection_enabled?
        Shared::FeatureFlagService.enabled?(:compound_learning_injection, @account)
      end

      def promotion_enabled?
        Shared::FeatureFlagService.enabled?(:compound_learning_promotion, @account)
      end

      def scheduled_verification_enabled?
        Shared::FeatureFlagService.enabled?(:compound_learning_scheduled_verification, @account)
      end

      def verify_batch_size
        configured = setting("ai_learning_verify_batch_size")
        (configured.presence || DEFAULT_VERIFY_BATCH_SIZE).to_i.clamp(1, 1_000)
      end

      # Account#settings → constant fallback, matching
      # Ai::ModelRefusalPromotionService's config-driven-config convention.
      def setting(key)
        s = @account&.settings
        return nil unless s.is_a?(Hash)

        s[key] || s[key.to_sym]
      end

      def execution_quality_sufficient?(execution)
        return false unless execution.respond_to?(:status) && execution.status == "completed"
        return false unless execution.respond_to?(:output_data) && execution.output_data.present?
        true
      end
    end
  end
end
